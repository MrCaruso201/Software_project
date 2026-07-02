"""
Dependency FastAPI per autenticazione e autorizzazione.

get_current_user  → verifica il JWT nell'header Authorization
require_role()    → factory che protegge un endpoint con un ruolo minimo

Uso:
    @router.get("/admin/users")
    def list_users(user = Depends(require_role(Role.ADMIN))):
        ...
"""

from fastapi import Depends, Header, HTTPException, status
from jose import JWTError

from auth.jwt import verify_access_token
from auth.roles import Role, has_permission


async def get_current_user(authorization: str = Header(...)) -> dict:
    """
    Estrae e verifica il JWT dall'header 'Authorization: Bearer <token>'.
    Lancia 401 se il token manca, è malformato o scaduto.
    """
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token mancante o formato non valido (atteso: Bearer <token>)",
        )
    token = authorization.removeprefix("Bearer ")
    try:
        return verify_access_token(token)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token non valido o scaduto",
        )


def require_role(required: Role):
    """
    Dependency factory: protegge un endpoint richiedendo un ruolo minimo.
    Restituisce il payload JWT se il ruolo è sufficiente, altrimenti 403.
    """
    async def _check(user: dict = Depends(get_current_user)) -> dict:
        if not has_permission(user.get("role", ""), required):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Permessi insufficienti",
            )
        return user
    return _check
