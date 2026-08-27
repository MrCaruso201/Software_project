"""Schema Pydantic per i risultati gara."""

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel


class EventResultResponse(BaseModel):
    id: int
    event_id: int
    user_id: Optional[int] = None
    driver_name: Optional[str] = None
    member_email: Optional[str] = None
    position: Optional[int] = None
    best_lap_ms: Optional[int] = None
    gap: Optional[str] = None
    laps: Optional[int] = None
    is_official: bool
    team_id: Optional[str] = None
    team_name: Optional[str] = None
    note: Optional[str] = None
    username: Optional[str] = None          # popolato dal join con users
    kart_number: Optional[int] = None
    profile_picture_url: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class SelfDeclaredResultRequest(BaseModel):
    best_lap_ms: int
    position: Optional[int] = None
    note: Optional[str] = None


class CSVImportResponse(BaseModel):
    imported: int
    errors: List[str]
