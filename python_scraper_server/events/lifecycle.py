"""Chiude gli eventi 48 ore dopo la data e ora programmate."""
import asyncio
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import text

from db.database import SessionLocal
from db.models import Event
from ws.manager import broadcast_to_event

EVENT_EXPIRATION_DELAY = timedelta(days=2)
logger = logging.getLogger(__name__)


def finish_past_events(*, now=None):
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    # Le date nel DB sono UTC senza tzinfo, come quelle inviate dal client.
    cutoff = now.astimezone(timezone.utc).replace(tzinfo=None) - EVENT_EXPIRATION_DELAY
    with SessionLocal() as db:
        # Serializza lettura e modifica rispetto ad altri writer SQLite.
        db.execute(text("BEGIN IMMEDIATE"))
        events = db.query(Event).filter(
            Event.status.in_(["scheduled", "started"]),
            Event.event_date <= cutoff,
        ).all()
        changed = [event.id for event in events]
        for event in events:
            event.status = "finished"
        db.commit()
    return changed


async def close_expired_events():
    changed = await asyncio.to_thread(finish_past_events)
    for event_id in changed:
        await broadcast_to_event(event_id, {"type": "event_update"})


async def monitor_event_expiration():
    while True:
        await asyncio.sleep(30)
        try:
            await close_expired_events()
        except Exception:
            logger.exception("Errore chiusura automatica eventi scaduti")
