"""
Endpoint amministrativi (riservati al ruolo admin).

GET   /admin/users              → lista tutti gli utenti
PATCH /admin/users/{id}/role    → modifica il ruolo di un utente

Regola speciale: l'utente con username "admin" è il superutente di sistema
e il suo ruolo non può essere modificato tramite API, nemmeno da altri admin.
"""

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional

from auth.dependencies import require_role
from auth.roles import Role
from auth.schemas import UserResponse
from db.database import get_db
from db.models import User, Event, SignedRelease
from notifications.router import notify_user
from services.pdf_generator import generate_release_pdf

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
            profile_picture_url = u.profile_picture_url,
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
            profile_picture_url = u.profile_picture_url,
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


class ReleaseFormUpdate(BaseModel):
    release_form_text: str | None


@router.put("/events/{event_id}/release-form")
def update_release_form(
    event_id: int,
    body: ReleaseFormUpdate,
    db: Session = Depends(get_db),
    _caller = Depends(require_role(Role.ADMIN)),
):
    """Aggiorna il testo della liberatoria per un evento."""
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(404, "Evento non trovato")
    event.release_form_text = body.release_form_text
    db.commit()
    return {"message": "Testo liberatoria aggiornato"}


@router.get("/events/{event_id}/releases")
def list_signed_releases(
    event_id: int,
    db: Session = Depends(get_db),
    _caller = Depends(require_role(Role.ADMIN)),
):
    """Restituisce la lista di chi ha firmato la liberatoria per l'evento."""
    releases = db.query(SignedRelease, User).join(User, SignedRelease.user_id == User.id).filter(SignedRelease.event_id == event_id).all()
    results = []
    for r, u in releases:
        results.append({
            "id": r.id,
            "user_id": r.user_id,
            "username": u.username,
            "first_name": r.first_name or "",
            "last_name": r.last_name or "",
            "signed_at": r.signed_at.isoformat()
        })
    return results


@router.get("/events/{event_id}/releases/{user_id}/pdf")
def download_release_pdf(
    event_id: int,
    user_id: int,
    token: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """Genera e scarica il PDF della liberatoria per un utente specifico."""
    if not token:
        raise HTTPException(401, "Token mancante")
    try:
        from auth.jwt import verify_access_token
        from auth.roles import has_permission, Role
        user_payload = verify_access_token(token)
    except Exception:
        raise HTTPException(401, "Token non valido")
        
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(403, "Permessi insufficienti")

    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(404, "Evento non trovato")
        
    release = db.query(SignedRelease).filter(
        SignedRelease.event_id == event_id,
        SignedRelease.user_id == user_id
    ).first()
    
    if not release:
        raise HTTPException(404, "Liberatoria non trovata per questo utente e evento")
        
    user = db.query(User).filter(User.id == user_id).first()
    
    first_name = release.first_name if release.first_name else (user.first_name if user and user.first_name else "Sconosciuto")
    last_name = release.last_name if release.last_name else (user.last_name if user and user.last_name else "")
    
    pdf_bytes = generate_release_pdf(
        event_title=event.title,
        event_date=event.event_date.strftime("%d/%m/%Y %H:%M") if event.event_date else "",
        event_location=event.location or "",
        release_text=event.release_form_text,
        first_name=first_name,
        last_name=last_name,
        codice_fiscale=release.codice_fiscale or "",
        birth_date=release.birth_date or "",
        residence=release.residence or "",
        signature_base64=release.signature_base64
    )
    
    filename = f"liberatoria_{event_id}_{user_id}.pdf"
    
    return Response(
        content=bytes(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )

@router.delete("/events/{event_id}/releases/{user_id}")
def delete_signed_release(
    event_id: int,
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role(Role.RACE_DIRECTOR))
):
    """L'admin rifiuta (elimina) una liberatoria firmata da un utente."""
    release = db.query(SignedRelease).filter(
        SignedRelease.event_id == event_id,
        SignedRelease.user_id == user_id
    ).first()
    
    if not release:
        raise HTTPException(404, "Liberatoria non trovata")
        
    db.delete(release)
    db.commit()
    
    # Notifica l'utente del rifiuto
    notify_user(
        db,
        user_id,
        event_id,
        "release_rejected",
        "Liberatoria Rifiutata",
        "L'admin ha cancellato la compilazione della liberatoria. Per favore, compilala nuovamente."
    )
    
    return {"message": "Liberatoria eliminata con successo"}
