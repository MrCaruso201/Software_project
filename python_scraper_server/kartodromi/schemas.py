"""
Schema Pydantic per i kartodromi.
"""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class KartodromoBase(BaseModel):
    nome: str
    luogo: str = ""
    url: str
    attivo: bool = True


class KartodromoCreate(KartodromoBase):
    pass


class KartodromoUpdate(BaseModel):
    nome: Optional[str] = None
    luogo: Optional[str] = None
    url: Optional[str] = None
    attivo: Optional[bool] = None


class KartodromoResponse(KartodromoBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True
