"""
Autenticazione dei client WebSocket.

Attualmente basata su un token statico (API_TOKEN in config.py).
In futuro questo modulo potrà essere esteso per supportare:
  - JWT (verifica firma, scadenza, refresh token)
  - Utenti su database (lookup per username/password)
  - Ruoli e permessi (admin, viewer, ecc.)
"""

from fastapi import WebSocket

from config import API_TOKEN


async def verify_websocket_token(websocket: WebSocket) -> bool:
    """
    Verifica che il client WebSocket presenti un token valido.

    Restituisce True se l'autenticazione ha successo, False altrimenti
    (dopo aver chiuso la connessione con codice 4401).

    Punto di estensione: sostituire il confronto statico con la verifica
    di un JWT o una query al DB utenti senza toccare il resto del codice.
    """
    if not API_TOKEN:
        # Nessuna autenticazione configurata: tutti i client sono accettati.
        return True

    token = websocket.query_params.get("token")
    if token != API_TOKEN:
        await websocket.close(code=4401)
        return False

    return True
