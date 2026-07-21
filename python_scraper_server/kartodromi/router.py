"""
Router FastAPI per i kartodromi.

Endpoints:
  GET    /kartodromi/        → lista kartodromi attivi (richiede ruolo viewer)
  GET    /kartodromi/tutti   → lista tutti i kartodromi inclusi inattivi (solo admin)
  POST   /kartodromi/        → crea nuovo kartodromo (solo admin)
  PATCH  /kartodromi/{id}    → modifica kartodromo (solo admin)
  DELETE /kartodromi/{id}    → elimina kartodromo (solo admin)
"""

import os
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.orm import Session

from auth.dependencies import require_role, get_current_user
from auth.roles import Role
from db.database import get_db
from db.models import Kartodromo, KartodromoResult
from kartodromi.schemas import KartodromoCreate, KartodromoUpdate, KartodromoResponse, KartodromoResultRequest, KartodromoResultResponse

router = APIRouter(prefix="/kartodromi", tags=["kartodromi"])


# ---------------------------------------------------------------------------
# Lettura (viewer e superiori)
# ---------------------------------------------------------------------------

@router.get("/", response_model=List[KartodromoResponse])
def get_kartodromi(
    db: Session = Depends(get_db),
    _user: dict = Depends(require_role(Role.VIEWER)),
):
    """Restituisce tutti i kartodromi con flag attivo=True."""
    return db.query(Kartodromo).filter(Kartodromo.attivo == True).order_by(Kartodromo.id).all()


@router.get("/tutti", response_model=List[KartodromoResponse])
def get_tutti_kartodromi(
    db: Session = Depends(get_db),
    _user: dict = Depends(require_role(Role.ADMIN)),
):
    """Restituisce tutti i kartodromi (inclusi quelli disabilitati). Solo admin."""
    return db.query(Kartodromo).order_by(Kartodromo.id).all()


@router.get("/{kartodromo_id}", response_model=KartodromoResponse)
def get_kartodromo(
    kartodromo_id: int,
    db: Session = Depends(get_db),
    _user: dict = Depends(require_role(Role.VIEWER)),
):
    """Restituisce un singolo kartodromo per ID."""
    k = db.query(Kartodromo).filter(Kartodromo.id == kartodromo_id).first()
    if not k:
        raise HTTPException(status_code=404, detail="Kartodromo non trovato")
    return k


# ---------------------------------------------------------------------------
# Scrittura (solo admin)
# ---------------------------------------------------------------------------

@router.post("/", response_model=KartodromoResponse, status_code=status.HTTP_201_CREATED)
def create_kartodromo(
    kartodromo: KartodromoCreate,
    db: Session = Depends(get_db),
    _user: dict = Depends(require_role(Role.ADMIN)),
):
    """Crea un nuovo kartodromo. Solo admin."""
    # Verifica URL duplicato
    existing = db.query(Kartodromo).filter(Kartodromo.url == kartodromo.url).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esiste già un kartodromo con questo URL",
        )
    db_k = Kartodromo(**kartodromo.model_dump())
    db.add(db_k)
    db.commit()
    db.refresh(db_k)
    return db_k


@router.patch("/{kartodromo_id}", response_model=KartodromoResponse)
def update_kartodromo(
    kartodromo_id: int,
    kartodromo_update: KartodromoUpdate,
    db: Session = Depends(get_db),
    _user: dict = Depends(require_role(Role.ADMIN)),
):
    """Aggiorna un kartodromo esistente. Solo admin."""
    db_k = db.query(Kartodromo).filter(Kartodromo.id == kartodromo_id).first()
    if not db_k:
        raise HTTPException(status_code=404, detail="Kartodromo non trovato")

    update_data = kartodromo_update.model_dump(exclude_unset=True)

    # Controlla unicità URL se viene cambiato
    if "url" in update_data:
        conflict = (
            db.query(Kartodromo)
            .filter(Kartodromo.url == update_data["url"], Kartodromo.id != kartodromo_id)
            .first()
        )
        if conflict:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Esiste già un kartodromo con questo URL",
            )

    for key, value in update_data.items():
        setattr(db_k, key, value)

    db.commit()
    db.refresh(db_k)
    return db_k


@router.delete("/{kartodromo_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_kartodromo(
    kartodromo_id: int,
    db: Session = Depends(get_db),
    _user: dict = Depends(require_role(Role.ADMIN)),
):
    """Elimina un kartodromo. Solo admin."""
    db_k = db.query(Kartodromo).filter(Kartodromo.id == kartodromo_id).first()
    if not db_k:
        raise HTTPException(status_code=404, detail="Kartodromo non trovato")

    db.delete(db_k)
    db.commit()
    return None


@router.post("/{kartodromo_id}/image", response_model=KartodromoResponse)
async def upload_circuit_image(
    kartodromo_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _user: dict = Depends(require_role(Role.ADMIN)),
):
    """Carica (o sostituisce) l'immagine del circuito per un kartodromo. Solo admin."""
    db_k = db.query(Kartodromo).filter(Kartodromo.id == kartodromo_id).first()
    if not db_k:
        raise HTTPException(status_code=404, detail="Kartodromo non trovato")

    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Il file deve essere un'immagine")

    ext = file.filename.split(".")[-1].lower() if file.filename and "." in file.filename else "png"
    filename = f"circuit_{kartodromo_id}.{ext}"

    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    images_dir = os.path.join(BASE_DIR, "data", "circuit_images")
    os.makedirs(images_dir, exist_ok=True)
    filepath = os.path.join(images_dir, filename)

    content = await file.read()
    with open(filepath, "wb") as f:
        f.write(content)

    db_k.image_url = f"/static/circuit_images/{filename}"
    db.commit()
    db.refresh(db_k)

    print(f"🖼️  Immagine circuito aggiornata: {db_k.nome} → {filename}")
    return db_k


# ---------------------------------------------------------------------------
# Risultati personali (self-declared su circuito)
# ---------------------------------------------------------------------------

@router.get("/results/me", response_model=List[KartodromoResultResponse])
def get_my_kartodromo_results(
    db: Session = Depends(get_db),
    user_payload: dict = Depends(get_current_user),
):
    """Restituisce tutti i tempi autodichiarati dell'utente corrente sui vari kartodromi."""
    user_id = int(user_payload["sub"])
    return db.query(KartodromoResult).filter(KartodromoResult.user_id == user_id).order_by(KartodromoResult.date.desc()).all()


@router.post("/{kartodromo_id}/results/me/best_lap", response_model=KartodromoResultResponse)
def self_declare_kartodromo_best_lap(
    kartodromo_id: int,
    req: KartodromoResultRequest,
    db: Session = Depends(get_db),
    user_payload: dict = Depends(get_current_user),
):
    """Crea o aggiorna il tempo autodichiarato dall'utente per un determinato kartodromo."""
    user_id = int(user_payload["sub"])
    
    k = db.query(Kartodromo).filter(Kartodromo.id == kartodromo_id).first()
    if not k:
        raise HTTPException(status_code=404, detail="Kartodromo non trovato")
        
    new_result = KartodromoResult(
        user_id=user_id,
        kartodromo_id=kartodromo_id,
        best_lap_ms=req.best_lap_ms,
        date=req.date
    )
    db.add(new_result)
    db.commit()
    db.refresh(new_result)
    return new_result
