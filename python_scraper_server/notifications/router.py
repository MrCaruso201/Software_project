from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime, timezone


from db.database import get_db
from db.models import Notification, Event
from auth.dependencies import get_current_user
from notifications.schemas import NotificationResponse

router = APIRouter(prefix="/notifications", tags=["Notifications"])

def _is_event_past(event_date_str: str) -> bool:
    try:
        # Pulisce la stringa per supportare il parsing nativo ISO (Z -> +00:00)
        safe_str = event_date_str.replace("Z", "+00:00")
        dt = datetime.fromisoformat(safe_str)
        # Se è naive, assumiamo UTC (o l'ora locale del server, ma l'app salva in ISO)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)
        # Elimina il giorno dopo l'evento
        return (now - dt).days >= 1
    except Exception:
        return False

@router.get("/me", response_model=List[NotificationResponse])
def get_my_notifications(
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """
    Ritorna le notifiche per l'utente loggato.
    Elimina automaticamente le notifiche per eventi che sono già passati (dal giorno dopo l'evento).
    """
    user_id = int(current_user["sub"])
    notifications = db.query(Notification).filter(Notification.user_id == user_id).all()
    
    valid_notifications = []
    to_delete = []

    for notif in notifications:
        # Se ha un event_id, controlla se l'evento è passato
        if notif.event_id:
            event = db.query(Event).filter(Event.id == notif.event_id).first()
            if event and event.event_date:
                if _is_event_past(event.event_date):
                    to_delete.append(notif)
                    continue
        valid_notifications.append(notif)

    if to_delete:
        for notif in to_delete:
            db.delete(notif)
        db.commit()

    return valid_notifications

@router.post("/{notification_id}/read")
def mark_notification_read(
    notification_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    user_id = int(current_user["sub"])
    notif = db.query(Notification).filter(
        Notification.id == notification_id,
        Notification.user_id == user_id
    ).first()
    if not notif:
        raise HTTPException(status_code=404, detail="Notifica non trovata")
    
    notif.is_read = True
    db.commit()
    return {"message": "Notifica letta"}

def notify_user(db: Session, user_id: int, event_id: int, notif_type: str, title: str, message: str):
    """
    Crea una nuova notifica per l'utente, mantenendo lo storico completo.
    """
    if not user_id:
        return
    
    new_notif = Notification(
        user_id=user_id,
        event_id=event_id,
        type=notif_type,
        title=title,
        message=message,
        is_read=False,
        created_at=datetime.now(timezone.utc).replace(tzinfo=None)
    )
    db.add(new_notif)
    db.commit()

@router.delete("/me", status_code=204)
def delete_all_notifications(user_payload: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    user_id = int(user_payload["sub"])
    db.query(Notification).filter(Notification.user_id == user_id).delete()
    db.commit()
    return None

@router.delete("/{notification_id}", status_code=204)
def delete_single_notification(
    notification_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    user_id = int(current_user["sub"])
    notif = db.query(Notification).filter(
        Notification.id == notification_id,
        Notification.user_id == user_id
    ).first()
    
    if not notif:
        raise HTTPException(status_code=404, detail="Notifica non trovata")
        
    db.delete(notif)
    db.commit()
    return None
