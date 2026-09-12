import logging
from datetime import datetime, timezone
from typing import Dict, List, Optional

from sqlalchemy.orm import Session
from db.database import SessionLocal
from db.models import Event, Kartodromo, LapTime

logger = logging.getLogger(__name__)

def parse_lap_time_ms(raw_lap: str) -> Optional[int]:
    """Converts a string like '54.213' or '1:02.435' to milliseconds."""
    if not raw_lap or raw_lap.strip() == "":
        return None
    raw_lap = raw_lap.strip()
    try:
        if ":" in raw_lap:
            parts = raw_lap.split(":")
            if len(parts) == 2:
                mins = int(parts[0])
                sec_parts = parts[1].split(".")
                secs = int(sec_parts[0])
                ms = int(sec_parts[1]) if len(sec_parts) > 1 else 0
                # Normalizza ms (es. ".4" -> 400ms, ".43" -> 430ms)
                if len(sec_parts) > 1:
                    ms_str = sec_parts[1]
                    ms = int(ms_str.ljust(3, '0')[:3])
                return (mins * 60 + secs) * 1000 + ms
        elif "." in raw_lap:
            sec_parts = raw_lap.split(".")
            secs = int(sec_parts[0])
            ms = 0
            if len(sec_parts) > 1:
                ms_str = sec_parts[1]
                ms = int(ms_str.ljust(3, '0')[:3])
            return secs * 1000 + ms
        else:
            return int(raw_lap)
    except ValueError:
        return None
    return None

def process_payload_for_laps(url: str, payload: dict, previous_lap_counts: Dict[int, int]) -> Dict[int, int]:
    """
    Osserva il payload live, confronta con i lap count precedenti,
    e se i giri sono aumentati, salva il Last Lap nel database.
    Ritorna il dizionario aggiornato dei lap_counts.
    """
    rows = payload.get("rows", [])
    headers = payload.get("headers", [])
    if not rows or not headers:
        return previous_lap_counts
        
    try:
        kart_idx = headers.index("Kart")
        # Support various column names for laps and last lap
        laps_idx = next(i for i, h in enumerate(headers) if h.lower() in ("laps", "giri", "lap"))
        last_idx = next(i for i, h in enumerate(headers) if h.lower() in ("last", "last lap", "ultimo", "ultimo giro"))
    except (ValueError, StopIteration):
        return previous_lap_counts

    current_lap_counts = {}
    new_laps_to_save = []

    for row in rows:
        if len(row) <= max(kart_idx, laps_idx, last_idx):
            continue
            
        try:
            kart_number = int(row[kart_idx])
            laps_str = row[laps_idx]
            # Gestione casi in cui il numero di giri ha testo (es. "12 laps")
            laps = int(''.join(filter(str.isdigit, str(laps_str))))
        except ValueError:
            continue
            
        current_lap_counts[kart_number] = laps
        last_lap_str = row[last_idx]
        
        # Se il numero di giri è aumentato, estraiamo l'ultimo giro
        prev_laps = previous_lap_counts.get(kart_number, 0)
        if laps > prev_laps and laps > 0:
            lap_ms = parse_lap_time_ms(last_lap_str)
            if lap_ms:
                new_laps_to_save.append({
                    "kart_number": kart_number,
                    "lap_number": laps,
                    "lap_time_ms": lap_ms
                })

    if new_laps_to_save:
        with SessionLocal() as db:
            # Trova l'evento attivo per questo URL
            kartodromo = db.query(Kartodromo).filter(Kartodromo.url == url).first()
            if kartodromo:
                event = db.query(Event).filter(
                    Event.location == kartodromo.nome,
                    Event.status == "started",
                    Event.race_status == "running"
                ).first()
                
                if event:
                    now = datetime.now(timezone.utc).replace(tzinfo=None)
                    for lap_data in new_laps_to_save:
                        # Controllo se esiste già questo giro per sicurezza
                        exists = db.query(LapTime).filter(
                            LapTime.event_id == event.id,
                            LapTime.kart_number == lap_data["kart_number"],
                            LapTime.lap_number == lap_data["lap_number"]
                        ).first()
                        if not exists:
                            new_lap = LapTime(
                                event_id=event.id,
                                kart_number=lap_data["kart_number"],
                                lap_number=lap_data["lap_number"],
                                lap_time_ms=lap_data["lap_time_ms"],
                                created_at=now
                            )
                            db.add(new_lap)
                    db.commit()

    return current_lap_counts
