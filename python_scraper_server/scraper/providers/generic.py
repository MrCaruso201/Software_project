"""
Provider generico — fallback per host sconosciuti ma consentiti.

Usa lo stesso estrattore JS di RaceFacer (cerca la tabella HTML più grande
nella pagina), il che funziona bene per qualunque piattaforma di timing
che pubblica i dati in una tabella HTML standard.

Quando un nuovo provider viene aggiunto a ALLOWED_URL_HOSTS ma non ha
ancora uno scraper dedicato, questo provider viene selezionato
automaticamente dalla factory come fallback.

Per aggiungere un provider dedicato:
  1. Crea un nuovo file in scraper/providers/
  2. Implementa BaseScraper
  3. Registra la classe in scraper/factory.py → SCRAPER_REGISTRY
"""

from scraper.providers.racefacer import RaceFacerScraper


class GenericScraper(RaceFacerScraper):
    """
    Scraper generico basato sull'estrattore JS tabellare di RaceFacer.
    Usato come fallback per provider non ancora mappati nel registry.
    """
    # Eredita tutto da RaceFacerScraper: stesso browser Playwright,
    # stesso JS_EXTRACT, stesso refresh periodico.
    # L'unica differenza è il nome della classe (visibile nei log).
