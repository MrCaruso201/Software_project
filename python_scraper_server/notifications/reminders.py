"""Promemoria persistenti: un solo invio per utente ed evento."""
import asyncio
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy.dialects.sqlite import insert

from db.database import SessionLocal
from db.models import Event, EventRegistration, EventReminderDelivery, Notification


def create_due_reminders(db, *, now=None, user_id=None, event_id=None):
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is not None:
        now = now.astimezone(timezone.utc).replace(tzinfo=None)
    db.flush()
    query = db.query(EventRegistration.user_id, Event).join(
        Event, Event.id == EventRegistration.event_id
    ).filter(
        EventRegistration.user_id.isnot(None),
        EventRegistration.status.in_(['confirmed', 'pending_payment']),
        Event.status == 'scheduled',
        Event.event_date > now,
        Event.event_date <= now + timedelta(days=7),
    )
    if user_id is not None:
        query = query.filter(EventRegistration.user_id == user_id)
    if event_id is not None:
        query = query.filter(Event.id == event_id)
    for recipient, event in query.all():
        claimed = db.execute(insert(EventReminderDelivery).values(
            user_id=recipient, event_id=event.id, sent_at=now
        ).on_conflict_do_nothing(index_elements=['user_id', 'event_id']))
        if claimed.rowcount != 1:
            continue
        db.add(Notification(
            user_id=recipient, event_id=event.id, type='upcoming_event',
            title='Evento imminente',
            message=f"{event.title} – L'evento si svolgerà nei prossimi 7 giorni.",
            is_read=False, created_at=now,
        ))


def deliver_due_reminders():
    with SessionLocal() as db:
        create_due_reminders(db)
        db.commit()


async def monitor_event_reminders():
    while True:
        try:
            await asyncio.to_thread(deliver_due_reminders)
        except Exception:
            logging.getLogger(__name__).exception('Errore invio promemoria eventi')
        await asyncio.sleep(30)
