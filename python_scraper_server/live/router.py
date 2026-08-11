"""
Router Live Race Management

Gestisce la sessione di gara in tempo reale:
  - Cambio stato evento (scheduled → started → finished)
  - Assegnazione kart ai team
  - Penalità per kart
  - Messaggi live (broadcast o per kart specifico)
  - Endpoint utente per vedere i propri dati live

Permessi:
  - race_director / admin → possono scrivere (assegnare kart, penalità, messaggi, cambiare stato)
  - tutti gli utenti autenticati → possono leggere
"""

from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import (
    Event, EventRegistration,
    LiveKartAssignment, RacePenalty, RaceMessage, PenaltyType
)
from auth.dependencies import get_current_user
from auth.roles import Role, has_permission
from live.schemas import (
    KartAssignmentCreate, KartAssignmentResponse,
    PenaltyCreate, PenaltyResponse, PenaltyTypeResponse,
    MessageCreate, MessageResponse,
    MyKartResponse, EventStatusUpdate
)
import json
from datetime import datetime, timezone
from scraper.storage import json_path_for

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
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Aggiorna lo stato di un evento.
    Accessibile a race_director e admin.
    """
    _require_director(user_payload)

    if body.status not in VALID_STATUSES:
        raise HTTPException(
            status_code=400,
            detail=f"Status non valido. Valori accettati: {VALID_STATUSES}"
        )

    event = _get_event_or_404(event_id, db)
    event.status = body.status
    db.commit()
    db.refresh(event)
    return {"event_id": event_id, "status": event.status}


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

    # 2. Team e piloti iscritti per match automatico
    from db.models import User
    registrations = db.query(EventRegistration, User).outerjoin(User, EventRegistration.user_id == User.id).filter(EventRegistration.event_id == event_id).all()
    
    team_name_map = {}
    for reg, user in registrations:
        t_name = (reg.team_name or "").strip().lower()
        if t_name:
            team_name_map[t_name] = (reg.team_id, reg.team_name)
        if user:
            full_name = f"{user.first_name or ''} {user.last_name or ''}".strip().lower()
            if full_name:
                team_name_map[full_name] = (reg.team_id, f"{user.first_name or ''} {user.last_name or ''}".strip())
            if user.username:
                team_name_map[user.username.lower()] = (reg.team_id, user.username)

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
                    matched_team_id, matched_team_name = team_name_map[d_name_lower]
                
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
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Assegna un numero kart a un team. Solo race_director/admin."""
    _require_director(user_payload)
    _get_event_or_404(event_id, db)

    # Controlla conflitti: stesso kart già assegnato in questo evento
    existing_kart = db.query(LiveKartAssignment).filter(
        LiveKartAssignment.event_id == event_id,
        LiveKartAssignment.kart_number == body.kart_number
    ).first()
    if existing_kart:
        raise HTTPException(
            status_code=400,
            detail=f"Il kart {body.kart_number} è già assegnato alla squadra '{existing_kart.team_name or existing_kart.team_id}'"
        )

    # Controlla conflitti: stesso team già ha un kart
    existing_team = db.query(LiveKartAssignment).filter(
        LiveKartAssignment.event_id == event_id,
        LiveKartAssignment.team_id == body.team_id
    ).first()
    if existing_team:
        raise HTTPException(
            status_code=400,
            detail=f"Questa squadra ha già il kart {existing_team.kart_number} assegnato"
        )

    assignment = LiveKartAssignment(
        event_id=event_id,
        team_id=body.team_id,
        kart_number=body.kart_number,
        team_name=body.team_name
    )
    db.add(assignment)
    db.commit()
    db.refresh(assignment)
    r = KartAssignmentResponse.model_validate(assignment)
    r.total_penalty_seconds = 0
    return r


@router.delete("/live/{event_id}/karts/{kart_number}", status_code=status.HTTP_204_NO_CONTENT)
def remove_kart_assignment(
    event_id: int,
    kart_number: int,
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
    return None


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
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
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

    return penalty



@router.delete("/live/{event_id}/penalties/{penalty_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_penalty(
    event_id: int,
    penalty_id: int,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
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
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Invia un messaggio live (broadcast o per kart specifico). Solo race_director/admin."""
    _require_director(user_payload)
    _get_event_or_404(event_id, db)

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
    db.commit()
    db.refresh(message)
    return message


@router.delete("/live/{event_id}/messages/{message_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_message(
    event_id: int,
    message_id: int,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
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

    if kart_number is None:
        return MyKartResponse(
            team_id=registration.team_id,
            team_name=registration.team_name
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
        team_name=assignment.team_name or registration.team_name,
        penalties=[PenaltyResponse.model_validate(p) for p in penalties],
        messages=[MessageResponse.model_validate(m) for m in messages],
        total_penalty_seconds=total_seconds
    )
