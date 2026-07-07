"""
Connessione al database SQLite tramite SQLAlchemy.

Espone:
  - engine      → connessione diretta al DB
  - SessionLocal → factory per le sessioni ORM
  - get_db()    → dependency FastAPI che apre/chiude la sessione per ogni request
  - init_db()   → crea le tabelle all'avvio del server (idempotente)
"""

from pathlib import Path
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.exc import OperationalError

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

    # --- Migrazioni colonne aggiunte dopo la creazione iniziale ---
    _apply_migrations()

    # --- Seed: utenti di default ---
    _seed_admin()
    _seed_viewer()

    # --- Seed: kartodromi di default ---
    _seed_kartodromi()


def _apply_migrations() -> None:
    """Aggiunge colonne al DB esistente senza sovrascrivere i dati (migration manuale)."""
    migrations = [
        "ALTER TABLE kartodromi ADD COLUMN sito_web TEXT NOT NULL DEFAULT ''",
    ]
    with engine.connect() as conn:
        for stmt in migrations:
            try:
                conn.execute(text(stmt))
                conn.commit()
            except OperationalError:
                pass  # colonna già presente, ignora


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


def _seed_kartodromi() -> None:
    """Popola la tabella kartodromi con i circuiti di default al primo avvio."""
    from db.models import Kartodromo  # import locale per evitare circolarità

    _DEFAULT_KARTODROMI = [
        {"nome": "Simulatore",                   "luogo": "",                    "url": "https://live.racefacer.com/simulator"},
        {"nome": "Ottobiano Motorsport",          "luogo": "Ottobiano, PV",       "url": "https://live.racefacer.com/ottobianomotorsport"},
        {"nome": "Karting Club",                  "luogo": "Messina, ME",         "url": "https://live.racefacer.com/kartodromomessina"},
        {"nome": "Orlando Kart Center",           "luogo": "Orlando, FL",         "url": "https://live.racefacer.com/orlandokartcenter"},
        {"nome": "Misanino",                      "luogo": "Misano Adriatico, RN", "url": "https://www.apex-timing.com/live-timing/misanino-kart/"},
    ]

    db: Session = SessionLocal()
    try:
        for data in _DEFAULT_KARTODROMI:
            existing = db.query(Kartodromo).filter(Kartodromo.url == data["url"]).first()
            if existing:
                continue  # già presente, niente da fare
            db.add(Kartodromo(**data))
        db.commit()
        print("🏎️  Kartodromi di default caricati.")
    finally:
        db.close()
