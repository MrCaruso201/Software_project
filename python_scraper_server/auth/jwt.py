"""
Creazione e verifica dei JWT (access token e refresh token).

Il JWT_SECRET è caricato da .env tramite python-dotenv ed è obbligatorio:
se non è definito il server non si avvia (ValueError al boot).
NON inserire mai la chiave segreta direttamente nel codice.

Access token:  scade in 30 minuti, contiene user_id e role.
Refresh token: token casuale (non JWT), hashato con SHA-256 prima di essere
               salvato nel DB. Il client riceve il token raw; il server
               confronta sempre l'hash.
"""

import hashlib
import os
import secrets
from datetime import datetime, timedelta, timezone

from dotenv import load_dotenv
from jose import jwt, JWTError  # noqa: F401  (JWTError re-esportato per i consumer)

load_dotenv()

SECRET_KEY: str = os.environ.get("JWT_SECRET", "")
if not SECRET_KEY:
    raise ValueError(
        "JWT_SECRET non impostata. "
        "Definiscila nel file .env prima di avviare il server."
    )
ALGORITHM = "HS256"
ACCESS_EXPIRE_MINUTES = 30
REFRESH_EXPIRE_DAYS   = 30


# ---------------------------------------------------------------------------
# Access token
# ---------------------------------------------------------------------------


def create_access_token(user_id: int, role: str) -> str:
    """Genera un JWT access token firmato con SECRET_KEY."""
    payload = {
        "sub":  str(user_id),
        "role": role,
        "exp":  datetime.now(timezone.utc) + timedelta(minutes=ACCESS_EXPIRE_MINUTES),
        "type": "access",
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def verify_access_token(token: str) -> dict:
    """
    Decodifica e verifica un access token.
    Lancia jose.JWTError se il token è invalido, scaduto o malformato.
    """
    return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])


# ---------------------------------------------------------------------------
# Refresh token
# ---------------------------------------------------------------------------


def create_refresh_token_raw() -> str:
    """Genera un refresh token casuale sicuro (URL-safe, 32 byte)."""
    return secrets.token_urlsafe(32)


def hash_refresh_token(raw: str) -> str:
    """SHA-256 del token raw — è questo che viene salvato nel DB."""
    return hashlib.sha256(raw.encode()).hexdigest()


def refresh_token_expires_at() -> datetime:
    """Restituisce la data di scadenza (UTC naive) del refresh token."""
    return datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(days=REFRESH_EXPIRE_DAYS)
