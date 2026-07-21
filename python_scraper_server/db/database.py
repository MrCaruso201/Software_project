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
        "ALTER TABLE kartodromi ADD COLUMN image_url TEXT",
        "ALTER TABLE events ADD COLUMN description TEXT",
        # Colonne squadra per event_registrations
        "ALTER TABLE event_registrations ADD COLUMN team_name TEXT",
        "ALTER TABLE event_registrations ADD COLUMN team_id TEXT",
        "ALTER TABLE event_registrations ADD COLUMN is_team_leader INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE event_registrations ADD COLUMN member_email TEXT",
    ]
    with engine.connect() as conn:
        for stmt in migrations:
            try:
                conn.execute(text(stmt))
                conn.commit()
            except OperationalError:
                pass  # colonna già presente, ignora

    # SQLite non supporta ALTER COLUMN: ricreiamo la tabella se user_id è ancora NOT NULL
    _migrate_event_registrations_nullable_userid()


def _migrate_event_registrations_nullable_userid() -> None:
    """Rende user_id nullable in event_registrations.
    SQLite non ha ALTER COLUMN: ricreiamo la tabella via sqlite3 raw (no ORM).
    Rimuoviamo anche il UNIQUE(user_id, event_id) perché non ha senso con NULL."""
    import sqlite3
    # Ricava il path del file SQLite dall'URL del motore
    db_path = str(engine.url).replace("sqlite:///", "")
    
    conn = sqlite3.connect(db_path)
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=OFF")

        # Controlla se user_id è ancora NOT NULL
        info = conn.execute("PRAGMA table_info(event_registrations)").fetchall()
        user_id_col = next((r for r in info if r[1] == "user_id"), None)
        if user_id_col is None:
            print("⚠️  Colonna user_id non trovata in event_registrations")
            return
        if user_id_col[3] == 0:
            print("ℹ️  user_id già nullable, nessuna migrazione necessaria.")
            return

        print(f"🔄 Migrazione: user_id in event_registrations è NOT NULL, ricreazione tabella...")

        conn.execute("DROP TABLE IF EXISTS event_registrations_new")
        conn.execute("""
            CREATE TABLE event_registrations_new (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id      INTEGER REFERENCES users(id) ON DELETE CASCADE,
                event_id     INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
                status       TEXT NOT NULL DEFAULT 'pending_payment',
                team_name    TEXT,
                team_id      TEXT,
                is_team_leader INTEGER NOT NULL DEFAULT 0,
                member_email TEXT,
                created_at   DATETIME
            )
        """)
        conn.execute("""
            INSERT INTO event_registrations_new
                (id, user_id, event_id, status, team_name, team_id,
                 is_team_leader, member_email, created_at)
            SELECT id, user_id, event_id, status, team_name, team_id,
                   is_team_leader, member_email, created_at
            FROM event_registrations
        """)
        conn.execute("DROP TABLE event_registrations")
        conn.execute("ALTER TABLE event_registrations_new RENAME TO event_registrations")
        conn.execute("PRAGMA foreign_keys=ON")
        conn.commit()
        print("✅ Migrazione event_registrations completata: user_id ora nullable.")
    except Exception as e:
        conn.rollback()
        print(f"❌ Errore migrazione event_registrations: {e}")
    finally:
        conn.close()


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
