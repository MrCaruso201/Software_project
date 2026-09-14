"""
Autenticazione dei client WebSocket tramite JWT.

verify_websocket_token() legge il token dalla query string (?token=...),
lo verifica con la chiave segreta e restituisce il payload JWT (che contiene
user_id e role) oppure None se il token è mancante/invalido/scaduto.

Il payload restituito viene poi usato in ws/router.py per:
  1. Identificare l'utente connesso
  2. Verificare il ruolo prima di eseguire comandi privilegiati (es. set_url)
"""

from typing import Optional

from fastapi import WebSocket
from jose import JWTError

from auth.dependencies import resolve_current_user
from db.database import SessionLocal


async def verify_websocket_token(websocket: WebSocket) -> Optional[dict]:
    """
    Verifica il JWT nella query string del WebSocket.

    Returns:
        Il payload JWT (dict con 'sub', 'role', 'exp', ...) se valido.
        None se il token è assente, invalido o scaduto (dopo aver chiuso la connessione).

    Controlla anche l'esistenza dell'account e legge il ruolo attuale dal DB.
    """
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4401)
        return None

    try:
        with SessionLocal() as db:
            return resolve_current_user(token, db)
    except JWTError:
        await websocket.close(code=4401)
        return None
