import uuid
from typing import List, Optional
from fastapi import APIRouter, Body, Depends, HTTPException, status
from sqlalchemy.orm import Session

from datetime import datetime, timezone

from db.database import get_db
from db.models import Event, EventRegistration, User
from events.schemas import (
    EventCreate, EventUpdate, EventResponse,
    EventRegistrationResponse, EventRegistrationWithUserResponse,
    TeamRegistrationRequest, TeamRegistrationResponse, TeamMemberResponse
)
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

# ── Iscrizione ────────────────────────────────────────────────────────────────

@router.post("/{event_id}/register", response_model=EventRegistrationResponse, status_code=status.HTTP_201_CREATED)
def register_for_event(
    event_id: int,
    team_data: Optional[TeamRegistrationRequest] = Body(default=None),
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = int(user_payload["sub"])
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    if event.registration_deadline and now > event.registration_deadline:
        raise HTTPException(status_code=400, detail="Registration deadline passed")

    # Determina se è una gara a squadre
    is_team_event = event.max_people_per_group is not None and event.max_people_per_group > 1

    if is_team_event:
        # Gara a squadre: richiede team_data
        if not team_data or not team_data.team_name.strip():
            raise HTTPException(status_code=400, detail="Nome squadra obbligatorio per gare a squadre")
        
        expected_members = event.max_people_per_group - 1  # escluso il leader
        if len(team_data.member_emails) > expected_members:
            raise HTTPException(
                status_code=400,
                detail=f"Troppi membri: massimo {event.max_people_per_group} per squadra"
            )
        
        # Controlla se il leader è già iscritto
        existing = db.query(EventRegistration).filter(
            EventRegistration.user_id == user_id,
            EventRegistration.event_id == event_id
        ).first()
        if existing:
            raise HTTPException(status_code=400, detail="Già iscritto a questo evento")
        
        # Controlla capienza gruppi (max_participants funge da max_squadre)
        if event.max_participants is not None:
            existing_teams = db.query(EventRegistration.team_id).filter(
                EventRegistration.event_id == event_id,
                EventRegistration.team_id.isnot(None),
                EventRegistration.is_team_leader == True
            ).distinct().count()
            if existing_teams >= event.max_participants:
                raise HTTPException(status_code=400, detail="Numero massimo di squadre raggiunto")

        # Genera UUID per il team
        new_team_id = str(uuid.uuid4())
        
        # Ottieni l'email del leader
        leader_user = db.query(User).filter(User.id == user_id).first()
        leader_email = leader_user.email if leader_user else user_payload.get("email", "")

        # Registra il leader (is_team_leader=True)
        leader_reg = EventRegistration(
            user_id=user_id,
            event_id=event_id,
            team_name=team_data.team_name.strip(),
            team_id=new_team_id,
            is_team_leader=True,
            member_email=leader_email,
        )
        db.add(leader_reg)
        
        # Registra gli altri membri (tramite email, user_id opzionale)
        for email in team_data.member_emails:
            email = email.strip().lower()
            if not email:
                continue
            # Cerca se l'utente è nel sistema
            member_user = db.query(User).filter(User.email == email).first()
            member_user_id = member_user.id if member_user else None
            
            # Controlla se quell'utente (se registrato) è già iscritto
            if member_user_id:
                already = db.query(EventRegistration).filter(
                    EventRegistration.user_id == member_user_id,
                    EventRegistration.event_id == event_id
                ).first()
                if already:
                    raise HTTPException(
                        status_code=400,
                        detail=f"L'utente con email {email} è già iscritto all'evento"
                    )
            
            member_reg = EventRegistration(
                user_id=member_user_id,
                event_id=event_id,
                team_name=team_data.team_name.strip(),
                team_id=new_team_id,
                is_team_leader=False,
                member_email=email,
            )
            db.add(member_reg)
        
        db.commit()
        db.refresh(leader_reg)
        return leader_reg

    else:
        # Gara individuale: logica originale
        if event.max_participants is not None:
            count = db.query(EventRegistration).filter(EventRegistration.event_id == event_id).count()
            if count >= event.max_participants:
                raise HTTPException(status_code=400, detail="Event is full")
                
        existing = db.query(EventRegistration).filter(
            EventRegistration.user_id == user_id,
            EventRegistration.event_id == event_id
        ).first()
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
    reg = db.query(EventRegistration).filter(
        EventRegistration.user_id == user_id,
        EventRegistration.event_id == event_id
    ).first()
    if not reg:
        raise HTTPException(status_code=404, detail="Registration not found")
        
    if reg.status == "confirmed":
        raise HTTPException(status_code=403, detail="Cannot cancel a confirmed registration")
    
    # Se fa parte di un team, solo il leader può annullare (e annulla tutti)
    if reg.team_id:
        if not reg.is_team_leader:
            raise HTTPException(status_code=403, detail="Solo il capogruppo può annullare l'iscrizione del team")
        # Cancella tutte le registrazioni del team
        db.query(EventRegistration).filter(
            EventRegistration.team_id == reg.team_id,
            EventRegistration.event_id == event_id
        ).delete()
    else:
        db.delete(reg)
    
    
    db.commit()
    return None


@router.get("/{event_id}/registrations/team/{team_id}", response_model=TeamRegistrationResponse)
def get_my_team_registration(
    event_id: int,
    team_id: str,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = int(user_payload["sub"])
    
    # Verifica che l'utente faccia parte del team
    my_reg = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id,
        EventRegistration.user_id == user_id
    ).first()
    
    if not my_reg:
        raise HTTPException(status_code=403, detail="Non fai parte di questo team")
        
    members = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id
    ).all()
    
    if not members:
        raise HTTPException(status_code=404, detail="Team non trovato")
        
    team_name = members[0].team_name or "Squadra Senza Nome"
    member_responses = []
    
    for m in members:
        user = db.query(User).filter(User.id == m.user_id).first() if m.user_id else None
        member_responses.append(TeamMemberResponse(
            registration_id=m.id,
            user_id=m.user_id,
            username=user.username if user else None,
            email=m.member_email or (user.email if user else None),
            is_team_leader=m.is_team_leader,
            status=m.status,
            profile_picture_url=user.profile_picture_url if user else None,
        ))
        
    leader = next((m for m in members if m.is_team_leader), None)
    overall_status = leader.status if leader else "pending_payment"
    
    return TeamRegistrationResponse(
        team_id=team_id,
        team_name=team_name,
        event_id=event_id,
        members=member_responses,
        overall_status=overall_status,
    )


@router.put("/{event_id}/registrations/team/{team_id}", response_model=EventRegistrationResponse)
def update_team_registration(
    event_id: int,
    team_id: str,
    team_data: TeamRegistrationRequest,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = int(user_payload["sub"])
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
        
    leader_reg = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id,
        EventRegistration.is_team_leader == True
    ).first()
    
    if not leader_reg:
        raise HTTPException(status_code=404, detail="Team non trovato o non sei il leader")
        
    if leader_reg.user_id != user_id:
        raise HTTPException(status_code=403, detail="Solo il capogruppo può modificare il team")
        
    # Rimosso check se confermata: permettiamo modifiche anche da pagata
    expected_members = event.max_people_per_group - 1
    if len(team_data.member_emails) > expected_members:
        raise HTTPException(
            status_code=400,
            detail=f"Troppi membri: massimo {event.max_people_per_group} per squadra"
        )
        
    # Elimina vecchi membri non leader
    db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.is_team_leader == False
    ).delete()
    
    # Aggiorna nome team
    leader_reg.team_name = team_data.team_name.strip()
    
    # Inserisci nuovi membri
    for email in team_data.member_emails:
        email = email.strip().lower()
        if not email:
            continue
            
        member_user = db.query(User).filter(User.email == email).first()
        member_user_id = member_user.id if member_user else None
        
        if member_user_id:
            already = db.query(EventRegistration).filter(
                EventRegistration.user_id == member_user_id,
                EventRegistration.event_id == event_id,
                EventRegistration.team_id != team_id # Non è già in questo team (teoricamente impossibile qui perché l'abbiamo svuotato)
            ).first()
            if already:
                raise HTTPException(
                    status_code=400,
                    detail=f"L'utente con email {email} è già iscritto a questo evento in un'altra squadra"
                )
                
        member_reg = EventRegistration(
            user_id=member_user_id,
            event_id=event_id,
            team_name=team_data.team_name.strip(),
            team_id=team_id,
            is_team_leader=False,
            member_email=email,
            status=leader_reg.status
        )
        db.add(member_reg)

    db.commit()
    db.refresh(leader_reg)
    return leader_reg


# ── Vista admin: iscrizioni flat ──────────────────────────────────────────────

@router.get("/{event_id}/registrations", response_model=List[EventRegistrationWithUserResponse])
def get_event_registrations(event_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    regs = db.query(EventRegistration).filter(EventRegistration.event_id == event_id).all()
    
    result = []
    for reg in regs:
        user = db.query(User).filter(User.id == reg.user_id).first() if reg.user_id else None
        result.append({
            "id": reg.id,
            "user_id": reg.user_id,
            "event_id": reg.event_id,
            "status": reg.status,
            "team_name": reg.team_name,
            "team_id": reg.team_id,
            "is_team_leader": reg.is_team_leader,
            "member_email": reg.member_email,
            "created_at": reg.created_at,
            "username": user.username if user else None,
            "email": reg.member_email or (user.email if user else None),
            "profile_picture_url": user.profile_picture_url if user else None,
        })
    return result


# ── Vista admin: iscrizioni raggruppate per team ──────────────────────────────

@router.get("/{event_id}/registrations/teams", response_model=List[TeamRegistrationResponse])
def get_event_team_registrations(event_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    regs = db.query(EventRegistration).filter(
        EventRegistration.event_id == event_id,
        EventRegistration.team_id.isnot(None)
    ).all()

    # Raggruppa per team_id
    teams: dict[str, list] = {}
    for reg in regs:
        tid = reg.team_id
        if tid not in teams:
            teams[tid] = []
        teams[tid].append(reg)

    result = []
    for team_id, members in teams.items():
        team_name = members[0].team_name or "Squadra Senza Nome"
        
        member_responses = []
        for m in members:
            user = db.query(User).filter(User.id == m.user_id).first() if m.user_id else None
            member_responses.append(TeamMemberResponse(
                registration_id=m.id,
                user_id=m.user_id,
                username=user.username if user else None,
                email=m.member_email or (user.email if user else None),
                is_team_leader=m.is_team_leader,
                status=m.status,
                profile_picture_url=user.profile_picture_url if user else None,
            ))
        
        # Status complessivo: confirmed solo se il leader è confermato
        leader = next((m for m in members if m.is_team_leader), None)
        overall_status = leader.status if leader else "pending_payment"
        
        result.append(TeamRegistrationResponse(
            team_id=team_id,
            team_name=team_name,
            event_id=event_id,
            members=member_responses,
            overall_status=overall_status,
        ))
    
    return result


# ── Admin: conferma iscrizione ────────────────────────────────────────────────

@router.patch("/{event_id}/registrations/{user_id}/confirm", response_model=EventRegistrationResponse)
def confirm_registration(event_id: int, user_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    reg = db.query(EventRegistration).filter(
        EventRegistration.user_id == user_id,
        EventRegistration.event_id == event_id
    ).first()
    if not reg:
        raise HTTPException(status_code=404, detail="Registration not found")
    
    # Per i team: conferma tutto il team quando si conferma il leader
    if reg.team_id and reg.is_team_leader:
        db.query(EventRegistration).filter(
            EventRegistration.team_id == reg.team_id,
            EventRegistration.event_id == event_id
        ).update({"status": "confirmed"})
    else:
        reg.status = "confirmed"
    
    db.commit()
    db.refresh(reg)
    return reg


# ── Admin: elimina iscrizione ─────────────────────────────────────────────────

@router.delete("/{event_id}/registrations/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_registration(event_id: int, user_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    reg = db.query(EventRegistration).filter(
        EventRegistration.user_id == user_id,
        EventRegistration.event_id == event_id
    ).first()
    if not reg:
        raise HTTPException(status_code=404, detail="Registration not found")
    
    # Se fa parte di un team, elimina tutto il team
    if reg.team_id:
        db.query(EventRegistration).filter(
            EventRegistration.team_id == reg.team_id,
            EventRegistration.event_id == event_id
        ).delete()
    else:
        db.delete(reg)
    
    db.commit()
    return None


# ── Admin: elimina registrazione per team_id ──────────────────────────────────

@router.delete("/{event_id}/registrations/team/{team_id}", status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_team_registration(event_id: int, team_id: str, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    
    deleted = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id
    ).delete()
    
    if not deleted:
        raise HTTPException(status_code=404, detail="Team registration not found")
    
    db.commit()
    return None


# ── Admin: conferma iscrizione per team_id ────────────────────────────────────

@router.patch("/{event_id}/registrations/team/{team_id}/confirm", status_code=status.HTTP_200_OK)
def admin_confirm_team_registration(event_id: int, team_id: str, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    
    updated = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id
    ).update({"status": "confirmed"})
    
    if not updated:
        raise HTTPException(status_code=404, detail="Team registration not found")
    
    db.commit()
    return {"detail": "Team confirmed"}
