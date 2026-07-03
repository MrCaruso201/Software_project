"""
Modelli ORM SQLAlchemy per il database.

Tabelle:
  - users          → credenziali e ruoli degli utenti
  - refresh_tokens → refresh token hashati (per logout / revoca)
"""

from datetime import datetime, timezone

from sqlalchemy import (
    Boolean, Column, DateTime, ForeignKey, Integer, String
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
