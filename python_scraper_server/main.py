"""
Kart Live Timing Server — Entrypoint
Scraping: Playwright (headless) | API: FastAPI WebSocket

MULTI-CLIENT
----------------------
Ogni URL richiesto ha una propria ScraperSession (proprio thread Playwright, proprio ultimo payload),
ogni WebSocket connesso è associato alla sessione che sta guardando. I comandi
"set_url" e "get_status" agiscono solo sul client che li invia; i broadcast
vanno solo ai client iscritti a quell'URL. Le sessioni senza più iscritti
vengono fermate dopo un breve periodo di grazia per liberare risorse
(ogni sessione tiene aperto un browser headless).

Accesso: esclusivamente tramite Tailscale Funnel (no rete locale).
Autenticazione: JWT — vedi auth/

Struttura del progetto:
  config.py              → costanti e validazione URL
  auth/roles.py          → enum ruoli (viewer, race_director, admin)
  auth/password.py       → hashing bcrypt
  auth/jwt.py            → creazione e verifica JWT
  auth/dependencies.py   → dependency FastAPI per proteggere endpoint
  auth/token.py          → verifica JWT per WebSocket
  auth/router.py         → endpoint /auth/*
  auth/admin_router.py   → endpoint /admin/* (solo admin)
  db/database.py         → connessione SQLite + init_db
  db/models.py           → modelli SQLAlchemy (users, refresh_tokens)
  scraper/storage.py     → persistenza JSON su disco
  scraper/session.py     → ScraperSession + registro globale sessioni
  ws/manager.py          → mappa client-URL, subscribe/unsubscribe, broadcast
  ws/router.py           → endpoint WebSocket e gestione comandi
  discovery/bonjour.py   → (non usato) codice mDNS conservato per riferimento
"""

from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from auth.admin_router import router as admin_router
from auth.router import router as auth_router
from db.database import init_db
from scraper.session import sessions
from scraper.storage import clear_saved_timing_data
from ws.router import router as ws_router


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup e shutdown dell'applicazione."""
    init_db()                   # crea le tabelle DB se non esistono
    clear_saved_timing_data()   # pulizia di eventuali residui da uno stop non pulito
    yield
    for session in list(sessions.values()):
        session.stop()
    clear_saved_timing_data()


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(admin_router)
app.include_router(ws_router)


# ---------------------------------------------------------------------------
# Avvio diretto
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, log_level="info")