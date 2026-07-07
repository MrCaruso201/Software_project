"""
Router FastAPI per i kartodromi.

Endpoints:
  GET    /kartodromi/        → lista kartodromi attivi (richiede ruolo viewer)
  GET    /kartodromi/tutti   → lista tutti i kartodromi inclusi inattivi (solo admin)
  POST   /kartodromi/        → crea nuovo kartodromo (solo admin)
  PATCH  /kartodromi/{id}    → modifica kartodromo (solo admin)
  DELETE /kartodromi/{id}    → elimina kartodromo (solo admin)
"""

from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from auth.dependencies import require_role
from auth.roles import Role
from db.database import get_db
from db.models import Kartodromo
from kartodromi.schemas import KartodromoCreate, KartodromoUpdate, KartodromoResponse

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
