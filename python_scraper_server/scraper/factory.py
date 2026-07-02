"""
Factory per la selezione del provider di scraping.

Flusso di selezione per un dato URL:
  1. Se l'URL è SIMULATOR_URL  → SimulatorScraper (legge file JSON locale)
  2. Se l'hostname è nel SCRAPER_REGISTRY → provider dedicato
  3. Altrimenti → GenericScraper (estrattore tabella HTML generico)

Per aggiungere il supporto a un nuovo provider:
  1. Crea il file scraper/providers/<nome>.py con la classe che implementa BaseScraper
  2. Aggiungi l'hostname a ALLOWED_URL_HOSTS in config.py (gate di sicurezza)
  3. Aggiungi la voce in SCRAPER_REGISTRY qui sotto
"""

from urllib.parse import urlparse

from config import SIMULATOR_URL
from scraper.base import BaseScraper
from scraper.providers.apex_timing import ApexTimingScraper
from scraper.providers.generic import GenericScraper
from scraper.providers.racefacer import RaceFacerScraper
from scraper.providers.simulator import SimulatorScraper

# ---------------------------------------------------------------------------
# Registro: hostname → classe scraper
# ---------------------------------------------------------------------------
# Aggiungere qui un nuovo provider dopo averlo implementato in providers/.

SCRAPER_REGISTRY: dict[str, type[BaseScraper]] = {
    "live.racefacer.com": RaceFacerScraper,
    "www.apex-timing.com": ApexTimingScraper,
    "apex-timing.com": ApexTimingScraper,
    # "timing.altro.com": AltroProviderScraper,
}


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------


def get_scraper_for_url(url: str) -> BaseScraper:
    """
    Restituisce un'istanza del provider più adatto per l'URL dato.

    Priorità:
      1. URL simulatore → SimulatorScraper
      2. Hostname nel registry → provider dedicato
      3. Fallback → GenericScraper
    """
    if url == SIMULATOR_URL:
        return SimulatorScraper()

    hostname = urlparse(url).hostname or ""
    scraper_cls = SCRAPER_REGISTRY.get(hostname, GenericScraper)
    return scraper_cls()
