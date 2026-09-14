"""
Connessione al database SQLite tramite SQLAlchemy.

Espone:
  - engine      → connessione diretta al DB
  - SessionLocal → factory per le sessioni ORM
  - get_db()    → dependency FastAPI che apre/chiude la sessione per ogni request
  - init_db()   → crea le tabelle all'avvio del server (idempotente)
"""

from pathlib import Path
from sqlalchemy import create_engine, text, event
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.exc import OperationalError

# Il DB è nella cartella data/ del progetto, accanto ai file JSON di timing
_DB_PATH = Path(__file__).parent.parent / "data" / "kart_timing.db"
DATABASE_URL = f"sqlite:///{_DB_PATH}"

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},  # necessario per SQLite con FastAPI
)

@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()

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
    from db.models import Base, User, Notification  # import locale per evitare importazione circolare
    Base.metadata.create_all(bind=engine)
    print("✅ Database inizializzato.")

    # --- Migrazioni colonne aggiunte dopo la creazione iniziale ---
    _apply_migrations()

    # --- Seed: utenti di default ---
    _seed_admin()
    _seed_viewer()

    # --- Seed: kartodromi di default ---
    _seed_kartodromi()

    # --- Seed: tipi di penalità di default ---
    _seed_penalty_types()


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
        "ALTER TABLE event_registrations ADD COLUMN accepts_extra_pilots INTEGER NOT NULL DEFAULT 0",
        # Nuovi campi gara per events
        "ALTER TABLE events ADD COLUMN race_duration INTEGER",
        "ALTER TABLE events ADD COLUMN pit_stops_required INTEGER",
        "ALTER TABLE events ADD COLUMN max_stint_duration INTEGER",
        # Stato gara live e turni
        "ALTER TABLE events ADD COLUMN status TEXT NOT NULL DEFAULT 'scheduled'",
        "ALTER TABLE events ADD COLUMN session_name TEXT",
        # Liberatoria
        "ALTER TABLE events ADD COLUMN release_form_text TEXT",
        # Risultati multipli
        "ALTER TABLE event_results ADD COLUMN result_type TEXT NOT NULL DEFAULT 'final'",
        "ALTER TABLE live_kart_assignments ADD COLUMN stint_penalty_assessed INTEGER NOT NULL DEFAULT 0",
        # Stint tracking
        "ALTER TABLE live_kart_assignments ADD COLUMN is_in_pit INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE live_kart_assignments ADD COLUMN stint_elapsed_seconds INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE live_kart_assignments ADD COLUMN stint_last_resume DATETIME",
        # Race status (separato da event.status per non interferire con il ciclo di vita dell'evento)
        "ALTER TABLE events ADD COLUMN race_status TEXT NOT NULL DEFAULT 'not_started'",
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
        {"nome": "Simulatore",                   "luogo": "",                    "url": "https://simulator"},
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


def _seed_penalty_types() -> None:
    """Popola la tabella penalty_types con le penalità standard."""
    from db.models import PenaltyType, RacePenalty
    _DEFAULT_PENALTIES = [
        # code, name, action, default_seconds, warning_threshold, auto_penalty_code, sort_order
        # ── Penalità ─────────────────────────────────────────────────────────────
        {"code": "false_start",    "name": "Falsa partenza",                "action": "time_added",    "default_seconds": 10, "warning_threshold": None, "auto_penalty_code": None,              "sort_order": 10},
        {"code": "aggressive_driving", "name": "Guida aggressiva",          "action": "time_added",    "default_seconds": 10, "warning_threshold": None, "auto_penalty_code": None,              "sort_order": 20},
        {"code": "stint_time",     "name": "Tempo stint non rispettato",    "action": "time_added",    "default_seconds": 30, "warning_threshold": None, "auto_penalty_code": None,              "sort_order": 30},
        {"code": "pit_stop_time",  "name": "Tempo pit stop non rispettato", "action": "time_added",    "default_seconds": 30, "warning_threshold": None, "auto_penalty_code": None,              "sort_order": 40},
        {"code": "weight",         "name": "Peso non rispettato",           "action": "time_added",    "default_seconds": 30, "warning_threshold": None, "auto_penalty_code": None,              "sort_order": 50},
        {"code": "track_limits",            "name": "Track Limits",                 "action": "time_added",    "default_seconds": 10, "warning_threshold": None, "auto_penalty_code": None,              "sort_order": 55},
        # ── Avvisi (auto-penalty) ─────────────────────────────────────────────
        {"code": "warning_track_limits",      "name": "Avviso (Track Limits)",      "action": "warning", "default_seconds": None, "warning_threshold": 3, "auto_penalty_code": "track_limits",       "sort_order": 60},
        {"code": "warning_aggressive_driving","name": "Avviso (Guida Aggressiva)",  "action": "warning", "default_seconds": None, "warning_threshold": 3, "auto_penalty_code": "aggressive_driving", "sort_order": 70},
        # ── Bandiere ──────────────────────────────────────────────────────────
        {"code": "black_flag",     "name": "Bandiera Nera (Espulsione)",    "action": "drive_through", "default_seconds": None, "warning_threshold": None, "auto_penalty_code": None,              "sort_order": 80},
        {"code": "blue_flag",      "name": "Bandiera Blu (Doppiaggio)",     "action": "warning",       "default_seconds": None, "warning_threshold": None, "auto_penalty_code": None,              "sort_order": 90},
        # ── Personalizzati (ultimi) ───────────────────────────────────────────
        {"code": "custom",         "name": "Penalità personalizzata",       "action": "custom",        "default_seconds": None, "warning_threshold": None, "auto_penalty_code": None,              "sort_order": 100},
        {"code": "drop_position",  "name": "Drop 1 Position",               "action": "warning",       "default_seconds": None, "warning_threshold": None, "auto_penalty_code": None,              "sort_order": 110},
    ]

    # Codici obsoleti da rimuovere dal DB
    _OBSOLETE_CODES = ["directive"]

    db: Session = SessionLocal()
    try:
        # Migra il vecchio codice, preservando configurazione e penalità storiche.
        legacy = db.query(PenaltyType).filter(PenaltyType.code == "track_limits_10s").first()
        current = db.query(PenaltyType).filter(PenaltyType.code == "track_limits").first()
        if legacy:
            if current:
                # Se esistono entrambi, prevale la configurazione del codice nuovo.
                db.delete(legacy)
            else:
                legacy.code = "track_limits"
        db.query(RacePenalty).filter(RacePenalty.penalty_type == "track_limits_10s").update(
            {RacePenalty.penalty_type: "track_limits"}, synchronize_session=False
        )
        db.query(PenaltyType).filter(PenaltyType.auto_penalty_code == "track_limits_10s").update(
            {PenaltyType.auto_penalty_code: "track_limits"}, synchronize_session=False
        )
        db.flush()

        # Rimuovi codici obsoleti (solo se non usati da penalità esistenti)
        for code in _OBSOLETE_CODES:
            obsolete = db.query(PenaltyType).filter(PenaltyType.code == code).first()
            if obsolete:
                db.delete(obsolete)

        for data in _DEFAULT_PENALTIES:
            existing = db.query(PenaltyType).filter(PenaltyType.code == data["code"]).first()
            if existing:
                # Aggiorna i metadati, preservando i valori configurati dall'admin.
                existing.name = data["name"]
                existing.action = data["action"]
                existing.auto_penalty_code = data["auto_penalty_code"]
                existing.sort_order = data["sort_order"]
            else:
                db.add(PenaltyType(**data))
        db.commit()
        print("🚩  Tipi di penalità di default caricati.")
    finally:
        db.close()
