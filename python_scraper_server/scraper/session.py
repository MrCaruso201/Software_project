"""
Gestione delle sessioni di scraping.

Una ScraperSession rappresenta un singolo URL in scraping:
  - Tiene aperto un browser Playwright in un thread dedicato
  - Notifica via broadcast tutti i client iscritti a quell'URL quando i dati cambiano
  - Si ferma automaticamente dopo SESSION_IDLE_GRACE secondi senza iscritti

Il dizionario globale `sessions` mappa URL -> ScraperSession ed è l'unica fonte
di verità sulle sessioni attive.
"""

import asyncio
import json
import threading
import time
from datetime import datetime
from typing import Dict, Optional

from playwright.sync_api import sync_playwright

from config import (
    POLL_INTERVAL,
    REFRESH_EVERY,
    SESSION_IDLE_GRACE,
    SIMULATOR_JSON_PATH,
    SIMULATOR_URL,
)
from scraper.storage import data_hash, json_path_for, save_json

# ---------------------------------------------------------------------------
# JavaScript estrattore tabella
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
# ScraperSession
# ---------------------------------------------------------------------------


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

    # -- lifecycle ---------------------------------------------------------

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

    # -- reference counting ------------------------------------------------

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

    # -- scraping loop (thread separato) -----------------------------------

    def _loop(self):
        # Importazione locale per evitare dipendenza circolare
        # (broadcast_to_url è definito in ws.manager che importa session)
        from ws.manager import broadcast_to_url

        last_hash = None
        poll_count = 0
        path = json_path_for(self.url)

        # --- Modalità simulatore locale ---
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
                            print(
                                f"📊 [{self.url}] Dati simulatore aggiornati: "
                                f"{len(payload.get('rows', []))} righe"
                            )
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

        # --- Modalità scraping Playwright ---
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


# ---------------------------------------------------------------------------
# Registro globale delle sessioni
# ---------------------------------------------------------------------------

sessions: Dict[str, ScraperSession] = {}


def get_or_create_session(
    url: str, loop: asyncio.AbstractEventLoop
) -> ScraperSession:
    """Restituisce la sessione esistente per l'URL o ne crea una nuova."""
    session = sessions.get(url)
    if session is None:
        session = ScraperSession(url, loop)
        sessions[url] = session
    return session
