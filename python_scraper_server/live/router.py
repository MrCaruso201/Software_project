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
    LiveKartAssignment, RacePenalty, RaceMessage
)
from auth.dependencies import get_current_user
from auth.roles import Role, has_permission
from live.schemas import (
    KartAssignmentCreate, KartAssignmentResponse,
    PenaltyCreate, PenaltyResponse,
    MessageCreate, MessageResponse,
    MyKartResponse, EventStatusUpdate
)

router = APIRouter(tags=["live"])

VALID_STATUSES = {"scheduled", "started", "finished"}
VALID_PENALTY_TYPES = {"drive_through", "stop_go", "time_added", "generic"}
VALID_MESSAGE_TYPES = {"yellow_flag", "red_flag", "green_flag", "info", "custom"}


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
    """Lista di tutti i kart assegnati per l'evento, con penalità totali per kart."""
    _get_event_or_404(event_id, db)
    assignments = (
        db.query(LiveKartAssignment)
        .filter(LiveKartAssignment.event_id == event_id)
        .order_by(LiveKartAssignment.kart_number)
        .all()
    )
    penalty_map = _penalty_seconds_by_kart(event_id, db)
    result = []
    for a in assignments:
        r = KartAssignmentResponse.model_validate(a)
        r.total_penalty_seconds = penalty_map.get(a.kart_number, 0)
        result.append(r)
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
    """Assegna una penalità a un kart. Solo race_director/admin."""
    _require_director(user_payload)
    _get_event_or_404(event_id, db)

    if body.penalty_type not in VALID_PENALTY_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Tipo penalità non valido. Valori accettati: {VALID_PENALTY_TYPES}"
        )

    penalty = RacePenalty(
        event_id=event_id,
        kart_number=body.kart_number,
        penalty_type=body.penalty_type,
        seconds=body.seconds,
        note=body.note
    )
    db.add(penalty)
    db.commit()
    db.refresh(penalty)
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
    - numero kart assegnato
    - penalità ricevute
    - messaggi rivolti al kart o broadcast
    """
    user_id = int(user_payload["sub"])
    _get_event_or_404(event_id, db)

    # Trova l'iscrizione dell'utente per recuperare il team_id
    registration = db.query(EventRegistration).filter(
        EventRegistration.user_id == user_id,
        EventRegistration.event_id == event_id
    ).first()

    if not registration or not registration.team_id:
        # Utente non iscritto o non in un team: risponde con dati vuoti
        return MyKartResponse()

    team_id = registration.team_id

    # Trova il kart assegnato al team
    assignment = db.query(LiveKartAssignment).filter(
        LiveKartAssignment.event_id == event_id,
        LiveKartAssignment.team_id == team_id
    ).first()

    if not assignment:
        return MyKartResponse(
            team_id=team_id,
            team_name=registration.team_name
        )

    kart_number = assignment.kart_number

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
