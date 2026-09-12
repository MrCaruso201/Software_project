"""
Gestione delle sessioni di scraping.

Una ScraperSession rappresenta un singolo URL in scraping:
  - Ottiene il provider corretto dalla factory (scraper/factory.py)
  - Esegue il loop di polling in un thread dedicato
  - Notifica via broadcast tutti i client iscritti a quell'URL quando i dati cambiano
  - Si ferma automaticamente dopo SESSION_IDLE_GRACE secondi senza iscritti

Il dizionario globale `sessions` mappa URL -> ScraperSession ed è l'unica fonte
di verità sulle sessioni attive.

Per aggiungere supporto a un nuovo provider non è necessario toccare questo file:
basta aggiungere la classe in scraper/providers/ e registrarla in scraper/factory.py.
"""

import asyncio
import threading
import time
from datetime import datetime
from typing import Dict, Optional

from config import POLL_INTERVAL, SESSION_IDLE_GRACE
from scraper.storage import data_hash, json_path_for, save_json


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
        self.last_lap_counts: Dict[int, int] = {}
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
        # Import locali per evitare dipendenze circolari:
        #   - broadcast_to_url è in ws.manager che importa session
        #   - get_scraper_for_url importa i provider che non dipendono da session
        from ws.manager import broadcast_to_url
        from scraper.factory import get_scraper_for_url

        path = json_path_for(self.url)
        last_hash = None

        scraper = get_scraper_for_url(self.url)
        print(f"🔌 Provider selezionato: {type(scraper).__name__} → {self.url}")

        scraper.setup(self.url)
        try:
            while self.running:
                try:
                    data = scraper.scrape()
                    payload = {
                        "type": "timing_update",
                        "url": self.url,
                        "updated_at": datetime.now().isoformat(),
                        "headers": data.get("headers", []),
                        "rows": data.get("rows", []),
                    }

                    h = data_hash(payload)
                    if h != last_hash:
                        last_hash = h
                        self.last_payload = payload
                        save_json(payload, path)
                        
                        from scraper.lap_tracker import process_payload_for_laps
                        self.last_lap_counts = process_payload_for_laps(self.url, payload, self.last_lap_counts)
                        
                        print(
                            f"📊 [{self.url}] Dati aggiornati: "
                            f"{len(payload['rows'])} righe"
                        )
                        asyncio.run_coroutine_threadsafe(
                            broadcast_to_url(self.url, payload), self.loop
                        )

                except Exception as e:
                    print(f"⚠️  Errore polling ({self.url}): {e}")

                time.sleep(POLL_INTERVAL)

        finally:
            scraper.teardown()
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
