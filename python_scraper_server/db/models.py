"""
Modelli ORM SQLAlchemy per il database.

Tabelle:
  - users          → credenziali e ruoli degli utenti
  - refresh_tokens → refresh token hashati (per logout / revoca)
"""

from datetime import datetime, timezone

from sqlalchemy import (
    Boolean, Column, DateTime, ForeignKey, Integer, String, Float
)
from sqlalchemy.orm import declarative_base

Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id         = Column(Integer, primary_key=True, index=True)
    username   = Column(String, unique=True, nullable=False, index=True)
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
    registration_deadline = Column(DateTime, nullable=True) # data fine iscrizioni
    location = Column(String, nullable=False) # luogo evento
    max_participants = Column(Integer, nullable=True) # massimo numero di partecipanti
    max_groups = Column(Integer, nullable=True) # massimo numero gruppi
    min_people_per_group = Column(Integer, nullable=True) # minimo numero di persone per gruppo
    max_people_per_group = Column(Integer, nullable=True) # massimo numero di persone per gruppo
    registration_cost = Column(Float, nullable=True) # costo di iscrizione a persona
    weight_limit = Column(Float, nullable=True) # peso limite (opzionale)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None))
