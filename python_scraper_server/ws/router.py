"""
Router WebSocket: gestisce la connessione e i comandi dei client.

Comandi supportati:
  - set_url  → cambia la sorgente dati osservata dal client
  - get_status → restituisce lo stato corrente della sessione del client
"""

import asyncio
import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from auth.token import verify_websocket_token
from config import DEFAULT_URL, MAX_CONCURRENT_SESSIONS
from config import is_url_allowed
from scraper.session import sessions
from ws.manager import client_url, subscribe_client, unsubscribe_client

router = APIRouter()


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    # Autenticazione: se fallisce, verify_websocket_token chiude già la connessione
    if not await verify_websocket_token(websocket):
        return

    await websocket.accept()
    loop = asyncio.get_event_loop()

    # Ogni client parte iscritto alla sorgente di default, indipendentemente
    # dagli altri client già connessi.
    session = subscribe_client(websocket, DEFAULT_URL, loop)
    print(f"📱 Client connesso su '{DEFAULT_URL}'. Totale client: {len(client_url)}")

    # Invia subito gli ultimi dati disponibili (se presenti)
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

            # ------------------------------------------------------------------
            # Comando: set_url
            # ------------------------------------------------------------------
            if command == "set_url":
                new_url = msg.get("url", "").strip()

                if not new_url.startswith("http"):
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": "URL non valido",
                    }))

                elif not is_url_allowed(new_url):
                    print(f"🚫 URL rifiutato (host non consentito): {new_url}")
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": "Dominio non consentito",
                    }))

                elif new_url not in sessions and len(sessions) >= MAX_CONCURRENT_SESSIONS:
                    print(f"🚫 Limite sessioni raggiunto, rifiuto: {new_url}")
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": "Troppe sessioni attive, riprova più tardi",
                    }))

                else:
                    print(f"🔗 Client richiede cambio URL → {new_url}")
                    new_session = subscribe_client(websocket, new_url, loop)
                    await websocket.send_text(json.dumps({
                        "type": "url_changed",
                        "url": new_url,
                    }))
                    # Se abbiamo già dati per questa sessione (magari condivisa
                    # con un altro client), inviali subito.
                    if new_session.last_payload:
                        await websocket.send_text(
                            json.dumps(new_session.last_payload, ensure_ascii=False)
                        )

            # ------------------------------------------------------------------
            # Comando: get_status
            # ------------------------------------------------------------------
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
