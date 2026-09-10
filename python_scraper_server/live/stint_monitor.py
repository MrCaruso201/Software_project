"""Server-side stint penalties, independent of connected clients."""
import asyncio
import logging
from datetime import datetime, timezone

from sqlalchemy import text

from db.database import SessionLocal
from db.models import Event, LiveKartAssignment, RacePenalty
from ws.manager import broadcast_to_event

logger = logging.getLogger(__name__)


def assess_stint(db, event, assignment, now):
    """Insert one ordinary penalty per stint; deleting it does not rearm the stint."""
    limit = event.max_stint_duration
    if not limit or limit <= 0 or assignment.team_id == "unassigned" or assignment.stint_penalty_assessed:
        return False
    elapsed = assignment.stint_elapsed_seconds
    if not assignment.is_in_pit and assignment.stint_last_resume and event.race_status == "running":
        elapsed += max(0, (now - assignment.stint_last_resume).total_seconds())
    if elapsed <= limit * 60:
        return False
    # Claim and penalty belong to the same transaction, including across workers.
    claimed = db.query(LiveKartAssignment).filter(
        LiveKartAssignment.id == assignment.id,
        LiveKartAssignment.stint_penalty_assessed == False,
    ).update({LiveKartAssignment.stint_penalty_assessed: True}, synchronize_session="fetch")
    if not claimed:
        return False
    db.add(RacePenalty(
        event_id=event.id, kart_number=assignment.kart_number,
        penalty_type="stint_time", seconds=15,
        note=f"Automatica: superato il limite stint di {limit} minuti (+15s).",
    ))
    return True


def scan_stints():
    changed = set()
    with SessionLocal() as db:
        # Serialize with SQLite writers before reading timer state.
        db.execute(text("BEGIN IMMEDIATE"))
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        rows = db.query(LiveKartAssignment, Event).join(
            Event, Event.id == LiveKartAssignment.event_id
        ).filter(
            Event.race_status.in_(["running", "paused"]),
            Event.max_stint_duration > 0,
            LiveKartAssignment.stint_penalty_assessed == False,
        ).all()
        for assignment, event in rows:
            if assess_stint(db, event, assignment, now):
                changed.add(event.id)
        db.commit()
    return changed


def penalty_notification(event_id):
    return {"type": "event_update", "change": "penalties", "event_id": event_id,
            "karts_changed": True, "request_id": None}


async def monitor_stints():
    while True:
        try:
            changed = await asyncio.to_thread(scan_stints)
            for event_id in changed:
                await broadcast_to_event(event_id, penalty_notification(event_id))
        except Exception:
            logger.exception("Automatic stint penalty check failed")
        await asyncio.sleep(1)
