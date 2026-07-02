"""
Persistenza su disco dei dati di timing.

Responsabilità:
  - Calcolo del percorso del file JSON per un dato URL
  - Scrittura atomica (tramite file temporaneo + os.replace)
  - Hashing del payload per rilevare cambiamenti
  - Pulizia dei file all'avvio/shutdown del server
"""

import hashlib
import json
import os
import tempfile
from pathlib import Path

from config import DATA_DIR


# ---------------------------------------------------------------------------
# Hashing
# ---------------------------------------------------------------------------


def data_hash(data: dict) -> str:
    """Restituisce l'MD5 del payload serializzato, usato per rilevare cambiamenti."""
    return hashlib.md5(json.dumps(data, sort_keys=True).encode()).hexdigest()


# ---------------------------------------------------------------------------
# Percorsi
# ---------------------------------------------------------------------------


def json_path_for(url: str) -> Path:
    """Ogni URL ha il proprio file di persistenza, per non sovrascrivere dati di sessioni diverse."""
    h = hashlib.md5(url.encode()).hexdigest()[:10]
    return DATA_DIR / f"live_timing_{h}.json"


# ---------------------------------------------------------------------------
# Lettura / scrittura
# ---------------------------------------------------------------------------


def save_json(payload: dict, path: Path) -> None:
    """Scrittura atomica: scrive su un file temporaneo poi sostituisce atomicamente il target."""
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".json", dir=DATA_DIR)
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, str(path))
    except Exception:
        os.unlink(tmp_path)
        raise


# ---------------------------------------------------------------------------
# Pulizia
# ---------------------------------------------------------------------------


def clear_saved_timing_data() -> None:
    """
    Cancella tutti i file di live timing salvati.
    Chiamata allo startup e allo shutdown del server, così i dati temporanei
    non si accumulano tra un avvio e l'altro.
    """
    removed = 0
    for f in DATA_DIR.glob("live_timing_*.json"):
        try:
            f.unlink()
            removed += 1
        except Exception as e:
            print(f"⚠️ Impossibile rimuovere {f.name}: {e}")
    if removed:
        print(f"🧹 Rimossi {removed} file di live timing salvati.")
