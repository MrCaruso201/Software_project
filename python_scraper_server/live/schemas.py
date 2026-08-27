from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel


# ── Kart Assignment ──────────────────────────────────────────────────────────

class KartAssignmentCreate(BaseModel):
    team_id: str
    kart_number: int
    team_name: Optional[str] = None

class KartAssignmentResponse(BaseModel):
    id: int
    event_id: int
    team_id: str
    kart_number: int
    team_name: Optional[str] = None
    created_at: datetime
    # Penalità totali calcolate (secondi), 0 se nessuna
    total_penalty_seconds: int = 0

    class Config:
        from_attributes = True


# ── Race Penalty ─────────────────────────────────────────────────────────────

class PenaltyTypeResponse(BaseModel):
    id: int
    code: str
    name: str
    action: str
    default_seconds: Optional[int] = None
    warning_threshold: Optional[int] = None
    auto_penalty_code: Optional[str] = None
    
    class Config:
        from_attributes = True

class PenaltyCreate(BaseModel):
    kart_number: int
    penalty_type: str   # Deve corrispondere a penalty_types.code
    seconds: Optional[int] = None
    note: Optional[str] = None

class PenaltyResponse(BaseModel):
    id: int
    event_id: int
    kart_number: int
    penalty_type: str
    seconds: Optional[int] = None
    note: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


# ── Race Message ─────────────────────────────────────────────────────────────

class MessageCreate(BaseModel):
    target_kart: Optional[int] = None   # None = broadcast
    message_type: str                   # 'yellow_flag'|'red_flag'|'green_flag'|'info'|'custom'
    text: str

class MessageResponse(BaseModel):
    id: int
    event_id: int
    target_kart: Optional[int] = None
    message_type: str
    text: str
    created_at: datetime

    class Config:
        from_attributes = True


# ── My Kart (user) ───────────────────────────────────────────────────────────

class MyKartResponse(BaseModel):
    """Risposta per l'endpoint /live/{event_id}/my-kart — dati del kart del proprio team."""
    kart_number: Optional[int] = None          # None se il team non ha ancora un kart assegnato
    team_id: Optional[str] = None
    team_name: Optional[str] = None
    penalties: List[PenaltyResponse] = []
    messages: List[MessageResponse] = []       # solo messaggi rivolti a questo kart o broadcast
    total_penalty_seconds: int = 0


# ── Event Status Update ──────────────────────────────────────────────────────

class EventStatusUpdate(BaseModel):
    status: str  # "scheduled" | "started" | "finished"
    session_name: Optional[str] = None
