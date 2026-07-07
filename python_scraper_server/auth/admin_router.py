"""
Endpoint amministrativi (riservati al ruolo admin).

GET   /admin/users              → lista tutti gli utenti
PATCH /admin/users/{id}/role    → modifica il ruolo di un utente

Regola speciale: l'utente con username "admin" è il superutente di sistema
e il suo ruolo non può essere modificato tramite API, nemmeno da altri admin.
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
        q_lower = q.strip().lower()
        pattern = f"%{q_lower}%"
        
        # Mappa i termini italiani ai ruoli nel database (supportando la ricerca parziale)
        role_filters = []
        if "spettatore".startswith(q_lower):
            role_filters.append("viewer")
        if "direttore".startswith(q_lower) or "gara".startswith(q_lower) or "direttore di gara".startswith(q_lower):
            role_filters.append("race_director")
        if "admin".startswith(q_lower):
            role_filters.append("admin")
            
        role_condition = User.role.in_(role_filters) if role_filters else False

        users = (
            db.query(User)
            .filter(
                User.username.ilike(pattern) | 
                User.email.ilike(pattern) |
                User.role.ilike(pattern) |
                role_condition
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
    """Modifica il ruolo di un utente. Solo gli admin possono farlo.
    
    Eccezione: l'utente con username 'admin' è il superutente di sistema
    e il suo ruolo non può essere modificato tramite questa API.
    """
    valid_roles = [r.value for r in Role]
    if body.role not in valid_roles:
        raise HTTPException(400, f"Ruolo non valido: '{body.role}'. Valori accettati: {valid_roles}")

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "Utente non trovato")

    # Superutente protetto: il ruolo di 'admin' non è modificabile via API
    if user.username == "admin":
        raise HTTPException(
            403,
            "Il ruolo del superutente 'admin' non può essere modificato."
        )

    old_role   = user.role
    user.role  = body.role
    db.commit()

    print(f"🛡️  Ruolo aggiornato: {user.username} {old_role} → {body.role}")
    return {"message": f"Ruolo aggiornato a '{body.role}' per {user.username}"}
