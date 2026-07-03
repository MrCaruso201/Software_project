"""
Endpoint REST di autenticazione.

POST /auth/register  → crea account (ruolo user)
POST /auth/login     → login, restituisce access + refresh token
POST /auth/refresh   → emette nuovo access token da refresh token valido
POST /auth/logout    → revoca il refresh token
GET  /auth/me        → info utente corrente (richiede access token valido)
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
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
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
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
    user = db.query(User).filter(User.username == req.username).first()
    if not user or not verify_password(req.password, user.hashed_pw):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Credenziali non valide")

    access_token = create_access_token(user.id, user.role)
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

    new_access = create_access_token(user.id, user.role)
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
        email      = user.email,
        role       = user.role,
        created_at = user.created_at.isoformat(),
    )
