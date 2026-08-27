"""
Router FastAPI per i risultati gara.

Endpoints (prefisso vuoto — path completi per evitare ambiguità con events_router):

  GET    /events/results/me                      → tutta la history dell'utente corrente
  GET    /events/{id}/results                    → classifica ufficiale pubblicata
  GET    /events/{id}/results/me                 → mio risultato per quell'evento
  POST   /events/{id}/results/import_csv         → admin importa classifica da file CSV
  POST   /events/{id}/results/me/best_lap        → utente auto-dichiara miglior giro
  DELETE /events/{id}/results                    → admin cancella classifica pubblicata

Formato CSV gare individuali:
    position,email,best_lap_ms
    1,pilota@example.com,65234

Formato CSV gare a squadre:
    position,team_name,best_lap_ms
    1,Team Alpha,65234

La colonna best_lap_ms è opzionale.
"""

import csv
import io
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from auth.dependencies import get_current_user, require_role
from auth.roles import Role
from db.database import get_db
from db.models import Event, EventRegistration, EventResult, User
from results.schemas import CSVImportResponse, EventResultResponse, SelfDeclaredResultRequest

router = APIRouter(tags=["results"])


# ─────────────────────────────────────────────────────────────────────────────
# Helper

def _to_response(result: EventResult, db: Session) -> EventResultResponse:
    user = db.query(User).filter(User.id == result.user_id).first() if result.user_id else None
    return EventResultResponse(
        id=result.id,
        event_id=result.event_id,
        user_id=result.user_id,
        driver_name=result.driver_name,
        member_email=result.member_email,
        position=result.position,
        best_lap_ms=result.best_lap_ms,
        gap=result.gap,
        laps=result.laps,
        is_official=result.is_official,
        team_id=result.team_id,
        team_name=result.team_name,
        note=result.note,
        username=user.username if user else None,
        kart_number=result.kart_number,
        profile_picture_url=user.profile_picture_url if user else None,
        created_at=result.created_at,
    )


# ─────────────────────────────────────────────────────────────────────────────
# GET /events/results/me  — tutta la history dell'utente
# IMPORTANTE: deve essere registrata PRIMA di GET /events/{event_id}/... per
# evitare che FastAPI provi a parsare "results" come event_id (int).

@router.get("/events/results/me", response_model=List[EventResultResponse])
def get_all_my_results(
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Restituisce tutti i risultati (ufficiali e auto-dichiarati) dell'utente corrente."""
    user_id = int(user_payload["sub"])
    results = (
        db.query(EventResult)
        .filter(EventResult.user_id == user_id)
        .order_by(EventResult.event_id)
        .all()
    )
    return [_to_response(r, db) for r in results]


# ─────────────────────────────────────────────────────────────────────────────
# GET /events/results/user/{user_id}  — risultati di un utente specifico (solo admin)

@router.get("/events/results/user/{target_user_id}", response_model=List[EventResultResponse])
def get_user_results_admin(
    target_user_id: int,
    user_payload: dict = Depends(require_role(Role.RACE_DIRECTOR)),
    db: Session = Depends(get_db),
):
    """Restituisce tutti i risultati di un utente specifico. Solo race_director e admin."""
    results = (
        db.query(EventResult)
        .filter(EventResult.user_id == target_user_id)
        .order_by(EventResult.event_id)
        .all()
    )
    return [_to_response(r, db) for r in results]


# ─────────────────────────────────────────────────────────────────────────────
# GET /events/{event_id}/results  — classifica ufficiale

@router.get("/events/{event_id}/results", response_model=List[EventResultResponse])
def get_event_results(
    event_id: int,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Classifica ufficiale di un evento (is_official=True), ordinata per posizione."""
    results = (
        db.query(EventResult)
        .filter(EventResult.event_id == event_id, EventResult.is_official == True)
        .order_by(EventResult.position)
        .all()
    )
    return [_to_response(r, db) for r in results]


# ─────────────────────────────────────────────────────────────────────────────
# GET /events/{event_id}/results/me  — mio risultato per un evento

@router.get("/events/{event_id}/results/me", response_model=EventResultResponse)
def get_my_result_for_event(
    event_id: int,
    user_payload: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Restituisce il risultato dell'utente per un evento."""
    user_id = int(user_payload["sub"])

    result = db.query(EventResult).filter(
        EventResult.event_id == event_id,
        EventResult.user_id == user_id
    ).first()
    
    if result:
        return _to_response(result, db)

    raise HTTPException(status_code=404, detail="Nessun risultato trovato per questo evento")


# ─────────────────────────────────────────────────────────────────────────────
# POST /events/{event_id}/results/import_csv  — importazione classifica da CSV

@router.post("/events/{event_id}/results/import_csv", response_model=CSVImportResponse)
async def import_results_from_csv(
    event_id: int,
    file: UploadFile = File(...),
    user_payload: dict = Depends(require_role(Role.ADMIN)),
    db: Session = Depends(get_db),
):
    """
    Importa la classifica ufficiale da CSV. Solo admin.
    Sovrascrive tutti i risultati ufficiali precedenti per questo evento.

    Formato CSV gare individuali:
      Posizione, Kart, Pilota, Miglior Giro (opzionale), Gap (opzionale), Giri (opzionale), username (opzionale)

    Formato CSV gare a squadre:
      Posizione, Kart, Squadra, Miglior Giro (opzionale), Gap (opzionale), Giri (opzionale)

    La colonna "Kart" è molto consigliata. Il backend cercherà l'utente incrociando
    la tabella delle assegnazioni live (`LiveKartAssignment`). Se manca il "Kart",
    proverà a fare un match sul nome (il "Nome sul Monitor" che era stato assegnato).
    """
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Evento non trovato")

    is_team_event = (
        event.max_people_per_group is not None and event.max_people_per_group > 1
    )

    # Decode CSV (gestisce BOM da Excel)
    content = await file.read()
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = content.decode("latin-1")

    reader = csv.DictReader(io.StringIO(text))
    if reader.fieldnames is None:
        raise HTTPException(status_code=400, detail="CSV vuoto o privo di intestazione")

    # Cancella risultati ufficiali precedenti per questo evento
    db.query(EventResult).filter(
        EventResult.event_id == event_id,
        EventResult.is_official == True,
    ).delete()

    imported = 0
    errors: list[str] = []

    from db.models import LiveKartAssignment
    
    # Pre-carica tutte le registrazioni per velocizzare
    all_regs = db.query(EventRegistration).filter(EventRegistration.event_id == event_id).all()
    
    for i, row in enumerate(reader, start=2):
        # Normalizza chiavi (case insensitive + strip); salta righe completamente vuote
        row = {k.strip().lower(): (v.strip() if v is not None else "") for k, v in row.items() if k}
        if not any(row.values()):
            continue  # riga vuota (es. riga finale del CSV)

        # Posizione
        raw_pos = row.get("posizione", row.get("position", ""))
        try:
            position = int(raw_pos)
        except ValueError:
            errors.append(f"Riga {i}: posizione '{raw_pos}' non valida — riga saltata")
            continue

        # Kart, Pilota e Squadra
        raw_kart = row.get("kart", row.get("numero", row.get("num", ""))).strip()
        kart_number = None
        if raw_kart:
            try: kart_number = int(raw_kart)
            except ValueError: pass

        driver_name = row.get("pilota", row.get("driver", row.get("email", ""))).strip() or None
        team_name = row.get("squadra", row.get("team", row.get("team_name", ""))).strip() or None
        monitor_name = team_name if is_team_event else driver_name

        # Miglior giro (opzionale)
        best_lap_ms: Optional[int] = None
        raw_lap = row.get("miglior giro", row.get("best lap", row.get("best_lap_ms", ""))).strip()
        if raw_lap:
            if ":" in raw_lap or "." in raw_lap:
                try:
                    parts = raw_lap.split(":")
                    if len(parts) == 2:
                        mins = int(parts[0])
                        sec_parts = parts[1].split(".")
                        secs = int(sec_parts[0])
                        ms = int(sec_parts[1]) if len(sec_parts) > 1 else 0
                        best_lap_ms = (mins * 60 + secs) * 1000 + ms
                    else:
                        best_lap_ms = int(float(raw_lap) * 1000)
                except ValueError:
                    errors.append(f"Riga {i}: miglior giro '{raw_lap}' non valido — ignorato")
            else:
                try:
                    best_lap_ms = int(raw_lap)
                except ValueError:
                    errors.append(f"Riga {i}: miglior giro '{raw_lap}' non valido — ignorato")

        # Gap e Giri
        gap = row.get("gap", "").strip() or None
        raw_giri = row.get("giri", row.get("laps", "")).strip()
        laps = None
        if raw_giri:
            try:
                laps = int(raw_giri)
            except ValueError:
                pass

        # Identificazione Utente / Registrazione tramite LiveKartAssignment
        user_id = None
        member_email = None
        matched_team_id = None
        
        # 1. Username esplicito (override manuale)
        username_col = row.get("username", "").strip()
        if username_col:
            u = db.query(User).filter(User.username == username_col).first()
            if u:
                user_id = u.id
                member_email = u.email

        # 2. Ricerca automatica tramite Kart o Nome Monitor
        if not user_id:
            assignment = None
            if kart_number is not None:
                assignment = db.query(LiveKartAssignment).filter(
                    LiveKartAssignment.event_id == event_id,
                    LiveKartAssignment.kart_number == kart_number
                ).first()
            
            if not assignment and monitor_name:
                # Fallback: ricerca case-insensitive per team_name (Nome Monitor)
                from sqlalchemy import func
                assignment = db.query(LiveKartAssignment).filter(
                    LiveKartAssignment.event_id == event_id,
                    func.lower(LiveKartAssignment.team_name) == monitor_name.lower()
                ).first()

            if assignment:
                # Trovata assegnazione! Il team_id in LiveKartAssignment è l'ID del team o l'ID della reg (come stringa)
                t_id_str = assignment.team_id
                
                if is_team_event:
                    # In eventi a squadre, cerchiamo tutte le reg con questo team_id
                    team_regs = [r for r in all_regs if r.team_id == t_id_str]
                    if team_regs:
                        matched_team_id = t_id_str
                        # Assegna al leader se c'è, altrimenti al primo utente valido
                        leader_reg = next(
                            (r for r in team_regs if r.is_team_leader and r.user_id),
                            next((r for r in team_regs if r.user_id), None)
                        )
                        if leader_reg:
                            user_id = leader_reg.user_id
                            member_email = leader_reg.member_email
                else:
                    # In eventi individuali, team_id è la stringa dell'ID registrazione
                    try:
                        reg_id = int(t_id_str)
                        reg = next((r for r in all_regs if r.id == reg_id), None)
                        if reg and reg.user_id:
                            user_id = reg.user_id
                            member_email = reg.member_email
                    except ValueError:
                        pass
        
        # Se non è stato trovato nulla tramite i kart, tentiamo l'ultimo disperato fallback
        # sul nome squadra direttamente nelle registrazioni (come faceva prima)
        if not user_id and is_team_event and team_name:
            team_regs = [r for r in all_regs if r.team_name and r.team_name.lower() == team_name.lower()]
            if team_regs:
                matched_team_id = team_regs[0].team_id
                leader_reg = next(
                    (r for r in team_regs if r.is_team_leader and r.user_id),
                    next((r for r in team_regs if r.user_id), None)
                )
                if leader_reg:
                    user_id = leader_reg.user_id
                    member_email = leader_reg.member_email

        # Salvataggio risultato
        if is_team_event and not team_name and not monitor_name:
            errors.append(f"Riga {i}: squadra mancante in gara a squadre — riga saltata")
            continue
            
        if not user_id:
            errors.append(f"Riga {i}: '{monitor_name or 'Kart ' + str(kart_number)}' non ha trovato associazioni valide (salvato senza account)")

        db.add(EventResult(
            event_id=event_id,
            user_id=user_id,
            driver_name=driver_name,
            member_email=member_email,
            position=position,
            best_lap_ms=best_lap_ms,
            gap=gap,
            laps=laps,
            is_official=True,
            team_id=matched_team_id,
            team_name=team_name,
            kart_number=kart_number,
        ))
        imported += 1

    db.commit()
    print(f"📊  Classifica importata per evento {event_id}: {imported} risultati, {len(errors)} errori")
    return CSVImportResponse(imported=imported, errors=errors)



# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# DELETE /events/{event_id}/results  — cancella classifica pubblicata

@router.delete("/events/{event_id}/results", status_code=status.HTTP_204_NO_CONTENT)
def delete_event_results(
    event_id: int,
    user_payload: dict = Depends(require_role(Role.ADMIN)),
    db: Session = Depends(get_db),
):
    """Cancella tutti i risultati ufficiali di un evento. Solo admin."""
    db.query(EventResult).filter(
        EventResult.event_id == event_id,
        EventResult.is_official == True,
    ).delete()
    db.commit()
    return None
