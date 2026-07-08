from datetime import datetime
from typing import Optional
from pydantic import BaseModel

class EventBase(BaseModel):
    title: str
    event_date: datetime
    registration_deadline: Optional[datetime] = None
    location: str
    max_participants: Optional[int] = None
    max_groups: Optional[int] = None
    min_people_per_group: Optional[int] = None
    max_people_per_group: Optional[int] = None
    registration_cost: Optional[float] = None
    weight_limit: Optional[float] = None
    description: Optional[str] = None

class EventCreate(EventBase):
    pass

class EventUpdate(BaseModel):
    title: Optional[str] = None
    event_date: Optional[datetime] = None
    registration_deadline: Optional[datetime] = None
    location: Optional[str] = None
    max_participants: Optional[int] = None
    max_groups: Optional[int] = None
    min_people_per_group: Optional[int] = None
    max_people_per_group: Optional[int] = None
    registration_cost: Optional[float] = None
    weight_limit: Optional[float] = None
    description: Optional[str] = None

class EventResponse(EventBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True
