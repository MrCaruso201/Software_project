from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from datetime import datetime, timezone

from db.database import get_db
from db.models import Event, EventRegistration, User
from events.schemas import EventCreate, EventUpdate, EventResponse, EventRegistrationResponse, EventRegistrationWithUserResponse
from auth.dependencies import get_current_user
from auth.roles import Role, has_permission

router = APIRouter(prefix="/events", tags=["events"])

@router.post("/", response_model=EventResponse, status_code=status.HTTP_201_CREATED)
def create_event(event: EventCreate, db: Session = Depends(get_db)):
    db_event = Event(**event.model_dump())
    db.add(db_event)
    db.commit()
    db.refresh(db_event)
    return db_event

@router.get("/", response_model=List[EventResponse])
def get_events(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    events = db.query(Event).offset(skip).limit(limit).all()
    return events

@router.get("/registrations/me", response_model=List[EventRegistrationResponse])
def get_my_registrations(user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    user_id = int(user_payload["sub"])
    regs = db.query(EventRegistration).filter(EventRegistration.user_id == user_id).all()
    return regs

@router.get("/{event_id}", response_model=EventResponse)
def get_event(event_id: int, db: Session = Depends(get_db)):
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    return event

@router.patch("/{event_id}", response_model=EventResponse)
def update_event(event_id: int, event_update: EventUpdate, db: Session = Depends(get_db)):
    db_event = db.query(Event).filter(Event.id == event_id).first()
    if not db_event:
        raise HTTPException(status_code=404, detail="Event not found")
    
    update_data = event_update.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(db_event, key, value)
        
    db.commit()
    db.refresh(db_event)
    return db_event

@router.delete("/{event_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_event(event_id: int, db: Session = Depends(get_db)):
    db_event = db.query(Event).filter(Event.id == event_id).first()
    if not db_event:
        raise HTTPException(status_code=404, detail="Event not found")
        
    db.delete(db_event)
    db.commit()
    return None

@router.post("/{event_id}/register", response_model=EventRegistrationResponse, status_code=status.HTTP_201_CREATED)
def register_for_event(event_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    user_id = int(user_payload["sub"])
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    if event.registration_deadline and now > event.registration_deadline:
        raise HTTPException(status_code=400, detail="Registration deadline passed")
        
    if event.max_participants is not None:
        count = db.query(EventRegistration).filter(EventRegistration.event_id == event_id).count()
        if count >= event.max_participants:
            raise HTTPException(status_code=400, detail="Event is full")
            
    existing = db.query(EventRegistration).filter(EventRegistration.user_id == user_id, EventRegistration.event_id == event_id).first()
    if existing:
        raise HTTPException(status_code=400, detail="Already registered")
        
    reg = EventRegistration(user_id=user_id, event_id=event_id)
    db.add(reg)
    db.commit()
    db.refresh(reg)
    return reg

@router.delete("/{event_id}/register", status_code=status.HTTP_204_NO_CONTENT)
def unregister_from_event(event_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    user_id = int(user_payload["sub"])
    reg = db.query(EventRegistration).filter(EventRegistration.user_id == user_id, EventRegistration.event_id == event_id).first()
    if not reg:
        raise HTTPException(status_code=404, detail="Registration not found")
        
    if reg.status == "confirmed":
        raise HTTPException(status_code=403, detail="Cannot cancel a confirmed registration")
        
    db.delete(reg)
    db.commit()
    return None

@router.get("/{event_id}/registrations", response_model=List[EventRegistrationWithUserResponse])
def get_event_registrations(event_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    regs = db.query(EventRegistration, User).join(User, EventRegistration.user_id == User.id).filter(EventRegistration.event_id == event_id).all()
    
    result = []
    for reg, user in regs:
        result.append({
            "id": reg.id,
            "user_id": reg.user_id,
            "event_id": reg.event_id,
            "status": reg.status,
            "created_at": reg.created_at,
            "username": user.username,
            "email": user.email
        })
    return result

@router.patch("/{event_id}/registrations/{user_id}/confirm", response_model=EventRegistrationResponse)
def confirm_registration(event_id: int, user_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    reg = db.query(EventRegistration).filter(EventRegistration.user_id == user_id, EventRegistration.event_id == event_id).first()
    if not reg:
        raise HTTPException(status_code=404, detail="Registration not found")
        
    reg.status = "confirmed"
    db.commit()
    db.refresh(reg)
    return reg

@router.delete("/{event_id}/registrations/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_registration(event_id: int, user_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    reg = db.query(EventRegistration).filter(EventRegistration.user_id == user_id, EventRegistration.event_id == event_id).first()
    if not reg:
        raise HTTPException(status_code=404, detail="Registration not found")
        
    db.delete(reg)
    db.commit()
    return None
