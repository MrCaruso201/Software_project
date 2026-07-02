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

from auth.jwt import verify_access_token


async def verify_websocket_token(websocket: WebSocket) -> Optional[dict]:
    """
    Verifica il JWT nella query string del WebSocket.

    Returns:
        Il payload JWT (dict con 'sub', 'role', 'exp', ...) se valido.
        None se il token è assente, invalido o scaduto (dopo aver chiuso la connessione).

    Punto di estensione: qui si possono aggiungere controlli aggiuntivi
    (es. verifica che l'utente esista ancora nel DB, che non sia bannato, ecc.)
    """
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4401)
        return None

    try:
        payload = verify_access_token(token)
        return payload
    except JWTError:
        await websocket.close(code=4401)
        return None
