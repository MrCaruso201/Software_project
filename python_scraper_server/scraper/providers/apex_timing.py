"""
Provider per apex-timing.com.

Apex Timing usa una struttura HTML ben definita con attributi data-*:
  - La riga intestazione ha class="head" e data-pos="0"
  - Le righe dati hanno data-pos="<posizione>" e NON hanno class "head"
  - Ogni cella ha data-type che identifica il tipo di dato:
      sta  → stato (spesso vuoto o icona)
      rk   → classifica
      no   → numero kart
      dr   → pilota
      tlp  → giri totali
      blp  → miglior giro
      llp  → ultimo giro
      gap  → distacco
      pena → penalità

Come RaceFacer, mantiene il browser aperto tra i poll e ricarica
periodicamente la pagina per garantire la freschezza dei dati.
"""

from playwright.sync_api import sync_playwright, Playwright, Browser, Page

from config import REFRESH_EVERY
from scraper.base import BaseScraper

# ---------------------------------------------------------------------------
# Estrattore JS specifico per Apex Timing
# ---------------------------------------------------------------------------

JS_EXTRACT_APEX = """
() => {
    // Mappa data-type → chiave standard
    const HEADER_MAP = {
        'rk':  'P',
        'no':  'Kart',
        'dr':  'Driver',
        'tlp': 'Laps',
        'blp': 'Best',
        'llp': 'Lap Time',
        'gap': 'Gap',
        'pena': '__pena__',
        // 'sta' non mappato: icone/stato non testuali, ignorato
    };

    // Ordine e nomi esatti delle colonne standard (compatibile con RaceFacer)
    const STANDARD_HEADERS = ['P', 'Kart', 'Driver', 'Lap Time', 'Gap', 'Int', 'Best', 'Laps', ''];

    const headerRow = document.querySelector('tr.head');
    if (!headerRow) return { headers: STANDARD_HEADERS, rows: [] };

    // Costruisce la mappa: indice colonna → chiave standard (null = ignora)
    const headerCells = Array.from(headerRow.querySelectorAll('td'));
    const colKeys = headerCells.map(td => HEADER_MAP[td.dataset.type] ?? null);

    // Righe dati ordinate per posizione
    const dataRows = Array.from(
        document.querySelectorAll('tr[data-pos]:not(.head)')
    ).sort((a, b) => parseInt(a.dataset.pos) - parseInt(b.dataset.pos));

    const rows = dataRows.map(tr => {
        // Inizializza tutte le colonne standard a stringa vuota
        const obj = {
            'P': '', 'Kart': '', 'Driver': '', 'Lap Time': '',
            'Gap': '', 'Int': '', 'Best': '', 'Laps': '', '__pena__': ''
        };
        Array.from(tr.querySelectorAll('td')).forEach((td, i) => {
            const key = colKeys[i];
            if (key !== null) obj[key] = td.innerText.trim();
        });
        // 'Int' sara' sempre '' (Apex Timing non lo fornisce)
        // '__pena__' va nell'ultima colonna ''
        return [
            obj['P'], obj['Kart'], obj['Driver'], obj['Lap Time'],
            obj['Gap'], obj['Int'], obj['Best'], obj['Laps'], obj['__pena__']
        ];
    }).filter(r => r.some(c => c !== ''));

    return { headers: STANDARD_HEADERS, rows };
}
"""


class ApexTimingScraper(BaseScraper):
    """
    Provider per apex-timing.com.

    Mantiene aperto un browser Playwright tra i poll.
    La pagina viene ricaricata ogni REFRESH_EVERY poll per evitare
    che i dati si "congelino" (Apex Timing usa aggiornamenti live
    via WebSocket interni, ma il refresh funge da rete di sicurezza).
    """

    def __init__(self):
        self._url: str = ""
        self._pw: Playwright | None = None
        self._browser: Browser | None = None
        self._page: Page | None = None
        self._poll_count: int = 0

    def setup(self, url: str) -> None:
        self._url = url
        self._pw = sync_playwright().start()
        self._browser = self._pw.chromium.launch(headless=True)
        self._page = self._browser.new_page()
        print(f"🌐 [ApexTiming] Caricamento pagina: {url}")
        # Aspetta che la tabella sia presente nel DOM prima di procedere
        self._page.goto(url, wait_until="networkidle", timeout=30_000)
        self._page.wait_for_selector("tr.head", timeout=15_000)
        print(f"✅ [ApexTiming] Pagina caricata ({url}). Inizio polling.")

    def scrape(self) -> dict:
        # Refresh periodico come rete di sicurezza
        if self._poll_count > 0 and self._poll_count % REFRESH_EVERY == 0:
            print(f"🔄 [ApexTiming] Refresh pagina... ({self._url})")
            self._page.goto(self._url, wait_until="networkidle", timeout=30_000)
            self._page.wait_for_selector("tr.head", timeout=15_000)

        self._poll_count += 1
        result = self._page.evaluate(JS_EXTRACT_APEX)
        return {
            "headers": result.get("headers", []),
            "rows": result.get("rows", []),
        }

    def teardown(self) -> None:
        if self._browser:
            self._browser.close()
        if self._pw:
            self._pw.stop()
