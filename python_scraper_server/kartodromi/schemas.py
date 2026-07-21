"""
Schema Pydantic per i kartodromi.
"""

from datetime import datetime, date
from typing import Optional
from pydantic import BaseModel


class KartodromoBase(BaseModel):
    nome: str
    luogo: str = ""
    url: str
    sito_web: str = ""
    attivo: bool = True


class KartodromoCreate(KartodromoBase):
    pass


class KartodromoUpdate(BaseModel):
    nome: Optional[str] = None
    luogo: Optional[str] = None
    url: Optional[str] = None
    sito_web: Optional[str] = None
    attivo: Optional[bool] = None
    image_url: Optional[str] = None


class KartodromoResponse(KartodromoBase):
    id: int
    image_url: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class KartodromoResultRequest(BaseModel):
    best_lap_ms: int
    date: date


class KartodromoResultResponse(BaseModel):
    id: int
    user_id: int
    kartodromo_id: int
    best_lap_ms: int
    date: date
    created_at: datetime

    class Config:
        from_attributes = True

