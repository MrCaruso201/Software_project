"""
Kart Live Timing Server
Scraping: Playwright (headless) | API: FastAPI WebSocket | Discovery: Bonjour/mDNS
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

# Cartella data/ interna al progetto
DATA_DIR  = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)
JSON_PATH = DATA_DIR / "live_timing.json"

DEFAULT_URL = "https://live.racefacer.com/ottobianomotorsport"
SIMULATOR_URL = "https://live.racefacer.com/simulator"
SIMULATOR_JSON_PATH = Path(__file__).parent.parent / "racefacer_sim" / "sim_data" / "live_timing.json"


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

# app is created after the lifespan function (see below)

# ---------------------------------------------------------------------------
# Stato globale (tipizzazione compatibile Python 3.9)
# ---------------------------------------------------------------------------

connected_clients: List[WebSocket] = []
current_url: str = DEFAULT_URL
scraper_thread: Optional[threading.Thread] = None
scraper_running: bool = False
last_payload: Optional[Dict] = None

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
        # close() è sincrono in questa versione di zeroconf
        await loop.run_in_executor(None, zeroconf_instance.close)
        print("🔴 Bonjour fermato")

# ---------------------------------------------------------------------------
# Salvataggio JSON (scrittura atomica)
# ---------------------------------------------------------------------------


def data_hash(data: dict) -> str:
    return hashlib.md5(json.dumps(data, sort_keys=True).encode()).hexdigest()


def save_json(payload: dict):
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".json", dir=DATA_DIR)
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, str(JSON_PATH))
    except Exception:
        os.unlink(tmp_path)
        raise

# ---------------------------------------------------------------------------
# Broadcast WebSocket
# ---------------------------------------------------------------------------


async def broadcast(message: dict):
    data = json.dumps(message, ensure_ascii=False)
    for ws in list(connected_clients):
        try:
            await ws.send_text(data)
        except Exception:
            connected_clients.remove(ws)

# ---------------------------------------------------------------------------
# Scraper (thread sincrono Playwright)
# ---------------------------------------------------------------------------


def scraper_loop(url: str, loop: asyncio.AbstractEventLoop):
    global scraper_running, last_payload
    last_hash = None
    poll_count = 0

    if url == SIMULATOR_URL:
        print(f"🎮 Avvio simulatore locale da {SIMULATOR_JSON_PATH}")
        while scraper_running:
            try:
                if SIMULATOR_JSON_PATH.exists():
                    with open(SIMULATOR_JSON_PATH, "r", encoding="utf-8") as f:
                        payload = json.load(f)
                    
                    h = data_hash(payload)
                    if h != last_hash:
                        last_hash = h
                        last_payload = payload
                        save_json(payload)
                        print(f"📊 Dati simulatore aggiornati: {len(payload.get('rows', []))} righe")
                        asyncio.run_coroutine_threadsafe(broadcast(payload), loop)
                else:
                    print(f"⚠️ File simulatore non trovato a {SIMULATOR_JSON_PATH}")
            except Exception as e:
                print(f"⚠️ Errore lettura simulatore: {e}")
            time.sleep(POLL_INTERVAL)
        print("🔴 Loop simulatore fermato.")
        return

    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(headless=True)
            page = browser.new_page()

            print(f"🌐 Caricamento pagina: {url}")
            page.goto(url, wait_until="networkidle", timeout=30_000)
            print("✅ Pagina caricata. Inizio polling.")

            while scraper_running:
                try:
                    if poll_count > 0 and poll_count % REFRESH_EVERY == 0:
                        print("🔄 Refresh pagina...")
                        page.goto(url, wait_until="networkidle", timeout=30_000)

                    poll_count += 1
                    result = page.evaluate(JS_EXTRACT)
                    headers = result.get("headers", [])
                    rows = result.get("rows", [])

                    payload = {
                        "type": "timing_update",
                        "url": url,
                        "updated_at": datetime.now().isoformat(),
                        "headers": headers,
                        "rows": rows,
                    }

                    h = data_hash(payload)
                    if h != last_hash:
                        last_hash = h
                        last_payload = payload
                        save_json(payload)
                        print(f"📊 Dati aggiornati: {len(rows)} righe")
                        asyncio.run_coroutine_threadsafe(broadcast(payload), loop)

                    time.sleep(POLL_INTERVAL)

                except Exception as e:
                    print(f"⚠️  Errore polling: {e}")
                    time.sleep(POLL_INTERVAL)

            browser.close()

    except Exception as e:
        print(f"❌ Errore browser: {e}")
    finally:
        scraper_running = False
        print("🔴 Scraper fermato.")


def start_scraper(url: str, loop: asyncio.AbstractEventLoop):
    global scraper_thread, scraper_running, current_url
    scraper_running = False
    if scraper_thread and scraper_thread.is_alive():
        scraper_thread.join(timeout=5)

    current_url = url
    scraper_running = True
    scraper_thread = threading.Thread(
        target=scraper_loop, args=(url, loop), daemon=True
    )
    scraper_thread.start()
    print(f"▶  Scraper avviato → {url}")


def stop_scraper():
    global scraper_running
    scraper_running = False
    print("⏸  Scraper fermato.")

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup e shutdown dell'applicazione."""
    loop = asyncio.get_event_loop()
    await start_bonjour()
    start_scraper(DEFAULT_URL, loop)
    yield
    stop_scraper()
    await stop_bonjour()


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
    connected_clients.append(websocket)
    print(f"📱 Client connesso. Totale: {len(connected_clients)}")

    if last_payload:
        try:
            await websocket.send_text(json.dumps(last_payload, ensure_ascii=False))
        except Exception:
            pass

    loop = asyncio.get_event_loop()

    try:
        while True:
            raw = await websocket.receive_text()
            msg = json.loads(raw)
            command = msg.get("command")

            if command == "set_url":
                new_url = msg.get("url", "").strip()
                if new_url.startswith("http"):
                    print(f"🔗 Cambio URL → {new_url}")
                    start_scraper(new_url, loop)
                    await websocket.send_text(json.dumps({
                        "type": "url_changed",
                        "url": new_url
                    }))
                else:
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": "URL non valido"
                    }))

            elif command == "get_status":
                await websocket.send_text(json.dumps({
                    "type": "status",
                    "scraping": scraper_running,
                    "url": current_url,
                }))

            else:
                print(f"Comando sconosciuto: {command}")

    except WebSocketDisconnect:
        connected_clients.remove(websocket)
        print(f"📴 Client disconnesso. Totale: {len(connected_clients)}")
