"""
Modelli ORM SQLAlchemy per il database.

Tabelle:
  - users          → credenziali e ruoli degli utenti
  - refresh_tokens → refresh token hashati (per logout / revoca)
  - events         → eventi/gare in calendario
  - kartodromi     → kartodromi disponibili con URL live timing
"""

from datetime import datetime, date, timezone

from sqlalchemy import (
    Boolean, Column, DateTime, Date, ForeignKey, Integer, String, Float, Text, UniqueConstraint
)
from sqlalchemy.orm import declarative_base

Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id         = Column(Integer, primary_key=True, index=True)
    username   = Column(String, unique=True, nullable=False, index=True)
    first_name = Column(String, nullable=True)
    last_name  = Column(String, nullable=True)
    profile_picture_url = Column(String, nullable=True)
    email      = Column(String, unique=True, nullable=False, index=True)
    hashed_pw  = Column(String, nullable=False)   # bcrypt hash, mai plaintext
    role       = Column(String, default="user", nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id         = Column(Integer, primary_key=True, index=True)
    user_id    = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    token_hash = Column(String, nullable=False, index=True)  # SHA-256 del token raw
    expires_at = Column(DateTime, nullable=False)
    revoked    = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))


class Event(Base):
    __tablename__ = "events"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False) # Titolo o nome dell'evento
    event_date = Column(DateTime, nullable=False) # data evento
    registration_deadline = Column(DateTime, nullable=True) # data fine iscrizioni (calcolata)
    days_before_deadline = Column(Integer, nullable=True) # giorni prima dell'evento per chiudere le iscrizioni
    location = Column(String, nullable=False) # luogo evento
    max_participants = Column(Integer, nullable=True) # massimo numero di partecipanti
    min_people_per_group = Column(Integer, nullable=True) # minimo numero di persone per gruppo
    max_people_per_group = Column(Integer, nullable=True) # massimo numero di persone per gruppo
    registration_cost = Column(Float, nullable=True) # costo di iscrizione a persona
    weight_limit = Column(Float, nullable=True) # peso limite (opzionale)
    kart = Column(String, nullable=True) # tipo di kart (es. CRG, Sodi, ecc.)
    description = Column(Text, nullable=True) # testo libero descrittivo dell'evento
    race_duration = Column(Integer, nullable=True) # durata gara in minuti
    max_stint_duration = Column(Integer, nullable=True) # durata massima stint in minuti
    status = Column(String, default="scheduled", nullable=False) # "scheduled" | "started" | "finished"
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))


class Kartodromo(Base):
    __tablename__ = "kartodromi"

    id         = Column(Integer, primary_key=True, index=True)
    nome       = Column(String, nullable=False)            # nome del kartodromo
    luogo      = Column(String, nullable=False, default="") # città e provincia (es. "Ottobiano, PV")
    url        = Column(String, nullable=False, unique=True) # URL pagina live timing
    sito_web   = Column(String, nullable=False, default="") # URL sito ufficiale del kartodromo
    image_url  = Column(String, nullable=True)             # URL immagine grafica circuito (vista dall'alto)
    attivo     = Column(Boolean, default=True, nullable=False) # se False viene nascosto nel client
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))


class EventRegistration(Base):
    __tablename__ = "event_registrations"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True)  # Nullable per email non registrate
    event_id = Column(Integer, ForeignKey("events.id", ondelete="CASCADE"), nullable=False)
    status = Column(String, default="pending_payment", nullable=False)
    # Campi squadra
    team_name = Column(String, nullable=True)        # nome della squadra (solo per gare a squadre)
    team_id = Column(String, nullable=True)          # UUID condiviso da tutti i membri del team
    is_team_leader = Column(Boolean, default=False, nullable=False)  # True per chi ha registrato il team
    member_email = Column(String, nullable=True)     # email del membro (anche non registrato)
    accepts_extra_pilots = Column(Boolean, default=False, nullable=False) # Se la squadra accetta piloti aggiuntivi inseriti dagli admin
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))

    __table_args__ = (
        UniqueConstraint('user_id', 'event_id', name='uq_user_event'),
    )


class EventResult(Base):
    """
    Risultato di un pilota in una gara.

    - is_official=True  → inserito dall'admin (via CSV o manualmente)
    - is_official=False → auto-dichiarato dal pilota
    In caso di gara a squadre tutti i membri condividono la stessa posizione.
    """
    __tablename__ = "event_results"

    id           = Column(Integer, primary_key=True, index=True)
    event_id     = Column(Integer, ForeignKey("events.id",    ondelete="CASCADE"), nullable=False)
    user_id      = Column(Integer, ForeignKey("users.id",     ondelete="CASCADE"), nullable=True)
    driver_name  = Column(String,  nullable=True)   # nome pilota dal CSV
    member_email = Column(String,  nullable=True)   # email anche se non registrato nel sistema
    position     = Column(Integer, nullable=True)   # posizione finale (None = non pubblicata)
    best_lap_ms  = Column(Integer, nullable=True)   # miglior giro in millisecondi
    gap          = Column(String,  nullable=True)   # distacco
    laps         = Column(Integer, nullable=True)   # numero di giri
    is_official  = Column(Boolean, default=False, nullable=False)  # True = admin, False = utente
    team_id      = Column(String,  nullable=True)   # UUID team (gare a squadre)
    team_name    = Column(String,  nullable=True)   # nome squadra
    note         = Column(Text,    nullable=True)
    created_at   = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))


class KartodromoResult(Base):
    """
    Risultato personale auto-dichiarato di un pilota su un determinato circuito (fuori da eventi ufficiali).
    """
    __tablename__ = "kartodromo_results"

    id            = Column(Integer, primary_key=True, index=True)
    user_id       = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    kartodromo_id = Column(Integer, ForeignKey("kartodromi.id", ondelete="CASCADE"), nullable=False)
    best_lap_ms   = Column(Integer, nullable=False)   # miglior giro in millisecondi
    date          = Column(Date, nullable=False)      # data della prova libera
    created_at    = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))


class Notification(Base):
    """
    Notifica generata dal server per azioni admin (es. spostamento in waitlist, conferma iscrizione).
    """
    __tablename__ = "notifications"

    id         = Column(Integer, primary_key=True, index=True)
    user_id    = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    event_id   = Column(Integer, ForeignKey("events.id", ondelete="CASCADE"), nullable=True)
    type       = Column(String, nullable=False)   # "registration_accepted", "moved_to_waitlist", ...
    title      = Column(String, nullable=False)
    message    = Column(Text, nullable=False)
    is_read    = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))


class LiveKartAssignment(Base):
    """
    Assegnazione numero kart → team per un evento live.
    Creata dal Race Director all'inizio della gara.
    Eliminata automaticamente quando l'evento viene cancellato (cascade).
    """
    __tablename__ = "live_kart_assignments"

    id          = Column(Integer, primary_key=True, index=True)
    event_id    = Column(Integer, ForeignKey("events.id", ondelete="CASCADE"), nullable=False)
    team_id     = Column(String, nullable=False)       # UUID team (da EventRegistration.team_id)
    kart_number = Column(Integer, nullable=False)      # numero kart fisico assegnato al team
    team_name   = Column(String, nullable=True)        # nome squadra (denormalizzato per comodità)
    created_at  = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))

    __table_args__ = (
        UniqueConstraint('event_id', 'kart_number', name='uq_event_kart'),
    )


class PenaltyType(Base):
    """
    Tipi di penalità predefinite e avvisi standard (es. track limits).
    """
    __tablename__ = "penalty_types"

    id                = Column(Integer, primary_key=True, index=True)
    code              = Column(String, unique=True, nullable=False, index=True) # es. "false_start"
    name              = Column(String, nullable=False)                          # es. "Falsa Partenza"
    action            = Column(String, nullable=False)                          # "time_added", "stop_go", "drive_through", "warning", "custom"
    default_seconds   = Column(Integer, nullable=True)                          # 10, 30, ecc.
    is_active         = Column(Boolean, default=True, nullable=False)
    sort_order        = Column(Integer, default=0, nullable=False)
    
    # Auto-penalty per avvisi (es. track limits)
    warning_threshold = Column(Integer, nullable=True)                          # Numero avvisi prima della penalità (es. 3)
    auto_penalty_code = Column(String, nullable=True)                           # Codice della penalità automatica da assegnare


class RacePenalty(Base):
    """
    Penalità assegnata da un Race Director a un numero kart durante la gara live.
    Eliminata automaticamente quando l'evento viene cancellato (cascade).
    """
    __tablename__ = "race_penalties"

    id           = Column(Integer, primary_key=True, index=True)
    event_id     = Column(Integer, ForeignKey("events.id", ondelete="CASCADE"), nullable=False)
    kart_number  = Column(Integer, nullable=False)     # kart destinatario della penalità
    penalty_type = Column(String, nullable=False)      # tipo penalità
    seconds      = Column(Integer, nullable=True)      # secondi (solo per 'time_added' e 'stop_go')
    note         = Column(Text, nullable=True)         # nota libera opzionale
    created_at   = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))


class RaceMessage(Base):
    """
    Messaggio live inviato dal Race Director durante la gara.
    target_kart=None → broadcast a tutti i team.
    target_kart=N    → visibile solo al team con quel numero kart.
    Eliminato automaticamente quando l'evento viene cancellato (cascade).
    """
    __tablename__ = "race_messages"

    id           = Column(Integer, primary_key=True, index=True)
    event_id     = Column(Integer, ForeignKey("events.id", ondelete="CASCADE"), nullable=False)
    target_kart  = Column(Integer, nullable=True)      # None = broadcast
    message_type = Column(String, nullable=False)      # 'yellow_flag'|'red_flag'|'green_flag'|'info'|'custom'
    text         = Column(String, nullable=False)      # testo del messaggio
    created_at   = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))
