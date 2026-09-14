"""
Gestione delle connessioni WebSocket attive.

Responsabilità:
  - Tracciamento della mappa client -> URL osservato
  - Subscribe / unsubscribe dei client alle sessioni di scraping
  - Broadcast dei messaggi ai client iscritti a un dato URL
"""

import asyncio
import json
from typing import Dict

from fastapi import WebSocket

from scraper.session import ScraperSession, get_or_create_session, sessions


# Mappa: WebSocket attivo -> URL che sta osservando
client_url: Dict[WebSocket, str] = {}

# Mappa: WebSocket attivo -> ID Evento che sta osservando
client_event: Dict[WebSocket, int] = {}


# ---------------------------------------------------------------------------
# Broadcast
# ---------------------------------------------------------------------------


async def broadcast_to_url(url: str, message: dict) -> None:
    """Invia il messaggio solo ai client attualmente iscritti a quell'URL."""
    data = json.dumps(message, ensure_ascii=False)
    for ws, watched_url in list(client_url.items()):
        if watched_url != url:
            continue
        try:
            await ws.send_text(data)
        except Exception:
            unsubscribe_client(ws)

async def broadcast_to_event(event_id: int, message: dict) -> None:
    """Invia il messaggio solo ai client iscritti a questo evento."""
    data = json.dumps(message, ensure_ascii=False)
    for ws, watched_event in list(client_event.items()):
        if watched_event != event_id:
            continue
        try:
            await ws.send_text(data)
        except Exception:
            unsubscribe_client(ws)


# ---------------------------------------------------------------------------
# Subscribe / Unsubscribe
# ---------------------------------------------------------------------------


def subscribe_client(
    ws: WebSocket, url: str, loop: asyncio.AbstractEventLoop
) -> ScraperSession:
    """
    Iscrive (o re-iscrive) un client a un URL, de-iscrivendolo dal precedente.

    Restituisce la ScraperSession associata al nuovo URL.
    """
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


def unsubscribe_client(ws: WebSocket) -> None:
    """Rimuove il client dalla mappa e decrementa il contatore della sessione."""
    client_event.pop(ws, None)
    url = client_url.pop(ws, None)
    if url is None:
        return
    session = sessions.get(url)
    if session:
        session.remove_subscriber()

def subscribe_client_to_event(ws: WebSocket, event_id: int) -> None:
    """Associa un client a un determinato evento."""
    client_event[ws] = event_id
