"""
Kart Live Timing Server
Scraping: Playwright (headless) | API: FastAPI WebSocket | Discovery: Bonjour/mDNS

MODIFICA MULTI-CLIENT
----------------------
Prima ogni client condivideva un unico scraper globale: cambiare URL da un
client cambiava la fonte per tutti. Ora ogni URL richiesto ha una propria
ScraperSession (proprio thread Playwright, proprio ultimo payload), e ogni
WebSocket connesso è associato alla sessione che sta guardando. I comandi
"set_url" e "get_status" agiscono solo sul client che li invia; i broadcast
vanno solo ai client iscritti a quell'URL. Le sessioni senza più iscritti
vengono fermate dopo un breve periodo di grazia per liberare risorse
(ogni sessione tiene aperto un browser headless).
"""

import asyncio
import json
import os
import socket
import tempfile
import hashlib
import time
import threading
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict
from urllib.parse import urlparse

from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from zeroconf import ServiceInfo, Zeroconf
from playwright.sync_api import sync_playwright

import uvicorn

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, log_level="info")


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SERVICE_TYPE  = "_karttiming._tcp.local."
SERVICE_NAME  = "Kart Live Timing._karttiming._tcp.local."
SERVICE_PORT  = 8000

API_TOKEN = "miotokentest12345"

# API_TOKEN = os.environ.get("KART_API_TOKEN")
# if not API_TOKEN:
#    print("⚠️  ATTENZIONE: KART_API_TOKEN non impostato, autenticazione WS disabilitata")

POLL_INTERVAL  = 3          # secondi tra un poll e l'altro
REFRESH_EVERY  = 10         # refresh pagina ogni N poll
SESSION_IDLE_GRACE = 15     # secondi di grazia prima di fermare una sessione senza iscritti

# Cartella data/ interna al progetto
DATA_DIR  = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)

DEFAULT_URL = "https://live.racefacer.com/ottobianomotorsport"
SIMULATOR_URL = "https://live.racefacer.com/simulator"
SIMULATOR_JSON_PATH = Path(__file__).parent.parent / "racefacer_sim" / "sim_data" / "live_timing.json"

# Domini che i client possono richiedere via "set_url". Chiunque abbia il
# token può scegliere la propria sorgente, ma solo tra questi host: evita
# che un client possa far scrapare al server URL arbitrari (SSRF verso la
# rete interna, siti a caso, ecc.).
ALLOWED_URL_HOSTS = {
    "live.racefacer.com",
    # "timing.altrapiattaforma.com",
}

# Numero massimo di sessioni di scraping distinte attive in contemporanea
# (una per URL distinto in uso). Protegge da un client che tenta di far
# aprire tanti browser headless diversi per esaurire CPU/RAM del server.
MAX_CONCURRENT_SESSIONS = 5


def is_url_allowed(url: str) -> bool:
    try:
        parsed = urlparse(url)
    except Exception:
        return False
    if parsed.scheme not in ("http", "https"):
        return False
    return parsed.hostname in ALLOWED_URL_HOSTS


def json_path_for(url: str) -> Path:
    """Ogni URL ha il proprio file di persistenza, per non sovrascrivere dati di sessioni diverse."""
    h = hashlib.md5(url.encode()).hexdigest()[:10]
    return DATA_DIR / f"live_timing_{h}.json"


def clear_saved_timing_data():
    """Cancella tutti i file di live timing salvati. Chiamata allo shutdown del
    server, così i dati temporanei non si accumulano da un avvio all'altro."""
    removed = 0
    for f in DATA_DIR.glob("live_timing_*.json"):
        try:
            f.unlink()
            removed += 1
        except Exception as e:
            print(f"⚠️ Impossibile rimuovere {f.name}: {e}")
    if removed:
        print(f"🧹 Rimossi {removed} file di live timing salvati.")


# ---------------------------------------------------------------------------
# JS estrattore tabella (identico allo script originale)
# ---------------------------------------------------------------------------

JS_EXTRACT = """
() => {
    const tables = document.querySelectorAll('table');
    let bestTable = null;
    let maxRows = 0;
    tables.forEach(t => {
        const rows = t.querySelectorAll('tr');
        if (rows.length > maxRows) { maxRows = rows.length; bestTable = t; }
    });
    if (!bestTable) return { headers: [], rows: [] };

    const allRows = Array.from(bestTable.querySelectorAll('tr'));
    const headers = Array.from(allRows[0]?.querySelectorAll('th, td') || [])
                        .map(c => c.innerText.trim());

    const rows = allRows.slice(1).map(row => {
        return Array.from(row.querySelectorAll('td'))
                    .map(c => c.innerText.trim());
    }).filter(r => r.some(c => c !== ''));

    return { headers, rows };
}
"""

# ---------------------------------------------------------------------------
# Salvataggio JSON (scrittura atomica)
# ---------------------------------------------------------------------------


def data_hash(data: dict) -> str:
    return hashlib.md5(json.dumps(data, sort_keys=True).encode()).hexdigest()


def save_json(payload: dict, path: Path):
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".json", dir=DATA_DIR)
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, str(path))
    except Exception:
        os.unlink(tmp_path)
        raise


# ---------------------------------------------------------------------------
# Gestione client <-> sessione
# ---------------------------------------------------------------------------

# Ogni WebSocket connesso è mappato all'URL che sta attualmente guardando.
client_url: Dict[WebSocket, str] = {}


class ScraperSession:
    """
    Una sessione di scraping indipendente per un singolo URL.
    Più client possono essere iscritti alla stessa sessione (stesso URL):
    in quel caso condividono naturalmente lo stesso browser/thread, il che
    è corretto ed efficiente (non serve un browser per ogni client, solo
    per ogni URL distinto in uso).
    """

    def __init__(self, url: str, loop: asyncio.AbstractEventLoop):
        self.url = url
        self.loop = loop
        self.subscriber_count = 0
        self.last_payload: Optional[Dict] = None
        self.running = False
        self.thread: Optional[threading.Thread] = None
        self._stop_timer: Optional[asyncio.TimerHandle] = None

    # -- lifecycle -----------------------------------------------------

    def start(self):
        if self.running:
            return
        self.running = True
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()
        print(f"▶  Sessione avviata → {self.url}")

    def stop(self):
        if not self.running:
            return
        self.running = False
        print(f"⏸  Sessione fermata → {self.url}")

    # -- reference counting ---------------------------------------------

    def add_subscriber(self):
        self._cancel_pending_stop()
        self.subscriber_count += 1
        self.start()

    def remove_subscriber(self):
        self.subscriber_count = max(0, self.subscriber_count - 1)
        if self.subscriber_count == 0:
            self._schedule_stop()

    def _schedule_stop(self):
        self._cancel_pending_stop()
        self._stop_timer = self.loop.call_later(
            SESSION_IDLE_GRACE, self._idle_stop_check
        )

    def _cancel_pending_stop(self):
        if self._stop_timer:
            self._stop_timer.cancel()
            self._stop_timer = None

    def _idle_stop_check(self):
        if self.subscriber_count == 0:
            self.stop()
            sessions.pop(self.url, None)
            self._delete_saved_file()

    def _delete_saved_file(self):
        path = json_path_for(self.url)
        try:
            if path.exists():
                path.unlink()
                print(f"🧹 Rimosso file dati per sessione senza più iscritti → {self.url}")
        except Exception as e:
            print(f"⚠️ Impossibile rimuovere {path.name}: {e}")

    # -- scraping loop (thread separato) ---------------------------------

    def _loop(self):
        last_hash = None
        poll_count = 0
        path = json_path_for(self.url)

        if self.url == SIMULATOR_URL:
            print(f"🎮 Avvio simulatore locale da {SIMULATOR_JSON_PATH}")
            while self.running:
                try:
                    if SIMULATOR_JSON_PATH.exists():
                        with open(SIMULATOR_JSON_PATH, "r", encoding="utf-8") as f:
                            payload = json.load(f)

                        h = data_hash(payload)
                        if h != last_hash:
                            last_hash = h
                            self.last_payload = payload
                            save_json(payload, path)
                            print(f"📊 [{self.url}] Dati simulatore aggiornati: {len(payload.get('rows', []))} righe")
                            asyncio.run_coroutine_threadsafe(
                                broadcast_to_url(self.url, payload), self.loop
                            )
                    else:
                        print(f"⚠️ File simulatore non trovato a {SIMULATOR_JSON_PATH}")
                except Exception as e:
                    print(f"⚠️ Errore lettura simulatore: {e}")
                time.sleep(POLL_INTERVAL)
            print(f"🔴 Loop simulatore fermato → {self.url}")
            return

        try:
            with sync_playwright() as pw:
                browser = pw.chromium.launch(headless=True)
                page = browser.new_page()

                print(f"🌐 Caricamento pagina: {self.url}")
                page.goto(self.url, wait_until="networkidle", timeout=30_000)
                print(f"✅ Pagina caricata ({self.url}). Inizio polling.")

                while self.running:
                    try:
                        if poll_count > 0 and poll_count % REFRESH_EVERY == 0:
                            print(f"🔄 Refresh pagina... ({self.url})")
                            page.goto(self.url, wait_until="networkidle", timeout=30_000)

                        poll_count += 1
                        result = page.evaluate(JS_EXTRACT)
                        headers = result.get("headers", [])
                        rows = result.get("rows", [])

                        payload = {
                            "type": "timing_update",
                            "url": self.url,
                            "updated_at": datetime.now().isoformat(),
                            "headers": headers,
                            "rows": rows,
                        }

                        h = data_hash(payload)
                        if h != last_hash:
                            last_hash = h
                            self.last_payload = payload
                            save_json(payload, path)
                            print(f"📊 [{self.url}] Dati aggiornati: {len(rows)} righe")
                            asyncio.run_coroutine_threadsafe(
                                broadcast_to_url(self.url, payload), self.loop
                            )

                        time.sleep(POLL_INTERVAL)

                    except Exception as e:
                        print(f"⚠️  Errore polling ({self.url}): {e}")
                        time.sleep(POLL_INTERVAL)

                browser.close()

        except Exception as e:
            print(f"❌ Errore browser ({self.url}): {e}")
        finally:
            self.running = False
            print(f"🔴 Scraper fermato → {self.url}")


sessions: Dict[str, ScraperSession] = {}


def get_or_create_session(url: str, loop: asyncio.AbstractEventLoop) -> ScraperSession:
    session = sessions.get(url)
    if session is None:
        session = ScraperSession(url, loop)
        sessions[url] = session
    return session


async def broadcast_to_url(url: str, message: dict):
    """Invia il messaggio solo ai client attualmente iscritti a quell'URL."""
    data = json.dumps(message, ensure_ascii=False)
    for ws, watched_url in list(client_url.items()):
        if watched_url != url:
            continue
        try:
            await ws.send_text(data)
        except Exception:
            client_url.pop(ws, None)


def subscribe_client(ws: WebSocket, url: str, loop: asyncio.AbstractEventLoop) -> ScraperSession:
    """Iscrive (o re-iscrive) un client a un URL, deiscrivendolo dal precedente."""
    old_url = client_url.get(ws)
    if old_url is not None and old_url != url:
        old_session = sessions.get(old_url)
        if old_session:
            old_session.remove_subscriber()

    client_url[ws] = url
    session = get_or_create_session(url, loop)
    if old_url != url:
        session.add_subscriber()
    return session


def unsubscribe_client(ws: WebSocket):
    url = client_url.pop(ws, None)
    if url is None:
        return
    session = sessions.get(url)
    if session:
        session.remove_subscriber()


# ---------------------------------------------------------------------------
# Bonjour
# ---------------------------------------------------------------------------

zeroconf_instance: Optional[Zeroconf] = None


def get_local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    finally:
        s.close()


async def start_bonjour():
    global zeroconf_instance
    local_ip = get_local_ip()
    print(f"📡 IP locale: {local_ip}")

    info = ServiceInfo(
        type_=SERVICE_TYPE,
        name=SERVICE_NAME,
        addresses=[socket.inet_aton(local_ip)],
        port=SERVICE_PORT,
        properties={"version": "1.0"},
        server=f"{socket.gethostname()}.local.",
    )

    zeroconf_instance = Zeroconf()
    await zeroconf_instance.async_register_service(info)
    print(f"✅ Bonjour attivo: '{SERVICE_NAME}' su {local_ip}:{SERVICE_PORT}")


async def stop_bonjour():
    if zeroconf_instance:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, zeroconf_instance.close)
        print("🔴 Bonjour fermato")


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup e shutdown dell'applicazione."""
    clear_saved_timing_data()  # pulizia anche di eventuali residui da uno stop non pulito
    await start_bonjour()
    # Nota: non avviamo più uno scraper globale all'avvio. Ogni sessione
    # parte on-demand quando il primo client la richiede (vedi
    # websocket_endpoint, che iscrive ogni nuovo client a DEFAULT_URL).
    yield
    for session in list(sessions.values()):
        session.stop()
    await stop_bonjour()
    clear_saved_timing_data()


# ---------------------------------------------------------------------------
# FastAPI
# ---------------------------------------------------------------------------

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# WebSocket endpoint
# ---------------------------------------------------------------------------


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    if API_TOKEN:
        token = websocket.query_params.get("token")
        if token != API_TOKEN:
            await websocket.close(code=4401)
            return

    await websocket.accept()
    loop = asyncio.get_event_loop()

    # Ogni client parte iscritto alla sorgente di default, indipendentemente
    # dagli altri client già connessi.
    session = subscribe_client(websocket, DEFAULT_URL, loop)
    print(f"📱 Client connesso su '{DEFAULT_URL}'. Totale client: {len(client_url)}")

    if session.last_payload:
        try:
            await websocket.send_text(json.dumps(session.last_payload, ensure_ascii=False))
        except Exception:
            pass

    try:
        while True:
            raw = await websocket.receive_text()
            msg = json.loads(raw)
            command = msg.get("command")

            if command == "set_url":
                new_url = msg.get("url", "").strip()

                if not new_url.startswith("http"):
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": "URL non valido"
                    }))

                elif not is_url_allowed(new_url):
                    print(f"🚫 URL rifiutato (host non consentito): {new_url}")
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": "Dominio non consentito"
                    }))

                elif new_url not in sessions and len(sessions) >= MAX_CONCURRENT_SESSIONS:
                    print(f"🚫 Limite sessioni raggiunto, rifiuto: {new_url}")
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": "Troppe sessioni attive, riprova più tardi"
                    }))

                else:
                    print(f"🔗 Client richiede cambio URL → {new_url}")
                    new_session = subscribe_client(websocket, new_url, loop)
                    await websocket.send_text(json.dumps({
                        "type": "url_changed",
                        "url": new_url
                    }))
                    # Se abbiamo già dati per questa sessione (magari
                    # condivisa con un altro client), inviali subito.
                    if new_session.last_payload:
                        await websocket.send_text(
                            json.dumps(new_session.last_payload, ensure_ascii=False)
                        )

            elif command == "get_status":
                current = client_url.get(websocket, DEFAULT_URL)
                current_session = sessions.get(current)
                await websocket.send_text(json.dumps({
                    "type": "status",
                    "scraping": bool(current_session and current_session.running),
                    "url": current,
                }))

            else:
                print(f"Comando sconosciuto: {command}")

    except WebSocketDisconnect:
        unsubscribe_client(websocket)
        print(f"📴 Client disconnesso. Totale client: {len(client_url)}")