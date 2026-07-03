"""
Connessione al database SQLite tramite SQLAlchemy.

Espone:
  - engine      → connessione diretta al DB
  - SessionLocal → factory per le sessioni ORM
  - get_db()    → dependency FastAPI che apre/chiude la sessione per ogni request
  - init_db()   → crea le tabelle all'avvio del server (idempotente)
"""

from pathlib import Path
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

# Il DB è nella cartella data/ del progetto, accanto ai file JSON di timing
_DB_PATH = Path(__file__).parent.parent / "data" / "kart_timing.db"
DATABASE_URL = f"sqlite:///{_DB_PATH}"

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},  # necessario per SQLite con FastAPI
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    """Dependency FastAPI: apre una sessione DB e la chiude al termine della request."""
    db: Session = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """Crea tutte le tabelle definite in db/models.py (idempotente: non sovrascrive).
    
    Al primo avvio crea anche un utente admin di default (admin/admin) e un utente
    viewer di default (viewer/viewer) se non esistono.
    """
    from db.models import Base, User  # import locale per evitare importazione circolare
    Base.metadata.create_all(bind=engine)
    print("✅ Database inizializzato.")

    # --- Seed: utenti di default ---
    _seed_admin()
    _seed_viewer()


def _seed_admin() -> None:
    """Crea l'utente admin con password 'admin' se non esiste ancora nel DB."""
    from auth.password import hash_password  # import locale per evitare circolarità
    from db.models import User

    db: Session = SessionLocal()
    try:
        existing = db.query(User).filter(User.username == "admin").first()
        if existing:
            return  # già presente, niente da fare

        admin_user = User(
            username  = "admin",
            email     = "admin@admin.com",
            hashed_pw = hash_password("admin"),
            role      = "admin",
        )
        db.add(admin_user)
        db.commit()
        print("🛡️  Utente admin creato (username=admin, password=admin).")
    finally:
        db.close()


def _seed_viewer() -> None:
    """Crea l'utente viewer con password 'viewer' se non esiste ancora nel DB."""
    from auth.password import hash_password  # import locale per evitare circolarità
    from db.models import User

    db: Session = SessionLocal()
    try:
        existing = db.query(User).filter(User.username == "viewer").first()
        if existing:
            return  # già presente, niente da fare

        viewer_user = User(
            username  = "viewer",
            email     = "viewer@viewer.com",
            hashed_pw = hash_password("viewer"),
            role      = "viewer",
        )
        db.add(viewer_user)
        db.commit()
        print("👁️  Utente viewer creato (username=viewer, password=viewer).")
    finally:
        db.close()
