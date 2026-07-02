"""
Classe base astratta per tutti i provider di scraping.

Ogni provider implementa tre metodi:
  - setup(url)  → apre il browser / prepara le risorse
  - scrape()    → esegue una singola lettura, restituisce {"headers": [...], "rows": [[...]]}
  - teardown()  → chiude il browser / libera le risorse

ScraperSession._loop() è completamente ignaro del provider: chiama
la factory per ottenere l'istanza giusta e poi itera su scrape().
"""

from abc import ABC, abstractmethod


class BaseScraper(ABC):
    """
    Interfaccia che ogni provider di live timing deve implementare.

    Il contratto di scrape() prevede che restituisca sempre un dizionario
    con almeno le chiavi:
      - "headers": list[str]   → intestazioni colonne
      - "rows":    list[list]  → righe dati (lista di liste di stringhe)

    In caso di errore non recuperabile, scrape() può lanciare un'eccezione:
    ScraperSession._loop() la cattura, logga e riprova al prossimo ciclo.
    """

    @abstractmethod
    def setup(self, url: str) -> None:
        """Prepara le risorse necessarie per lo scraping (es. apre il browser)."""

    @abstractmethod
    def scrape(self) -> dict:
        """
        Esegue una singola lettura della sorgente.

        Returns:
            dict con chiavi "headers" (list[str]) e "rows" (list[list[str]]).
        """

    @abstractmethod
    def teardown(self) -> None:
        """Libera le risorse acquisite in setup() (es. chiude il browser)."""
