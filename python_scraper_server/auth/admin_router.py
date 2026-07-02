"""
Endpoint amministrativi (riservati al ruolo admin).

GET   /admin/users              → lista tutti gli utenti
PATCH /admin/users/{id}/role    → modifica il ruolo di un utente
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from auth.dependencies import require_role
from auth.roles import Role
from auth.schemas import UserResponse
from db.database import get_db
from db.models import User

router = APIRouter(prefix="/admin", tags=["admin"])


class RoleUpdate(BaseModel):
    role: str


@router.get("/users")
def list_users(
    db: Session = Depends(get_db),
    _caller = Depends(require_role(Role.ADMIN)),
):
    """Restituisce la lista di tutti gli utenti registrati."""
    users = db.query(User).order_by(User.created_at).all()
    return [
        UserResponse(
            id         = u.id,
            username   = u.username,
            email      = u.email,
            role       = u.role,
            created_at = u.created_at.isoformat(),
        )
        for u in users
    ]


@router.get("/users/search")
def search_users(
    q: str = "",
    db: Session = Depends(get_db),
    _caller = Depends(require_role(Role.ADMIN)),
):
    """Cerca utenti per username o email (ricerca parziale, case-insensitive).
    
    Se q è vuoto restituisce tutti gli utenti (stesso comportamento di /admin/users).
    """
    if q.strip():
        pattern = f"%{q.strip()}%"
        users = (
            db.query(User)
            .filter(
                User.username.ilike(pattern) | User.email.ilike(pattern)
            )
            .order_by(User.username)
            .all()
        )
    else:
        users = db.query(User).order_by(User.created_at).all()

    return [
        UserResponse(
            id         = u.id,
            username   = u.username,
            email      = u.email,
            role       = u.role,
            created_at = u.created_at.isoformat(),
        )
        for u in users
    ]



@router.patch("/users/{user_id}/role")
def update_role(
    user_id: int,
    body: RoleUpdate,
    db: Session = Depends(get_db),
    _caller = Depends(require_role(Role.ADMIN)),
):
    """Modifica il ruolo di un utente. Solo gli admin possono farlo."""
    valid_roles = [r.value for r in Role]
    if body.role not in valid_roles:
        raise HTTPException(400, f"Ruolo non valido: '{body.role}'. Valori accettati: {valid_roles}")

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "Utente non trovato")

    old_role   = user.role
    user.role  = body.role
    db.commit()

    print(f"🛡️  Ruolo aggiornato: {user.username} {old_role} → {body.role}")
    return {"message": f"Ruolo aggiornato a '{body.role}' per {user.username}"}
