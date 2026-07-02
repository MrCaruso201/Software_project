"""
Provider simulatore locale.

Invece di scrapare una pagina web, legge i dati da un file JSON locale
(SIMULATOR_JSON_PATH in config.py). Utile per sviluppo e test senza
bisogno di una connessione a una piattaforma di timing reale.

Il file JSON deve contenere almeno le chiavi "headers" e "rows"
(stesso formato restituito dagli altri provider).
"""

import json

from config import SIMULATOR_JSON_PATH
from scraper.base import BaseScraper


class SimulatorScraper(BaseScraper):
    """
    Provider simulatore: legge i dati da un file JSON locale.
    Non richiede un browser né una connessione di rete.
    """

    def __init__(self):
        self._url: str = ""

    def setup(self, url: str) -> None:
        self._url = url
        print(f"🎮 Avvio simulatore locale da {SIMULATOR_JSON_PATH}")
        if not SIMULATOR_JSON_PATH.exists():
            print(f"⚠️ File simulatore non trovato a {SIMULATOR_JSON_PATH}")

    def scrape(self) -> dict:
        if not SIMULATOR_JSON_PATH.exists():
            print(f"⚠️ File simulatore non trovato a {SIMULATOR_JSON_PATH}")
            return {"headers": [], "rows": []}

        with open(SIMULATOR_JSON_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)

        # Il file può contenere il payload completo oppure solo headers/rows
        return {
            "headers": data.get("headers", []),
            "rows": data.get("rows", []),
        }

    def teardown(self) -> None:
        # Nessuna risorsa da liberare
        pass
