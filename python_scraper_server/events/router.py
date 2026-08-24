import uuid
from typing import List, Optional
from fastapi import APIRouter, Body, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import func

from datetime import datetime, timezone, timedelta

from db.database import get_db
from db.models import Event, EventRegistration, User, EventResult, KartodromoResult, SignedRelease
from notifications.router import notify_user
from events.schemas import (
    EventCreate, EventUpdate, EventResponse,
    EventRegistrationResponse, EventRegistrationWithUserResponse,
    TeamRegistrationRequest, TeamRegistrationResponse, TeamMemberResponse,
    AdminIndividualRegistrationRequest, AdminTeamRegistrationRequest,
    AdminAssignTeamRequest, AdminCreateTeamFromIndividualsRequest,
    SignReleaseRequest, SignedReleaseResponse
)
from auth.dependencies import get_current_user
from auth.roles import Role, has_permission

def resolve_user_by_identifier(db: Session, identifier: str) -> Optional[User]:
    identifier = identifier.strip()
    if not identifier:
        return None
    if identifier.startswith("@"):
        username = identifier[1:]
        return db.query(User).filter(func.lower(User.username) == username.lower()).first()
    return db.query(User).filter(func.lower(User.email) == identifier.lower()).first()

def _populate_has_signed_release(regs, db: Session):
    for r in regs:
        if hasattr(r, 'user_id') and hasattr(r, 'event_id') and r.user_id and r.event_id:
            signed = db.query(SignedRelease).filter_by(event_id=r.event_id, user_id=r.user_id).first()
            r.has_signed_release = (signed is not None)
        else:
            r.has_signed_release = False

router = APIRouter(prefix="/events", tags=["events"])

@router.post("/", response_model=EventResponse, status_code=status.HTTP_201_CREATED)
def create_event(event: EventCreate, db: Session = Depends(get_db)):
    event_data = event.model_dump()

    # Se fornito days_before_deadline, calcola e salva anche registration_deadline
    days = event_data.get("days_before_deadline")
    if days is not None:
        event_data["registration_deadline"] = event_data["event_date"] - timedelta(days=days)

    db_event = Event(**event_data)
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
    _populate_has_signed_release(regs, db)
    return regs

@router.get("/registrations/user/{target_user_id}", response_model=List[EventRegistrationResponse])
def get_user_registrations_admin(
    target_user_id: int,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Restituisce tutte le iscrizioni di un utente specifico. Solo race_director e admin."""
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    regs = db.query(EventRegistration).filter(EventRegistration.user_id == target_user_id).all()
    _populate_has_signed_release(regs, db)
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

    # Se fornito days_before_deadline, calcola e aggiorna anche registration_deadline
    if "days_before_deadline" in update_data:
        days = update_data["days_before_deadline"]
        if days is not None:
            # Usa la nuova event_date se presente nel payload, altrimenti quella già nel DB
            base_date = update_data.get("event_date", db_event.event_date)
            update_data["registration_deadline"] = base_date - timedelta(days=days)
        else:
            # days_before_deadline azzerato esplicitamente: rimuove anche la deadline
            update_data["registration_deadline"] = None

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
    # Se la deadline è passata, l'iscrizione viene accettata ma forzata in lista d'attesa
    past_deadline = bool(event.registration_deadline and now > event.registration_deadline)

    # Determina se è una gara a squadre
    is_team_event = event.max_people_per_group is not None and event.max_people_per_group > 1
    creating_team = is_team_event and team_data and team_data.team_name.strip()

    if creating_team:
        # Gara a squadre: creazione team
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
        # Se la deadline è scaduta, va direttamente in waitlist ignorando la capienza
        if past_deadline:
            initial_status = "waitlist"
        else:
            initial_status = "pending_payment"
            if event.max_participants is not None:
                existing_teams = db.query(EventRegistration.team_id).filter(
                    EventRegistration.event_id == event_id,
                    EventRegistration.team_id.isnot(None),
                    EventRegistration.is_team_leader == True,
                    EventRegistration.status != "waitlist"
                ).distinct().count()
                if existing_teams >= event.max_participants:
                    initial_status = "waitlist"

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
            accepts_extra_pilots=team_data.accepts_extra_pilots,
            status=initial_status
        )
        db.add(leader_reg)
        
        # Registra gli altri membri (tramite email, user_id opzionale)
        for raw_email in team_data.member_emails:
            raw_email = raw_email.strip()
            if not raw_email:
                continue
            # Cerca se l'utente è nel sistema
            member_user = resolve_user_by_identifier(db, raw_email)
            member_user_id = member_user.id if member_user else None
            final_email = member_user.email if member_user else raw_email.lower()
            
            # Controlla se quell'utente (se registrato) è già iscritto
            if member_user_id:
                already = db.query(EventRegistration).filter(
                    EventRegistration.user_id == member_user_id,
                    EventRegistration.event_id == event_id
                ).first()
                if already:
                    raise HTTPException(
                        status_code=400,
                        detail=f"L'utente {final_email} è già iscritto all'evento"
                    )
            
            member_reg = EventRegistration(
                user_id=member_user_id,
                event_id=event_id,
                team_name=team_data.team_name.strip(),
                team_id=new_team_id,
                is_team_leader=False,
                member_email=final_email,
                accepts_extra_pilots=team_data.accepts_extra_pilots,
                status=initial_status
            )
            db.add(member_reg)
        
        db.commit()
        
        # Invia notifiche ai membri (dopo aver committato il team)
        for raw_email in team_data.member_emails:
            member_user = resolve_user_by_identifier(db, raw_email)
            if member_user:
                notify_user(db, member_user.id, event_id, "registration_updated", "Aggiunto alla squadra", f"Il caposquadra ti ha aggiunto alla squadra {team_data.team_name.strip()} per questo evento.")
        db.refresh(leader_reg)
        return leader_reg

    else:
        # Gara individuale o iscrizione "singola" per gara a squadre
        # Se la deadline è scaduta, va direttamente in waitlist ignorando la capienza
        if past_deadline:
            initial_status = "waitlist"
        elif is_team_event:
            # Iscrizione singola a una gara a squadre → waitlist di default
            initial_status = "waitlist"
        elif event.max_participants is not None:
            # Solo per gare individuali: controlla capienza
            count = db.query(EventRegistration).filter(
                EventRegistration.event_id == event_id,
                EventRegistration.status != "waitlist"
            ).count()
            initial_status = "waitlist" if count >= event.max_participants else "pending_payment"
        else:
            initial_status = "pending_payment"
                
        existing = db.query(EventRegistration).filter(
            EventRegistration.user_id == user_id,
            EventRegistration.event_id == event_id
        ).first()
        if existing:
            raise HTTPException(status_code=400, detail="Already registered")
            
        reg = EventRegistration(user_id=user_id, event_id=event_id, status=initial_status)
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


@router.delete("/{event_id}/registrations/me/leave", status_code=status.HTTP_204_NO_CONTENT)
def leave_team_as_member(
    event_id: int,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Permette a un membro NON-leader di abbandonare il proprio team.
    Rimuove solo la propria iscrizione; il resto del team rimane invariato.
    Funziona anche se lo status è 'confirmed'.
    """
    user_id = int(user_payload["sub"])

    reg = db.query(EventRegistration).filter(
        EventRegistration.user_id == user_id,
        EventRegistration.event_id == event_id,
        EventRegistration.is_team_leader == False
    ).first()

    if not reg:
        raise HTTPException(
            status_code=404,
            detail="Iscrizione non trovata o sei il capogruppo del team"
        )

    team_id = reg.team_id

    # Salva info utente prima di eliminare
    leaving_user = db.query(User).filter(User.id == user_id).first()
    leaving_name = (leaving_user.username or leaving_user.email) if leaving_user else "Un membro"

    db.delete(reg)
    db.commit()

    # Notifica il leader
    if team_id:
        leader = db.query(EventRegistration).filter(
            EventRegistration.team_id == team_id,
            EventRegistration.event_id == event_id,
            EventRegistration.is_team_leader == True
        ).first()
        if leader and leader.user_id:
            notify_user(
                db, leader.user_id, event_id,
                "registration_deleted",
                "Membro ha abbandonato il team",
                f"{leaving_name} ha rifiutato l'iscrizione e ha abbandonato la squadra."
            )

    return None




@router.get("/{event_id}/registrations/team/{team_id}", response_model=TeamRegistrationResponse)
def get_my_team_registration(
    event_id: int,
    team_id: str,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = int(user_payload["sub"])
    is_admin = has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR)
    
    # Verifica che l'utente faccia parte del team o sia admin
    my_reg = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id,
        EventRegistration.user_id == user_id
    ).first()
    
    if not my_reg and not is_admin:
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
        accepts_extra_pilots=leader.accepts_extra_pilots if leader else False
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
    is_admin = has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR)
    
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
        
    leader_reg = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id,
        EventRegistration.is_team_leader == True
    ).first()
    
    if not leader_reg:
        raise HTTPException(status_code=404, detail="Team non trovato")
        
    if leader_reg.user_id != user_id and not is_admin:
        raise HTTPException(status_code=403, detail="Solo il capogruppo o un admin può modificare il team")
        
    # Rimosso check se confermata: permettiamo modifiche anche da pagata
    expected_members = event.max_people_per_group - 1
    if len(team_data.member_emails) > expected_members:
        raise HTTPException(
            status_code=400,
            detail=f"Troppi membri: massimo {event.max_people_per_group} per squadra"
        )
        
    # Salva vecchi membri per notificarli
    old_members = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.is_team_leader == False
    ).all()
    old_emails = {m.member_email.lower(): m.user_id for m in old_members if m.member_email}

    # Elimina vecchi membri non leader
    for m in old_members:
        db.delete(m)
        
    # Fondamentale per evitare errori di UNIQUE constraint:
    # diciamo ad SQLAlchemy di eseguire le DELETE prima di accodare eventuali INSERT
    db.flush()
    
    # Aggiorna nome team e preferenze
    leader_reg.team_name = team_data.team_name.strip()
    leader_reg.accepts_extra_pilots = team_data.accepts_extra_pilots
    
    if is_admin and team_data.leader_email:
        raw_leader_email = team_data.leader_email.strip()
        new_leader_user = resolve_user_by_identifier(db, raw_leader_email)
        final_leader_email = new_leader_user.email if new_leader_user else raw_leader_email.lower()
        
        if final_leader_email != leader_reg.member_email:
            if new_leader_user:
                already = db.query(EventRegistration).filter(
                    EventRegistration.user_id == new_leader_user.id,
                    EventRegistration.event_id == event_id,
                    EventRegistration.team_id != team_id
                ).first()
                if already:
                    raise HTTPException(
                        status_code=400,
                        detail=f"L'utente {final_leader_email} è già in un altro team"
                    )
            leader_reg.user_id = new_leader_user.id if new_leader_user else None
            leader_reg.member_email = final_leader_email
    
    # Inserisci nuovi membri
    for raw_email in team_data.member_emails:
        raw_email = raw_email.strip()
        if not raw_email:
            continue
            
        member_user = resolve_user_by_identifier(db, raw_email)
        member_user_id = member_user.id if member_user else None
        final_email = member_user.email if member_user else raw_email.lower()
        
        if member_user_id:
            already = db.query(EventRegistration).filter(
                EventRegistration.user_id == member_user_id,
                EventRegistration.event_id == event_id,
                EventRegistration.team_id != team_id # Non è già in questo team (teoricamente impossibile qui perché l'abbiamo svuotato)
            ).first()
            if already:
                raise HTTPException(
                    status_code=400,
                    detail=f"L'utente {final_email} è già iscritto a questo evento in un'altra squadra"
                )
                
        member_reg = EventRegistration(
            user_id=member_user_id,
            event_id=event_id,
            team_name=team_data.team_name.strip(),
            team_id=team_id,
            is_team_leader=False,
            member_email=final_email,
            status=leader_reg.status
        )
        db.add(member_reg)

    db.commit()
    
    new_emails_set = set()
    for raw_email in team_data.member_emails:
        raw_email = raw_email.strip()
        if not raw_email: continue
        u = resolve_user_by_identifier(db, raw_email)
        new_emails_set.add(u.email if u else raw_email.lower())
    
    # Notifica membri aggiunti
    for email in new_emails_set:
        if email not in old_emails:
            added_user = db.query(User).filter(User.email == email).first()
            if added_user:
                if is_admin:
                    notify_user(db, added_user.id, event_id, "admin_registered", "Aggiunto alla squadra", "L'organizzatore ti ha aggiunto alla squadra per questo evento.")
                else:
                    notify_user(db, added_user.id, event_id, "registration_updated", "Aggiunto alla squadra", "Il caposquadra ti ha aggiunto alla squadra per questo evento.")
                
    # Notifica membri rimossi
    for email, old_user_id in old_emails.items():
        if email not in new_emails_set and old_user_id:
            if is_admin:
                notify_user(db, old_user_id, event_id, "registration_deleted", "Rimosso dalla squadra", "L'organizzatore ti ha rimosso dalla squadra per questo evento.")
            else:
                notify_user(db, old_user_id, event_id, "registration_deleted", "Rimosso dalla squadra", "Il caposquadra ti ha rimosso dalla squadra per questo evento.")

    if leader_reg.user_id:
        if is_admin:
            notify_user(db, leader_reg.user_id, event_id, "admin_registered", "Squadra modificata", "L'organizzatore ha modificato la tua squadra per questo evento.")
        # Se non è admin (quindi è il leader stesso a modificarsi il team), non gli mandiamo nessuna notifica.
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
            "accepts_extra_pilots": reg.accepts_extra_pilots,
            "created_at": reg.created_at,
            "username": user.username if user else None,
            "email": reg.member_email or (user.email if user else None),
            "profile_picture_url": user.profile_picture_url if user else None,
            "has_signed_release": db.query(SignedRelease).filter_by(event_id=reg.event_id, user_id=reg.user_id).first() is not None if reg.user_id else False
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
                has_signed_release=db.query(SignedRelease).filter_by(event_id=m.event_id, user_id=m.user_id).first() is not None if m.user_id else False,
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
            accepts_extra_pilots=leader.accepts_extra_pilots if leader else False
        ))
    
    return result


# ── Admin: conferma iscrizione ────────────────────────────────────────────────

@router.patch("/{event_id}/registrations/{registration_id}/confirm", response_model=EventRegistrationResponse)
def confirm_registration(event_id: int, registration_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    reg = db.query(EventRegistration).filter(
        EventRegistration.id == registration_id,
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
    
    if reg.user_id:
        notify_user(db, reg.user_id, event_id, "registration_confirmed", "Iscrizione confermata", "L'organizzatore ha confermato la tua iscrizione.")
    
    db.commit()
    db.refresh(reg)
    return reg

@router.patch("/{event_id}/registrations/{registration_id}/unconfirm", response_model=EventRegistrationResponse)
def unconfirm_registration(event_id: int, registration_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    reg = db.query(EventRegistration).filter(
        EventRegistration.id == registration_id,
        EventRegistration.event_id == event_id
    ).first()
    if not reg:
        raise HTTPException(status_code=404, detail="Registration not found")
        
    if reg.status != "confirmed":
        raise HTTPException(status_code=400, detail="Only confirmed registrations can be unconfirmed")
    
    if reg.team_id and reg.is_team_leader:
        db.query(EventRegistration).filter(
            EventRegistration.team_id == reg.team_id,
            EventRegistration.event_id == event_id
        ).update({"status": "pending_payment"})
    else:
        reg.status = "pending_payment"
    
    if reg.user_id:
        notify_user(db, reg.user_id, event_id, "registration_unconfirmed", "Iscrizione in attesa", "L'organizzatore ha riportato la tua iscrizione in attesa di conferma/pagamento.")
    
    db.commit()
    db.refresh(reg)
    return reg

# ── Admin: elimina iscrizione ─────────────────────────────────────────────────

@router.delete("/{event_id}/registrations/{registration_id}", status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_registration(event_id: int, registration_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    reg = db.query(EventRegistration).filter(
        EventRegistration.id == registration_id,
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
        if reg.user_id:
            notify_user(db, reg.user_id, event_id, "registration_deleted", "Iscrizione annullata", "L'organizzatore ha annullato la tua iscrizione.")
    
    db.commit()
    return None


# ── Admin: elimina registrazione per team_id ──────────────────────────────────

@router.delete("/{event_id}/registrations/team/{team_id}", status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_team_registration(event_id: int, team_id: str, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    
    team_regs = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id
    ).all()
    for r in team_regs:
        if r.user_id:
            notify_user(db, r.user_id, event_id, "registration_deleted", "Iscrizione annullata", "L'organizzatore ha rimosso la tua squadra dall'evento.")
            
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
    
    if updated:
        team_regs = db.query(EventRegistration).filter(
            EventRegistration.team_id == team_id,
            EventRegistration.event_id == event_id
        ).all()
        for r in team_regs:
            if r.user_id:
                notify_user(db, r.user_id, event_id, "registration_confirmed", "Squadra confermata", "L'organizzatore ha confermato l'iscrizione della tua squadra.")
    
    if not updated:
        raise HTTPException(status_code=404, detail="Team registration not found")
    
    db.commit()
    return {"detail": "Team confirmed"}

@router.patch("/{event_id}/registrations/team/{team_id}/unconfirm", status_code=status.HTTP_200_OK)
def admin_unconfirm_team_registration(event_id: int, team_id: str, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    
    updated = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id,
        EventRegistration.status == "confirmed"
    ).update({"status": "pending_payment"})
    
    if updated:
        team_regs = db.query(EventRegistration).filter(
            EventRegistration.team_id == team_id,
            EventRegistration.event_id == event_id
        ).all()
        for r in team_regs:
            if r.user_id:
                notify_user(db, r.user_id, event_id, "registration_unconfirmed", "Squadra da confermare", "L'organizzatore ha riportato la tua squadra in attesa di conferma/pagamento.")
    
    if not updated:
        raise HTTPException(status_code=404, detail="Team registration not found or not confirmed")
    
    db.commit()
    return {"detail": "Team unconfirmed"}


# ── Admin: accetta da lista d'attesa ──────────────────────────────────────────

@router.patch("/{event_id}/registrations/{registration_id}/accept_waitlist", response_model=EventRegistrationResponse)
def accept_waitlist_registration(event_id: int, registration_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    reg = db.query(EventRegistration).filter(
        EventRegistration.id == registration_id,
        EventRegistration.event_id == event_id
    ).first()
    if not reg:
        raise HTTPException(status_code=404, detail="Registration not found")
        
    if reg.status != "waitlist":
        raise HTTPException(status_code=400, detail="Registration is not in waitlist")
    
    if reg.team_id and reg.is_team_leader:
        db.query(EventRegistration).filter(
            EventRegistration.team_id == reg.team_id,
            EventRegistration.event_id == event_id
        ).update({"status": "pending_payment"})
    else:
        reg.status = "pending_payment"
    
    if reg.user_id:
        notify_user(db, reg.user_id, event_id, "registration_accepted", "Accettato dall'organizzatore", "L'organizzatore ti ha accettato dalla lista d'attesa!")
    
    db.commit()
    db.refresh(reg)
    return reg

@router.patch("/{event_id}/registrations/team/{team_id}/accept_waitlist", status_code=status.HTTP_200_OK)
def admin_accept_waitlist_team_registration(event_id: int, team_id: str, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    
    updated = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id,
        EventRegistration.status == "waitlist"
    ).update({"status": "pending_payment"})
    
    if updated:
        team_regs = db.query(EventRegistration).filter(
            EventRegistration.team_id == team_id,
            EventRegistration.event_id == event_id
        ).all()
        for r in team_regs:
            if r.user_id:
                notify_user(db, r.user_id, event_id, "registration_accepted", "Squadra accettata", "L'organizzatore ha accettato la tua squadra dalla lista d'attesa!")
    
    if not updated:
        raise HTTPException(status_code=404, detail="Team registration not found or not in waitlist")
    
    db.commit()
    return {"detail": "Team moved to pending_payment"}


# ── Admin: sposta in lista d'attesa ──────────────────────────────────────────

@router.patch("/{event_id}/registrations/{registration_id}/move_to_waitlist", response_model=EventRegistrationResponse)
def move_to_waitlist_registration(event_id: int, registration_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    reg = db.query(EventRegistration).filter(
        EventRegistration.id == registration_id,
        EventRegistration.event_id == event_id
    ).first()
    if not reg:
        raise HTTPException(status_code=404, detail="Registration not found")
        
    if reg.status != "pending_payment":
        raise HTTPException(status_code=400, detail="Only pending_payment registrations can be moved to waitlist")
    
    if reg.team_id and reg.is_team_leader:
        db.query(EventRegistration).filter(
            EventRegistration.team_id == reg.team_id,
            EventRegistration.event_id == event_id
        ).update({"status": "waitlist"})
    else:
        reg.status = "waitlist"
        
    if reg.user_id:
        notify_user(db, reg.user_id, event_id, "moved_to_waitlist", "Spostato in lista d'attesa", "L'organizzatore ti ha spostato in lista d'attesa per questo evento.")
    
    db.commit()
    db.refresh(reg)
    return reg

@router.patch("/{event_id}/registrations/team/{team_id}/move_to_waitlist", status_code=status.HTTP_200_OK)
def admin_move_to_waitlist_team_registration(event_id: int, team_id: str, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    
    updated = db.query(EventRegistration).filter(
        EventRegistration.team_id == team_id,
        EventRegistration.event_id == event_id,
        EventRegistration.status == "pending_payment"
    ).update({"status": "waitlist"})
    
    if updated:
        team_regs = db.query(EventRegistration).filter(
            EventRegistration.team_id == team_id,
            EventRegistration.event_id == event_id
        ).all()
        for r in team_regs:
            if r.user_id:
                notify_user(db, r.user_id, event_id, "moved_to_waitlist", "Squadra in lista d'attesa", "L'organizzatore ha spostato la tua squadra in lista d'attesa.")
    
    if not updated:
        raise HTTPException(status_code=404, detail="Team registration not found or not in pending_payment")
    
    db.commit()
    return {"detail": "Team moved to waitlist"}


# ── Admin: Iscrizione Manuale ────────────────────────────────────────────────

@router.post("/{event_id}/admin_register/individual", response_model=EventRegistrationResponse, status_code=status.HTTP_201_CREATED)
def admin_register_individual(
    event_id: int,
    req: AdminIndividualRegistrationRequest,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
        
    raw_email = req.email.strip()
    user = resolve_user_by_identifier(db, raw_email)
    final_email = user.email if user else raw_email.lower()
    
    if user:
        existing = db.query(EventRegistration).filter(
            EventRegistration.user_id == user.id,
            EventRegistration.event_id == event_id
        ).first()
        if existing:
            raise HTTPException(status_code=400, detail="L'utente è già iscritto a questo evento")
            
    reg = EventRegistration(
        user_id=user.id if user else None,
        event_id=event_id,
        status="pending_payment",
        member_email=final_email
    )
    db.add(reg)
    db.commit()
    if reg.user_id:
        notify_user(db, reg.user_id, event_id, "admin_registered", "Iscritto dall'organizzatore", "L'organizzatore ti ha aggiunto a questo evento.")
    db.refresh(reg)
    return reg

@router.post("/{event_id}/admin_register/team", response_model=EventRegistrationResponse, status_code=status.HTTP_201_CREATED)
def admin_register_team(
    event_id: int,
    req: AdminTeamRegistrationRequest,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
        
    new_team_id = str(uuid.uuid4())
    raw_leader = req.leader_email.strip()
    leader_user = resolve_user_by_identifier(db, raw_leader)
    final_leader_email = leader_user.email if leader_user else raw_leader.lower()
    
    if leader_user:
        existing = db.query(EventRegistration).filter(
            EventRegistration.user_id == leader_user.id,
            EventRegistration.event_id == event_id
        ).first()
        if existing:
            raise HTTPException(status_code=400, detail=f"Il caposquadra {final_leader_email} è già iscritto")
            
    leader_reg = EventRegistration(
        user_id=leader_user.id if leader_user else None,
        event_id=event_id,
        team_name=req.team_name.strip(),
        team_id=new_team_id,
        is_team_leader=True,
        member_email=final_leader_email,
        status="pending_payment"
    )
    db.add(leader_reg)
    
    for raw_email in req.member_emails:
        raw_email = raw_email.strip()
        if not raw_email: continue
        
        member_user = resolve_user_by_identifier(db, raw_email)
        final_email = member_user.email if member_user else raw_email.lower()
        
        if member_user:
            already = db.query(EventRegistration).filter(
                EventRegistration.user_id == member_user.id,
                EventRegistration.event_id == event_id
            ).first()
            if already:
                raise HTTPException(status_code=400, detail=f"Il membro {final_email} è già iscritto all'evento")
                
        member_reg = EventRegistration(
            user_id=member_user.id if member_user else None,
            event_id=event_id,
            team_name=req.team_name.strip(),
            team_id=new_team_id,
            is_team_leader=False,
            member_email=final_email,
            status="pending_payment"
        )
        db.add(member_reg)
        
    db.commit()
    if leader_reg.user_id:
        notify_user(db, leader_reg.user_id, event_id, "admin_registered", "Squadra iscritta dall'organizzatore", "L'organizzatore ha iscritto la tua squadra a questo evento.")
    db.refresh(leader_reg)
    return leader_reg

@router.get("/{event_id}/admin_register/unassigned", response_model=List[EventRegistrationWithUserResponse])
def get_unassigned_individuals(event_id: int, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    regs = db.query(EventRegistration).filter(
        EventRegistration.event_id == event_id,
        EventRegistration.team_id == None
    ).all()
    
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
            "accepts_extra_pilots": reg.accepts_extra_pilots,
            "created_at": reg.created_at,
            "username": user.username if user else None,
            "email": reg.member_email or (user.email if user else None),
            "profile_picture_url": user.profile_picture_url if user else None,
            "has_signed_release": db.query(SignedRelease).filter_by(event_id=reg.event_id, user_id=reg.user_id).first() is not None if reg.user_id else False
        })
    return result

@router.post("/{event_id}/admin_register/teams/{team_id}/assign", response_model=List[EventRegistrationResponse])
def assign_to_team(event_id: int, team_id: str, req: AdminAssignTeamRequest, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    team_regs = db.query(EventRegistration).filter(
        EventRegistration.event_id == event_id,
        EventRegistration.team_id == team_id
    ).all()
    
    if not team_regs:
        raise HTTPException(status_code=404, detail="Team not found")
        
    leader = next((r for r in team_regs if r.is_team_leader), team_regs[0])
    
    regs_to_update = db.query(EventRegistration).filter(
        EventRegistration.id.in_(req.registration_ids),
        EventRegistration.event_id == event_id,
        EventRegistration.team_id == None
    ).all()
    
    for r in regs_to_update:
        r.team_id = team_id
        r.team_name = leader.team_name
        r.accepts_extra_pilots = leader.accepts_extra_pilots
        r.is_team_leader = False
        r.status = leader.status
        
    db.commit()
    for r in regs_to_update:
        if r.user_id:
            notify_user(db, r.user_id, event_id, "team_member_added", "Aggiunto a una squadra", f"L'organizzatore ti ha inserito nella squadra {leader.team_name}.")
    for r in regs_to_update:
        db.refresh(r)
        
    return regs_to_update

@router.post("/{event_id}/admin_register/teams/create_from_individuals", response_model=List[EventRegistrationResponse])
def create_team_from_individuals(event_id: int, req: AdminCreateTeamFromIndividualsRequest, user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Insufficient permissions")
        
    all_ids = [req.leader_registration_id] + req.member_registration_ids
    
    regs = db.query(EventRegistration).filter(
        EventRegistration.id.in_(all_ids),
        EventRegistration.event_id == event_id,
        EventRegistration.team_id == None
    ).all()
    
    if len(regs) != len(all_ids):
        raise HTTPException(status_code=400, detail="Some registrations were not found or are already in a team")
        
    new_team_id = str(uuid.uuid4())
    
    for r in regs:
        r.team_id = new_team_id
        r.team_name = req.team_name.strip()
        r.accepts_extra_pilots = req.accepts_extra_pilots
        r.is_team_leader = (r.id == req.leader_registration_id)
        if r.status == "waitlist":
            r.status = "pending_payment"
        
    db.commit()
    for r in regs:
        if r.user_id:
            notify_user(db, r.user_id, event_id, "team_created", "Squadra creata", f"L'organizzatore ti ha inserito nella nuova squadra {req.team_name.strip()}.")
    for r in regs:
        db.refresh(r)
        
    return regs


# ── Utente: firma liberatoria ────────────────────────────────────────────────

@router.post("/{event_id}/release-form/sign", status_code=status.HTTP_200_OK)
def sign_release_form(
    event_id: int,
    req: SignReleaseRequest,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = user_payload.get("sub")
    
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Evento non trovato")
        
    if not event.release_form_text:
        raise HTTPException(status_code=400, detail="Questo evento non prevede una liberatoria")
        
    is_registered = db.query(EventRegistration).filter(
        EventRegistration.event_id == event_id,
        EventRegistration.user_id == user_id
    ).first()
    
    if not is_registered:
        raise HTTPException(status_code=403, detail="Devi essere iscritto all'evento per firmare la liberatoria")
        
    existing_release = db.query(SignedRelease).filter(
        SignedRelease.event_id == event_id,
        SignedRelease.user_id == user_id
    ).first()
    
    if existing_release:
        existing_release.signature_base64 = req.signature_base64
        existing_release.first_name = req.first_name
        existing_release.last_name = req.last_name
        existing_release.codice_fiscale = req.codice_fiscale
        existing_release.birth_date = req.birth_date
        existing_release.residence = req.residence
        existing_release.signed_at = datetime.now(timezone.utc).replace(tzinfo=None)
    else:
        new_release = SignedRelease(
            event_id=event_id,
            user_id=user_id,
            signature_base64=req.signature_base64,
            first_name=req.first_name,
            last_name=req.last_name,
            codice_fiscale=req.codice_fiscale,
            birth_date=req.birth_date,
            residence=req.residence
        )
        db.add(new_release)
        
    db.commit()
    return {"status": "ok"}

@router.get("/{event_id}/release-form/mine", response_model=SignedReleaseResponse)
def get_my_release_form(
    event_id: int,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    user_id = int(user_payload["sub"])
    release = db.query(SignedRelease).filter(
        SignedRelease.event_id == event_id,
        SignedRelease.user_id == user_id
    ).first()
    
    if not release:
        raise HTTPException(status_code=404, detail="Liberatoria non trovata")
        
    return release

