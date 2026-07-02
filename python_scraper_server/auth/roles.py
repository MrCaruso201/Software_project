"""
Definizione dei ruoli e logica di autorizzazione.

La gerarchia è rappresentata come interi: ogni ruolo include i permessi
di quelli con valore inferiore, quindi has_permission() è un semplice
confronto numerico — non serve una lista di permessi esplicita.
"""

from enum import Enum


class Role(str, Enum):
    """Ruoli disponibili nel sistema. Compatibile Python 3.9+."""
    VIEWER        = "viewer"
    RACE_DIRECTOR = "race_director"
    ADMIN         = "admin"


# Gerarchia: valore più alto = più permessi
ROLE_HIERARCHY: dict[str, int] = {
    Role.VIEWER:        0,
    Role.RACE_DIRECTOR: 1,
    Role.ADMIN:         2,
}


def has_permission(user_role: str, required_role: str) -> bool:
    """True se user_role ha almeno i permessi di required_role."""
    return ROLE_HIERARCHY.get(user_role, -1) >= ROLE_HIERARCHY.get(required_role, 999)
