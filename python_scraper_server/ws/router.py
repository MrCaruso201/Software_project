"""
Router WebSocket: gestisce la connessione e i comandi dei client.

Comandi supportati:
  - set_url    → cambia la sorgente dati (richiede ruolo >= viewer)
  - get_status → restituisce lo stato corrente della sessione del client
"""

import asyncio
import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from auth.roles import Role, has_permission
from auth.token import verify_websocket_token
from config import MAX_CONCURRENT_SESSIONS, is_url_allowed
from scraper.session import sessions
from ws.manager import client_url, subscribe_client, unsubscribe_client

router = APIRouter()


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    # Autenticazione JWT — restituisce il payload (user_id, role) o None
    user_payload = await verify_websocket_token(websocket)
    if user_payload is None:
        return

    await websocket.accept()
    loop = asyncio.get_event_loop()

    user_role = user_payload.get("role", Role.VIEWER)

    print(
        f"📱 Client connesso (ruolo={user_role}). "
        f"Nessun tracciato selezionato inizialmente. Totale client: {len(client_url) + 1}"
    )

    try:
        while True:
            # Rivalida anche connessioni inattive: account eliminati e token scaduti
            # non devono continuare a ricevere il live indefinitamente.
            try:
                raw = await asyncio.wait_for(websocket.receive_text(), timeout=5)
            except asyncio.TimeoutError:
                raw = None
            user_payload = await verify_websocket_token(websocket)
            if user_payload is None:
                return
            user_role = user_payload.get("role", Role.VIEWER)
            if raw is None:
                continue
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({"type": "error", "message": "JSON non valido"}))
                continue
            if not isinstance(msg, dict) or not isinstance(msg.get("command"), str):
                await websocket.send_text(json.dumps({"type": "error", "message": "Atteso un oggetto JSON con command di tipo stringa"}))
                continue
            command = msg["command"]

            # ------------------------------------------------------------------
            # Comando: set_url  (accessibile a tutti gli utenti autenticati)
            # ------------------------------------------------------------------
            if command == "set_url":
                if not has_permission(user_role, Role.VIEWER):
                    await websocket.send_text(json.dumps({
                        "type":    "error",
                        "message": "Permessi insufficienti per cambiare URL",
                    }))

                else:
                    if not isinstance(msg.get("url"), str):
                        await websocket.send_text(json.dumps({"type": "error", "message": "URL non valido: attesa una stringa"}))
                        continue
                    new_url = msg["url"].strip()

                    if not new_url.startswith("http"):
                        await websocket.send_text(json.dumps({
                            "type":    "error",
                            "message": "URL non valido",
                        }))

                    elif not is_url_allowed(new_url):
                        print(f"🚫 URL rifiutato (host non consentito): {new_url}")
                        await websocket.send_text(json.dumps({
                            "type":    "error",
                            "message": "Dominio non consentito",
                        }))

                    elif new_url not in sessions and len(sessions) >= MAX_CONCURRENT_SESSIONS:
                        print(f"🚫 Limite sessioni raggiunto, rifiuto: {new_url}")
                        await websocket.send_text(json.dumps({
                            "type":    "error",
                            "message": "Troppe sessioni attive, riprova più tardi",
                        }))

                    else:
                        print(f"🔗 Client richiede cambio URL → {new_url}")
                        new_session = subscribe_client(websocket, new_url, loop)
                        await websocket.send_text(json.dumps({
                            "type": "url_changed",
                            "url":  new_url,
                        }))
                        if new_session.last_payload:
                            await websocket.send_text(
                                json.dumps(new_session.last_payload, ensure_ascii=False)
                            )

            # ------------------------------------------------------------------
            # Comando: get_status
            # ------------------------------------------------------------------
            elif command == "get_status":
                current         = client_url.get(websocket)
                current_session = sessions.get(current) if current else None
                await websocket.send_text(json.dumps({
                    "type":     "status",
                    "scraping": bool(current_session and current_session.running),
                    "url":      current or "",
                    "role":     user_role,
                }))

            # ------------------------------------------------------------------
            # Comando: subscribe_event
            # ------------------------------------------------------------------
            elif command == "subscribe_event":
                event_id = msg.get("event_id")
                if type(event_id) is int and event_id > 0:
                    from ws.manager import subscribe_client_to_event
                    subscribe_client_to_event(websocket, event_id)
                    print(f"🔗 Client iscritto all'evento {event_id}")
                else:
                    await websocket.send_text(json.dumps({"type": "error", "message": "event_id deve essere un intero positivo"}))

            else:
                await websocket.send_text(json.dumps({"type": "error", "message": "Comando sconosciuto"}))

    except WebSocketDisconnect:
        pass
    finally:
        unsubscribe_client(websocket)
        print(f"📴 Client disconnesso. Totale client: {len(client_url)}")
