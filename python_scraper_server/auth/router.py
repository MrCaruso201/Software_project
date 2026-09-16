"""
Endpoint REST di autenticazione.

POST /auth/register         → crea account (ruolo user)
POST /auth/login            → login, restituisce access + refresh token
POST /auth/refresh          → emette nuovo access token da refresh token valido
POST /auth/logout           → revoca il refresh token
GET  /auth/me               → info utente corrente (richiede access token valido)
POST /auth/change-password  → cambia la password dell'utente corrente
"""

import os
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.orm import Session

from auth.dependencies import get_current_user
from auth.jwt import (
    create_access_token,
    create_refresh_token_raw,
    hash_refresh_token,
    refresh_token_expires_at,
)
from auth.password import hash_password, verify_password
from auth.schemas import (
    ChangePasswordRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
    UserUpdateRequest,
)
from db.database import get_db
from db.models import RefreshToken, User

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(req: RegisterRequest, db: Session = Depends(get_db)):
    """Crea un nuovo account con ruolo 'user'."""
    if not req.username.strip() or not req.email.strip() or not req.password:
        raise HTTPException(400, "Tutti i campi sono obbligatori")

    if db.query(User).filter(User.username == req.username).first():
        raise HTTPException(400, "Username già in uso")
    if db.query(User).filter(User.email == req.email).first():
        raise HTTPException(400, "Email già in uso")

    user = User(
        username=req.username.strip(),
        email=req.email.strip().lower(),
        hashed_pw=hash_password(req.password),
        role="user",
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    print(f"👤 Nuovo utente registrato: {user.username} (id={user.id})")
    return {"message": "Account creato con successo", "user_id": user.id}


@router.post("/login", response_model=TokenResponse)
def login(req: LoginRequest, db: Session = Depends(get_db)):
    """Login: verifica credenziali e restituisce access + refresh token."""
    user = db.query(User).filter(
        (User.username == req.username) | (User.email == req.username)
    ).first()
    if not user or not verify_password(req.password, user.hashed_pw):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Credenziali non valide")

    access_token = create_access_token(user.id, user.role, user.token_version)
    raw_refresh   = create_refresh_token_raw()

    rt = RefreshToken(
        user_id    = user.id,
        token_hash = hash_refresh_token(raw_refresh),
        expires_at = refresh_token_expires_at(),
    )
    db.add(rt)
    db.commit()

    print(f"🔑 Login: {user.username} (ruolo={user.role})")
    return TokenResponse(access_token=access_token, refresh_token=raw_refresh)


@router.post("/refresh")
def refresh(req: RefreshRequest, db: Session = Depends(get_db)):
    """Emette un nuovo access token se il refresh token è ancora valido."""
    hashed = hash_refresh_token(req.refresh_token)
    now    = datetime.now(timezone.utc).replace(tzinfo=None)

    rt = db.query(RefreshToken).filter(
        RefreshToken.token_hash == hashed,
        RefreshToken.revoked    == False,   # noqa: E712
        RefreshToken.expires_at >  now,
    ).first()

    if not rt:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Refresh token non valido o scaduto")

    user = db.query(User).filter(User.id == rt.user_id).first()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Utente non trovato")

    new_access = create_access_token(user.id, user.role, user.token_version)
    return {"access_token": new_access, "token_type": "bearer"}


@router.post("/logout")
def logout(req: RefreshRequest, db: Session = Depends(get_db)):
    """Revoca il refresh token (logout). Idempotente."""
    hashed = hash_refresh_token(req.refresh_token)
    rt = db.query(RefreshToken).filter(RefreshToken.token_hash == hashed).first()
    if rt:
        rt.revoked = True
        db.commit()
    return {"message": "Logout effettuato"}


@router.get("/me", response_model=UserResponse)
def me(user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    """Restituisce le informazioni dell'utente corrente."""
    user = db.query(User).filter(User.id == int(user_payload["sub"])).first()
    if not user:
        raise HTTPException(404, "Utente non trovato")
    return UserResponse(
        id         = user.id,
        username   = user.username,
        first_name = user.first_name,
        last_name  = user.last_name,
        profile_picture_url = user.profile_picture_url,
        email      = user.email,
        role       = user.role,
        created_at = user.created_at.isoformat(),
    )

@router.patch("/me", response_model=UserResponse)
def update_me(
    req: UserUpdateRequest,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Aggiorna le informazioni (nome/cognome) dell'utente corrente."""
    user = db.query(User).filter(User.id == int(user_payload["sub"])).first()
    if not user:
        raise HTTPException(404, "Utente non trovato")

    if req.first_name is not None:
        user.first_name = req.first_name
    if req.last_name is not None:
        user.last_name = req.last_name
        
    db.commit()
    db.refresh(user)
    
    return UserResponse(
        id         = user.id,
        username   = user.username,
        first_name = user.first_name,
        last_name  = user.last_name,
        profile_picture_url = user.profile_picture_url,
        email      = user.email,
        role       = user.role,
        created_at = user.created_at.isoformat(),
    )

@router.post("/me/avatar", response_model=UserResponse)
async def upload_avatar(
    file: UploadFile = File(...),
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Carica e aggiorna l'immagine del profilo dell'utente corrente."""
    user_id = int(user_payload["sub"])
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "Utente non trovato")
        
    if not file.content_type.startswith("image/"):
        raise HTTPException(400, "Il file deve essere un'immagine")

    # Salva il file
    ext = file.filename.split(".")[-1] if "." in file.filename else "jpg"
    filename = f"avatar_{user_id}.{ext}"
    
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    filepath = os.path.join(BASE_DIR, "data", "profile_pictures", filename)
    
    content = await file.read()
    with open(filepath, "wb") as f:
        f.write(content)
        
    # Aggiorna il db
    user.profile_picture_url = f"/static/profile_pictures/{filename}"
    db.commit()
    db.refresh(user)
    
    return UserResponse(
        id         = user.id,
        username   = user.username,
        first_name = user.first_name,
        last_name  = user.last_name,
        profile_picture_url = user.profile_picture_url,
        email      = user.email,
        role       = user.role,
        created_at = user.created_at.isoformat(),
    )


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Elimina l'account dell'utente autenticato."""
    user = db.query(User).filter(User.id == int(user_payload["sub"])).first()
    if not user:
        raise HTTPException(404, "Utente non trovato")
        
    db.delete(user)
    db.commit()
    return None


@router.post("/change-password", status_code=status.HTTP_200_OK)
def change_password(
    req: ChangePasswordRequest,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Cambia la password dell'utente autenticato.
    
    Richiede la vecchia password per conferma. La nuova password deve
    avere almeno 6 caratteri.
    """
    if len(req.new_password) < 3:
        raise HTTPException(400, "La nuova password deve essere di almeno 3 caratteri")

    user = db.query(User).filter(User.id == int(user_payload["sub"])).first()
    if not user:
        raise HTTPException(404, "Utente non trovato")

    if not verify_password(req.old_password, user.hashed_pw):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "La vecchia password non è corretta")

    user.hashed_pw = hash_password(req.new_password)
    db.commit()

    print(f"🔒 Password aggiornata per: {user.username}")
    return {"message": "Password aggiornata con successo"}
