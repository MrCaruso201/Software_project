from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel

class EventBase(BaseModel):
    title: str
    event_date: datetime
    registration_deadline: Optional[datetime] = None
    location: str
    max_participants: Optional[int] = None
    min_people_per_group: Optional[int] = None
    max_people_per_group: Optional[int] = None
    registration_cost: Optional[float] = None
    weight_limit: Optional[float] = None
    kart: Optional[str] = None
    description: Optional[str] = None

class EventCreate(EventBase):
    pass

class EventUpdate(BaseModel):
    title: Optional[str] = None
    event_date: Optional[datetime] = None
    registration_deadline: Optional[datetime] = None
    location: Optional[str] = None
    max_participants: Optional[int] = None
    min_people_per_group: Optional[int] = None
    max_people_per_group: Optional[int] = None
    registration_cost: Optional[float] = None
    weight_limit: Optional[float] = None
    kart: Optional[str] = None
    description: Optional[str] = None

class EventResponse(EventBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True

# ── Iscrizione individuale ─────────────────────────────────────────────────────

class EventRegistrationResponse(BaseModel):
    id: int
    user_id: Optional[int]
    event_id: int
    status: str
    team_name: Optional[str] = None
    team_id: Optional[str] = None
    is_team_leader: bool = False
    member_email: Optional[str] = None
    accepts_extra_pilots: bool = False
    created_at: datetime

    class Config:
        from_attributes = True

# ── Iscrizione con dati utente (per admin) ────────────────────────────────────

class EventRegistrationWithUserResponse(BaseModel):
    id: int
    user_id: Optional[int]
    event_id: int
    status: str
    team_name: Optional[str] = None
    team_id: Optional[str] = None
    is_team_leader: bool = False
    member_email: Optional[str] = None
    accepts_extra_pilots: bool = False
    created_at: datetime
    username: Optional[str] = None
    email: Optional[str] = None
    profile_picture_url: Optional[str] = None  # URL relativo es. /static/profile_pictures/xxx.jpg

    class Config:
        from_attributes = True

# ── Squadra aggregata (per admin) ─────────────────────────────────────────────

class TeamMemberResponse(BaseModel):
    registration_id: int
    user_id: Optional[int]
    username: Optional[str]
    email: Optional[str]
    is_team_leader: bool
    status: str
    profile_picture_url: Optional[str] = None

class TeamRegistrationResponse(BaseModel):
    team_id: str
    team_name: str
    event_id: int
    members: List[TeamMemberResponse]
    accepts_extra_pilots: bool = False
    overall_status: str  # "confirmed" se almeno 1 confermato, altrimenti "pending_payment"

# ── Request body per iscrizione a squadre ────────────────────────────────────

class TeamRegistrationRequest(BaseModel):
    team_name: str
    member_emails: List[str]  # email degli altri partecipanti (escluso il leader)
    accepts_extra_pilots: bool = False
    leader_email: Optional[str] = None

class AdminIndividualRegistrationRequest(BaseModel):
    email: str

class AdminTeamRegistrationRequest(BaseModel):
    team_name: str
    leader_email: str
    member_emails: List[str]
    accepts_extra_pilots: bool = False

class AdminAssignTeamRequest(BaseModel):
    registration_ids: List[int]

class AdminCreateTeamFromIndividualsRequest(BaseModel):
    team_name: str
    leader_registration_id: int
    member_registration_ids: List[int]
    accepts_extra_pilots: bool = False
