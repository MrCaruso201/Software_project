"""
Router FastAPI per il live timing (gare in corso).

Endpoints:

── Stato evento ─────────────────────────────────────────────────────
  PATCH  /events/{event_id}/status                    → aggiorna stato evento (scheduled/started/finished) e session_name;
                                                          se passa a "started" elimina le iscrizioni non confermate e notifica
                                                          gli iscritti confermati (richiede ruolo race_director o superiore)

── Kart Assignments ─────────────────────────────────────────────────
  GET    /live/{event_id}/karts                        → lista kart assegnati (manuali + match automatico da live timing),
                                                          con penalità totali per kart (utente autenticato)
  POST   /live/{event_id}/karts                        → assegna un numero kart a un team (race_director o superiore)
  DELETE /live/{event_id}/karts/{kart_number}           → rimuove assegnazione kart (race_director o superiore)

── Penalità ──────────────────────────────────────────────────────────
  GET    /live/penalty-types                            → lista tipi di penalità attivi configurati (utente autenticato)
  GET    /live/{event_id}/penalties                     → lista penalità evento, filtrabile per kart_number (utente autenticato)
  POST   /live/{event_id}/penalties                     → assegna penalità a un kart, con eventuale auto-penalità
                                                          se supera la soglia di warning (race_director o superiore)
  DELETE /live/{event_id}/penalties/{penalty_id}         → cancella una penalità (race_director o superiore)

── Messaggi live ─────────────────────────────────────────────────────
  GET    /live/{event_id}/messages                      → lista messaggi live, filtrabile per kart_number
                                                          (broadcast + messaggi per quel kart) (utente autenticato)
  POST   /live/{event_id}/messages                       → invia messaggio live (broadcast o per kart specifico)
                                                          (race_director o superiore)
  DELETE /live/{event_id}/messages/{message_id}          → cancella un messaggio live (race_director o superiore)

── Kart dell'utente ──────────────────────────────────────────────────
  GET    /live/{event_id}/my-kart                       → info sul kart del team dell'utente corrente: numero kart,
                                                          penalità ricevute, messaggi rivolti al kart o broadcast
                                                          (utente autenticato)
"""

from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks, Header
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import (
    Event, EventRegistration, SignedRelease,
    LiveKartAssignment, RacePenalty, RaceMessage, PenaltyType
)
from auth.dependencies import get_current_user
from auth.roles import Role, has_permission
from live.schemas import (
    KartAssignmentCreate, KartAssignmentResponse,
    PenaltyCreate, PenaltyResponse, PenaltyTypeResponse,
    MessageCreate, MessageResponse,
    MyKartResponse, EventStatusUpdate, KartPitUpdate
)
from live.stint_monitor import assess_stint, penalty_notification

import json
from datetime import datetime, timezone
from scraper.storage import json_path_for
from ws.manager import broadcast_to_event

router = APIRouter(tags=["live"])

VALID_STATUSES = {"scheduled", "started", "finished"}
VALID_MESSAGE_TYPES = {"yellow_flag", "red_flag", "green_flag", "checkered_flag", "info", "custom"}


# ─────────────────────────────────────────────────────────────────────────────
# Helper
# ─────────────────────────────────────────────────────────────────────────────

def _require_director(user_payload: dict):
    """Lancia 403 se l'utente non è almeno race_director."""
    if not has_permission(user_payload.get("role", ""), Role.RACE_DIRECTOR):
        raise HTTPException(status_code=403, detail="Permessi insufficienti")


def _get_event_or_404(event_id: int, db: Session) -> Event:
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Evento non trovato")
    return event


def _penalty_seconds_by_kart(event_id: int, db: Session) -> dict[int, int]:
    """Restituisce un dizionario {kart_number: total_penalty_seconds} per l'evento."""
    penalties = db.query(RacePenalty).filter(RacePenalty.event_id == event_id).all()
    totals: dict[int, int] = {}
    for p in penalties:
        totals[p.kart_number] = totals.get(p.kart_number, 0) + (p.seconds or 0)
    return totals

def _get_kartodromo_url(event: Event, db: Session) -> Optional[str]:
    from db.models import Kartodromo
    kartodromo = db.query(Kartodromo).filter(Kartodromo.nome == event.location).first()
    return kartodromo.url if kartodromo else None

def _read_live_timing(url: str) -> dict:
    if not url: return {}
    path = json_path_for(url)
    if not path.exists(): return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


# ─────────────────────────────────────────────────────────────────────────────
# Stato Evento
# ─────────────────────────────────────────────────────────────────────────────

@router.patch("/events/{event_id}/status", status_code=status.HTTP_200_OK)
def update_event_status(
    event_id: int,
    body: EventStatusUpdate,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Aggiorna lo stato di un evento.
    Accessibile a race_director e admin.
    """
    _require_director(user_payload)

    if body.status is not None and body.status not in VALID_STATUSES:
        raise HTTPException(
            status_code=400,
            detail=f"Status non valido. Valori accettati: {VALID_STATUSES}"
        )

    event = _get_event_or_404(event_id, db)
    
    if body.session_name is not None:
        event.session_name = body.session_name

    # Notify users if the event is starting OR re-starting (red flag resume)
    if body.status is not None and body.status == "started":
        from notifications.router import notify_user
        
        is_first_start = event.status != "started"
        
        if is_first_start:
            # 1. Rifiuta (elimina) tutte le iscrizioni non confermate
            unconfirmed_regs = db.query(EventRegistration).filter(
                EventRegistration.event_id == event_id,
                ~EventRegistration.status.in_(["confirmed"])
            ).all()
            
            for reg in unconfirmed_regs:
                if reg.user_id:
                    # 1.1 Elimina l'eventuale liberatoria associata a questa iscrizione rifiutata
                    db.query(SignedRelease).filter(
                        SignedRelease.event_id == event_id,
                        SignedRelease.user_id == reg.user_id
                    ).delete(synchronize_session=False)
                    
                    notify_user(
                        db=db,
                        user_id=reg.user_id,
                        event_id=event_id,
                        notif_type="registration_deleted",
                        title="Iscrizione annullata",
                        message="L'evento è iniziato e la tua iscrizione non è stata confermata in tempo."
                    )
                db.delete(reg)
                
            # 2. Notifica solo gli iscritti confermati
            confirmed_registrations = db.query(EventRegistration).filter(
                EventRegistration.event_id == event_id,
                EventRegistration.status == "confirmed",
                EventRegistration.user_id.isnot(None)
            ).all()
            
            for reg in confirmed_registrations:
                notify_user(
                    db=db,
                    user_id=reg.user_id,
                    event_id=event_id,
                    notif_type="event_started",
                    title="L'evento è iniziato!",
                    message=f"L'evento {event.title} è appena iniziato! Apri l'app per seguire il live timing."
                )
        
            # 3. Inizializza i timer stint senza avviarli
            registered_karts = db.query(LiveKartAssignment).filter(
                LiveKartAssignment.event_id == event_id,
                LiveKartAssignment.team_id != "unassigned"
            ).all()
            for k in registered_karts:
                k.is_in_pit = False
                k.stint_penalty_assessed = False
                k.stint_elapsed_seconds = 0
                k.stint_last_resume = None

    if body.status is not None:
        event.status = body.status
    db.commit()
    db.refresh(event)
    background_tasks.add_task(broadcast_to_event, event_id, {"type": "event_update"})
    return {"event_id": event_id, "status": event.status, "session_name": event.session_name}


# ─────────────────────────────────────────────────────────────────────────────
# Kart Assignments
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/live/{event_id}/karts", response_model=List[KartAssignmentResponse])
def get_kart_assignments(
    event_id: int,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Lista di tutti i kart assegnati per l'evento, con penalità totali per kart.
       Combina gli override manuali e i dati estrapolati automaticamente dal live timing."""
    event = _get_event_or_404(event_id, db)
    
    # 1. Assegnazioni manuali (override)
    manual_assignments = (
        db.query(LiveKartAssignment)
        .filter(LiveKartAssignment.event_id == event_id)
        .all()
    )
    manual_by_kart = {a.kart_number: a for a in manual_assignments}
    manual_team_ids = {a.team_id for a in manual_assignments if a.team_id}

    # 2. Team e piloti iscritti per match automatico
    from db.models import User
    registrations = db.query(EventRegistration, User).outerjoin(User, EventRegistration.user_id == User.id).filter(EventRegistration.event_id == event_id).all()
    
    team_name_map = {}
    for reg, user in registrations:
        t_name = (reg.team_name or "").strip().lower()
        team_ident = reg.team_id or str(reg.id)
        if t_name:
            team_name_map[t_name] = (team_ident, reg.team_name)
        if user:
            full_name = f"{user.first_name or ''} {user.last_name or ''}".strip().lower()
            if full_name:
                team_name_map[full_name] = (team_ident, f"{user.first_name or ''} {user.last_name or ''}".strip())
            if user.username:
                team_name_map[user.username.lower()] = (team_ident, user.username)

    # 3. Leggi il JSON del live timing
    url = _get_kartodromo_url(event, db)
    live_data = _read_live_timing(url) if url else {}
    rows = live_data.get("rows", [])
    headers = live_data.get("headers", [])
    
    try:
        kart_idx = headers.index("Kart")
        driver_idx = headers.index("Driver")
    except ValueError:
        kart_idx = -1
        driver_idx = -1

    penalty_map = _penalty_seconds_by_kart(event_id, db)
    result = []
    processed_karts = set()
    
    if kart_idx != -1 and driver_idx != -1:
        for row in rows:
            if len(row) <= max(kart_idx, driver_idx): continue
            try:
                kart_number = int(row[kart_idx])
            except ValueError:
                continue
                
            driver_name = row[driver_idx]
            processed_karts.add(kart_number)
            
            if kart_number in manual_by_kart:
                a = manual_by_kart[kart_number]
                r = KartAssignmentResponse.model_validate(a)
                r.total_penalty_seconds = penalty_map.get(a.kart_number, 0)
                result.append(r)
            else:
                d_name_lower = driver_name.strip().lower()
                matched_team_id = ""
                matched_team_name = driver_name
                if d_name_lower in team_name_map:
                    tid, tname = team_name_map[d_name_lower]
                    if tid not in manual_team_ids:
                        matched_team_id, matched_team_name = tid, tname
                
                r = KartAssignmentResponse(
                    id=0,
                    event_id=event_id,
                    team_id=matched_team_id,
                    kart_number=kart_number,
                    team_name=matched_team_name,
                    created_at=datetime.now(timezone.utc).replace(tzinfo=None)
                )
                r.total_penalty_seconds = penalty_map.get(kart_number, 0)
                result.append(r)

    # Aggiungi eventuali kart assegnati manualmente che non sono (più) nel JSON live
    for kart_num, a in manual_by_kart.items():
        if kart_num not in processed_karts:
            r = KartAssignmentResponse.model_validate(a)
            r.total_penalty_seconds = penalty_map.get(a.kart_number, 0)
            result.append(r)
            
    result.sort(key=lambda x: x.kart_number)
    return result


@router.post(
    "/live/{event_id}/karts",
    response_model=KartAssignmentResponse,
    status_code=status.HTTP_201_CREATED
)
def assign_kart(
    event_id: int,
    body: KartAssignmentCreate,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Assegna un numero kart a un team. Solo race_director/admin."""
    _require_director(user_payload)
    _get_event_or_404(event_id, db)

    # 1. Se il team ha già un kart assegnato, rimuoviamo l'assegnazione precedente
    existing_team = db.query(LiveKartAssignment).filter(
        LiveKartAssignment.event_id == event_id,
        LiveKartAssignment.team_id == body.team_id
    ).first()
    if existing_team:
        db.delete(existing_team)

    # 2. Se il kart richiesto è già assegnato a un altro team, blocca l'operazione
    existing_kart = db.query(LiveKartAssignment).filter(
        LiveKartAssignment.event_id == event_id,
        LiveKartAssignment.kart_number == body.kart_number
    ).first()
    if existing_kart and existing_kart.team_id != body.team_id:
        if existing_kart.team_id == "unassigned":
            # Consenti la sovrascrittura di un kart fittizio (placeholder per la telemetria)
            db.delete(existing_kart)
        else:
            raise HTTPException(
                status_code=409, 
                detail=f"Il kart {body.kart_number} è già assegnato al team {existing_kart.team_name or existing_kart.team_id}!"
            )

    db.flush()

    assignment = LiveKartAssignment(
        event_id=event_id,
        team_id=body.team_id,
        kart_number=body.kart_number,
        team_name=body.team_name,
        is_in_pit=False,
        stint_elapsed_seconds=0,
        stint_last_resume=datetime.now(timezone.utc).replace(tzinfo=None) if db.query(Event).filter(Event.id==event_id).first().race_status == "running" else None
    )
    db.add(assignment)
    db.commit()
    db.refresh(assignment)
    background_tasks.add_task(broadcast_to_event, event_id, {"type": "event_update"})
    r = KartAssignmentResponse.model_validate(assignment)
    r.total_penalty_seconds = 0
    return r


@router.delete("/live/{event_id}/karts/{kart_number}", status_code=status.HTTP_204_NO_CONTENT)
def remove_kart_assignment(
    event_id: int,
    kart_number: int,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Rimuovi l'assegnazione di un kart. Solo race_director/admin."""
    _require_director(user_payload)
    assignment = db.query(LiveKartAssignment).filter(
        LiveKartAssignment.event_id == event_id,
        LiveKartAssignment.kart_number == kart_number
    ).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Assegnazione non trovata")
    db.delete(assignment)
    db.commit()
    background_tasks.add_task(broadcast_to_event, event_id, {"type": "event_update"})
    return None


@router.patch("/live/{event_id}/karts/{kart_number}/pit", response_model=KartAssignmentResponse)
def update_kart_pit_status(
    event_id: int,
    kart_number: int,
    body: KartPitUpdate,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
    request_id: Optional[str] = Header(default=None, alias="X-Request-ID", max_length=128)
):
    """Aggiorna lo stato pit (in box o in pista) di un kart. Solo race_director/admin."""
    _require_director(user_payload)
    event = _get_event_or_404(event_id, db)
    
    assignment = db.query(LiveKartAssignment).filter(
        LiveKartAssignment.event_id == event_id,
        LiveKartAssignment.kart_number == kart_number
    ).first()
    
    if not assignment:
        raise HTTPException(status_code=404, detail="Assegnazione kart non trovata. Assegna prima il kart a un team.")
    
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    race_is_running = event.race_status == "running"
    
    # Check before freezing/resetting the timer so a sub-second monitor gap cannot hide an overrun.
    automatic_penalty = assess_stint(db, event, assignment, now)
    if body.is_in_pit and not assignment.is_in_pit:
        # Entra nei box: accumula secondi, ferma il timer
        if assignment.stint_last_resume and race_is_running:
            delta = int((now - assignment.stint_last_resume).total_seconds())
            assignment.stint_elapsed_seconds += max(0, delta)
        assignment.stint_last_resume = None
        assignment.is_in_pit = True
    elif not body.is_in_pit and assignment.is_in_pit:
        # Esce dai box: azzera stint e riavvia solo se la gara è in corso
        assignment.stint_penalty_assessed = False
        assignment.stint_elapsed_seconds = 0
        assignment.stint_last_resume = now if race_is_running else None
        assignment.is_in_pit = False
        
    db.commit()
    db.refresh(assignment)
    if automatic_penalty:
        background_tasks.add_task(broadcast_to_event, event_id, penalty_notification(event_id))
    
    background_tasks.add_task(broadcast_to_event, event_id, {
        "type": "event_update",
        "change": "pit",
        "event_id": event_id,
        "kart_number": kart_number,
        "request_id": request_id,
    })
    r = KartAssignmentResponse.model_validate(assignment)
    r.total_penalty_seconds = _penalty_seconds_by_kart(event_id, db).get(kart_number, 0)
    return r

# ─────────────────────────────────────────────────────────────────────────────
# Penalties
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/live/penalty-types", response_model=List[PenaltyTypeResponse])
def get_penalty_types(
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Lista dei tipi di penalità standard configurati nel database.
    """
    return db.query(PenaltyType).filter(PenaltyType.is_active == True).order_by(PenaltyType.sort_order).all()


@router.get("/live/{event_id}/penalties", response_model=List[PenaltyResponse])
def get_penalties(
    event_id: int,
    kart_number: Optional[int] = None,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Lista penalità per l'evento, opzionalmente filtrate per kart.
    Visibile a tutti gli utenti autenticati.
    """
    _get_event_or_404(event_id, db)
    q = db.query(RacePenalty).filter(RacePenalty.event_id == event_id)
    if kart_number is not None:
        q = q.filter(RacePenalty.kart_number == kart_number)
    return q.order_by(RacePenalty.created_at).all()


@router.post(
    "/live/{event_id}/penalties",
    response_model=PenaltyResponse,
    status_code=status.HTTP_201_CREATED
)
def add_penalty(
    event_id: int,
    body: PenaltyCreate,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
    request_id: Optional[str] = Header(default=None, alias="X-Request-ID", max_length=128)
):
    """Assegna una penalità a un kart (e triggera auto-penalità se si supera la soglia di warning). Solo race_director/admin."""
    _require_director(user_payload)
    _get_event_or_404(event_id, db)

    # Verifica validità tipo penalità dal DB
    p_type = db.query(PenaltyType).filter(PenaltyType.code == body.penalty_type, PenaltyType.is_active == True).first()
    if not p_type:
        raise HTTPException(
            status_code=400,
            detail=f"Tipo penalità non valido o inattivo: {body.penalty_type}"
        )

    # Applica i secondi di default se non specificati
    seconds = body.seconds if body.seconds is not None else p_type.default_seconds
    
    # Per i warning, forziamo seconds a None (o 0) per non alterare il total time
    if p_type.action == "warning":
        seconds = None

    penalty = RacePenalty(
        event_id=event_id,
        kart_number=body.kart_number,
        penalty_type=body.penalty_type,
        seconds=seconds,
        note=body.note
    )
    db.add(penalty)
    db.commit()
    db.refresh(penalty)
    
    # Auto-penalty logic (e.g. 3 track limits warnings -> 1 auto-penalty)
    if p_type.warning_threshold is not None and p_type.auto_penalty_code is not None:
        # Conta quanti warning di questo tipo ha il kart in questo evento (incluso quello appena inserito)
        count = db.query(RacePenalty).filter(
            RacePenalty.event_id == event_id,
            RacePenalty.kart_number == body.kart_number,
            RacePenalty.penalty_type == body.penalty_type
        ).count()
        
        # Ogni volta che count supera/raggiunge la soglia, assegna la penalità associata.
        # Es. se soglia=3, alla 3° -> penalità. Alla 4° -> penalità.
        if count >= p_type.warning_threshold:
            auto_p_type = db.query(PenaltyType).filter(PenaltyType.code == p_type.auto_penalty_code).first()
            if auto_p_type:
                auto_penalty = RacePenalty(
                    event_id=event_id,
                    kart_number=body.kart_number,
                    penalty_type=auto_p_type.code,
                    seconds=auto_p_type.default_seconds,
                    note=f"Assegnata automaticamente dopo {count} warning ({p_type.name})"
                )
                db.add(auto_penalty)
                db.commit()

    background_tasks.add_task(broadcast_to_event, event_id, {
        "type": "event_update", "change": "penalties", "event_id": event_id,
        "karts_changed": True,
        "request_id": request_id,
    })
    return penalty



@router.delete("/live/{event_id}/penalties/{penalty_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_penalty(
    event_id: int,
    penalty_id: int,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
    request_id: Optional[str] = Header(default=None, alias="X-Request-ID", max_length=128)
):
    """Cancella una penalità. Solo race_director/admin."""
    _require_director(user_payload)
    penalty = db.query(RacePenalty).filter(
        RacePenalty.id == penalty_id,
        RacePenalty.event_id == event_id
    ).first()
    if not penalty:
        raise HTTPException(status_code=404, detail="Penalità non trovata")
    db.delete(penalty)
    db.commit()
    background_tasks.add_task(broadcast_to_event, event_id, {
        "type": "event_update", "change": "penalties", "event_id": event_id,
        "karts_changed": True,
        "request_id": request_id,
    })
    return None


# ─────────────────────────────────────────────────────────────────────────────
# Messages
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/live/{event_id}/messages", response_model=List[MessageResponse])
def get_messages(
    event_id: int,
    kart_number: Optional[int] = None,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Lista messaggi live.
    Se kart_number è specificato, restituisce i messaggi per quel kart + broadcast.
    Se non specificato (race_director), restituisce tutti.
    """
    _get_event_or_404(event_id, db)
    q = db.query(RaceMessage).filter(RaceMessage.event_id == event_id)

    if kart_number is not None:
        # Filtra: broadcast (target_kart=None) oppure messaggi per questo kart
        from sqlalchemy import or_
        q = q.filter(
            or_(RaceMessage.target_kart == None, RaceMessage.target_kart == kart_number)  # noqa: E711
        )

    return q.order_by(RaceMessage.created_at).all()


@router.post(
    "/live/{event_id}/messages",
    response_model=MessageResponse,
    status_code=status.HTTP_201_CREATED
)
def send_message(
    event_id: int,
    body: MessageCreate,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
    request_id: Optional[str] = Header(default=None, alias="X-Request-ID", max_length=128)
):
    """Invia un messaggio live (broadcast o per kart specifico). Solo race_director/admin."""
    _require_director(user_payload)
    event = _get_event_or_404(event_id, db)

    if body.message_type not in VALID_MESSAGE_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Tipo messaggio non valido. Valori accettati: {VALID_MESSAGE_TYPES}"
        )

    message = RaceMessage(
        event_id=event_id,
        target_kart=body.target_kart,
        message_type=body.message_type,
        text=body.text
    )
    db.add(message)
    
    # Gestione timer stint e race_status in base al tipo di messaggio.
    # race_status è indipendente da event.status (che gestisce il ciclo di vita dell'evento).
    # Opera solo sui kart con assegnazione reale (non "unassigned")
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    karts = db.query(LiveKartAssignment).filter(
        LiveKartAssignment.event_id == event_id,
        LiveKartAssignment.team_id != "unassigned"
    ).all()
    
    text_lower = body.text.strip().lower()
    is_gara_iniziata = (
        body.message_type == "custom" and (text_lower == "gara iniziata" or text_lower == "turno iniziato")
    )
    
    automatic_penalty = False
    for kart in karts:
        automatic_penalty = assess_stint(db, event, kart, now) or automatic_penalty

    if body.message_type in ("red_flag", "checkered_flag"):
        # Ferma tutti i timer — stint_last_resume = None garantisce che il timer iOS si fermi
        for k in karts:
            if k.stint_last_resume:
                delta = int((now - k.stint_last_resume).total_seconds())
                k.stint_elapsed_seconds += max(0, delta)
            k.stint_last_resume = None
        # Aggiorna race_status senza toccare event.status
        event.race_status = "paused" if body.message_type == "red_flag" else "stopped"
    elif body.message_type == "green_flag":
        if event.race_status != "stopped":
            # Riprende i timer dal punto in cui erano (NO reset) solo se non è stopped
            for k in karts:
                if not k.is_in_pit and k.stint_last_resume is None:
                    k.stint_last_resume = now
            event.race_status = "running"
    elif is_gara_iniziata:
        # Porta TUTTI i kart in pista, azzera e avvia i timer da zero
        for k in karts:
            k.is_in_pit = False
            k.stint_penalty_assessed = False
            k.stint_elapsed_seconds = 0
            k.stint_last_resume = now
        event.race_status = "running"

    db.commit()
    db.refresh(message)
    if automatic_penalty:
        background_tasks.add_task(broadcast_to_event, event_id, penalty_notification(event_id))
    background_tasks.add_task(broadcast_to_event, event_id, {
        "type": "event_update", "change": "messages", "event_id": event_id,
        "karts_changed": body.message_type in ("red_flag", "green_flag", "checkered_flag") or is_gara_iniziata,
        "request_id": request_id,
    })
    return message


@router.delete("/live/{event_id}/messages/{message_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_message(
    event_id: int,
    message_id: int,
    background_tasks: BackgroundTasks,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
    request_id: Optional[str] = Header(default=None, alias="X-Request-ID", max_length=128)
):
    """Cancella un messaggio live. Solo race_director/admin."""
    _require_director(user_payload)
    msg = db.query(RaceMessage).filter(
        RaceMessage.id == message_id,
        RaceMessage.event_id == event_id
    ).first()
    if not msg:
        raise HTTPException(status_code=404, detail="Messaggio non trovato")
    db.delete(msg)
    db.commit()
    background_tasks.add_task(broadcast_to_event, event_id, {
        "type": "event_update", "change": "messages", "event_id": event_id,
        "karts_changed": False,
        "request_id": request_id,
    })
    return None


# ─────────────────────────────────────────────────────────────────────────────
# My Kart (User endpoint)
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/live/{event_id}/my-kart", response_model=MyKartResponse)
def get_my_kart(
    event_id: int,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Restituisce le informazioni sul kart del team dell'utente corrente per l'evento:
    - numero kart (scoperto da manual override o JSON live timing)
    - penalità ricevute
    - messaggi rivolti al kart o broadcast
    """
    user_id = int(user_payload["sub"])
    event = _get_event_or_404(event_id, db)

    # Trova l'iscrizione dell'utente per recuperare il team_id e i nomi per il match
    from db.models import User
    user = db.query(User).filter(User.id == user_id).first()
    registration = db.query(EventRegistration).filter(
        EventRegistration.user_id == user_id,
        EventRegistration.event_id == event_id
    ).first()

    if not registration:
        return MyKartResponse()
        
    team_id = registration.team_id or f"user_{user_id}"

    # 1. Prova a trovare un override manuale
    assignment = None
    if registration.team_id:
        assignment = db.query(LiveKartAssignment).filter(
            LiveKartAssignment.event_id == event_id,
            LiveKartAssignment.team_id == registration.team_id
        ).first()
    else:
        assignment = db.query(LiveKartAssignment).filter(
            LiveKartAssignment.event_id == event_id,
            LiveKartAssignment.team_id == str(registration.id)
        ).first()

    kart_number = None
    team_name = registration.team_name

    if assignment:
        kart_number = assignment.kart_number
        team_name = assignment.team_name or team_name
    else:
        # 2. Fallback al match automatico dal live timing
        url = _get_kartodromo_url(event, db)
        live_data = _read_live_timing(url) if url else {}
        rows = live_data.get("rows", [])
        headers = live_data.get("headers", [])
        
        try:
            kart_idx = headers.index("Kart")
            driver_idx = headers.index("Driver")
        except ValueError:
            kart_idx = -1
            driver_idx = -1
            
        if kart_idx != -1 and driver_idx != -1:
            match_names = set()
            if registration.team_name:
                match_names.add(registration.team_name.strip().lower())
            if user:
                full_name = f"{user.first_name or ''} {user.last_name or ''}".strip().lower()
                if full_name: match_names.add(full_name)
                if user.username: match_names.add(user.username.lower())
                
            for row in rows:
                if len(row) <= max(kart_idx, driver_idx): continue
                driver_name_lower = row[driver_idx].strip().lower()
                if driver_name_lower in match_names:
                    try:
                        kart_number = int(row[kart_idx])
                        team_name = row[driver_idx]
                        break
                    except ValueError:
                        pass

    # Recupera i membri del team (per eventi a squadre)
    from live.schemas import TeamMemberWeight
    team_members = []
    if registration.team_id:
        team_regs = db.query(EventRegistration).filter(
            EventRegistration.event_id == event_id,
            EventRegistration.team_id == registration.team_id
        ).order_by(EventRegistration.is_team_leader.desc()).all()
        for tr in team_regs:
            member_user = db.query(User).filter(User.id == tr.user_id).first() if tr.user_id else None
            username = member_user.username if member_user else (tr.member_email or "Membro")
            team_members.append(TeamMemberWeight(username=username, weight=tr.weight))

    if kart_number is None:
        return MyKartResponse(
            team_id=registration.team_id,
            team_name=registration.team_name,
            weight=registration.weight,
            team_members=team_members
        )

    # Penalità per questo kart
    penalties = (
        db.query(RacePenalty)
        .filter(RacePenalty.event_id == event_id, RacePenalty.kart_number == kart_number)
        .order_by(RacePenalty.created_at)
        .all()
    )
    total_seconds = sum(p.seconds or 0 for p in penalties)

    # Messaggi: broadcast + messaggi per questo kart
    from sqlalchemy import or_
    messages = (
        db.query(RaceMessage)
        .filter(
            RaceMessage.event_id == event_id,
            or_(RaceMessage.target_kart == None, RaceMessage.target_kart == kart_number)  # noqa: E711
        )
        .order_by(RaceMessage.created_at)
        .all()
    )

    return MyKartResponse(
        kart_number=kart_number,
        team_id=team_id,
        team_name=team_name,
        penalties=[PenaltyResponse.model_validate(p) for p in penalties],
        messages=[MessageResponse.model_validate(m) for m in messages],
        total_penalty_seconds=total_seconds,
        weight=registration.weight,
        team_members=team_members,
        is_in_pit=assignment.is_in_pit if assignment else False,
        stint_elapsed_seconds=assignment.stint_elapsed_seconds if assignment else 0,
        stint_last_resume=assignment.stint_last_resume if assignment else None
    )
