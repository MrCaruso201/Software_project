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

    Gare individuali → colonne: position, email, best_lap_ms (opzionale)
    Gare a squadre   → colonne: position, team_name, best_lap_ms (opzionale)
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

    for i, row in enumerate(reader, start=2):
        # Normalizza chiavi (case insensitive + strip)
        row = {k.strip().lower(): v.strip() for k, v in row.items() if k}

        # Posizione
        raw_pos = row.get("posizione", row.get("position", ""))
        try:
            position = int(raw_pos)
        except ValueError:
            errors.append(f"Riga {i}: posizione '{raw_pos}' non valida — riga saltata")
            continue

        # Pilota e Squadra
        driver_name = row.get("pilota", row.get("driver", row.get("email", ""))).strip()
        team_name = row.get("squadra", row.get("team", row.get("team_name", ""))).strip()
        if not team_name and not is_team_event:
            team_name = None  # Gara individuale -> NULL nel campo squadra

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
        gap = row.get("gap", "").strip()
        raw_giri = row.get("giri", row.get("laps", "")).strip()
        laps = None
        if raw_giri:
            try:
                laps = int(raw_giri)
            except ValueError:
                pass

        user_id = None
        member_email = None
        matched_team_id = None

        if is_team_event:
            if team_name:
                team_regs = db.query(EventRegistration).filter(
                    EventRegistration.event_id == event_id,
                    EventRegistration.team_name == team_name,
                ).all()

                if team_regs:
                    matched_team_id = team_regs[0].team_id
                    # Gara a squadre: un risultato PER OGNI membro del team iscritto
                    for reg in team_regs:
                        db.add(EventResult(
                            event_id=event_id,
                            user_id=reg.user_id,
                            driver_name=driver_name,
                            member_email=reg.member_email,
                            position=position,
                            best_lap_ms=best_lap_ms,
                            gap=gap,
                            laps=laps,
                            is_official=True,
                            team_id=matched_team_id,
                            team_name=team_name,
                        ))
                        imported += 1
                    continue
                else:
                    errors.append(f"Riga {i}: squadra '{team_name}' non iscritta (salvato senza utenti associati)")
            else:
                errors.append(f"Riga {i}: squadra mancante in gara a squadre")
        else:
            # Gara individuale: match per nome pilota
            if driver_name:
                regs = db.query(EventRegistration).filter(EventRegistration.event_id == event_id).all()
                for reg in regs:
                    if reg.user_id:
                        u = db.query(User).filter(User.id == reg.user_id).first()
                        if u and f"{u.first_name} {u.last_name}".lower() == driver_name.lower():
                            user_id = u.id
                            member_email = u.email
                            break

        # Inserimento fallback se non è team event o se il team_name non è stato matchato
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
