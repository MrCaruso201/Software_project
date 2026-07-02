"""
Provider per live.racefacer.com.

Usa Playwright per caricare la pagina e uno script JS per estrarre
la tabella con il maggior numero di righe (l'unica tabella rilevante
nella pagina di live timing di RaceFacer).

Il browser rimane aperto tra un poll e l'altro (viene aperto in setup()
e chiuso in teardown()); la pagina viene ricaricata periodicamente
ogni REFRESH_EVERY scrape per evitare che i dati si "congelino".
"""

from playwright.sync_api import sync_playwright, Playwright, Browser, Page

from config import REFRESH_EVERY
from scraper.base import BaseScraper

# ---------------------------------------------------------------------------
# Estrattore JS: seleziona la tabella più grande nella pagina
# ---------------------------------------------------------------------------

JS_EXTRACT = """
() => {
    const tables = document.querySelectorAll('table');
    let bestTable = null;
    let maxRows = 0;
    tables.forEach(t => {
        const rows = t.querySelectorAll('tr');
        if (rows.length > maxRows) { maxRows = rows.length; bestTable = t; }
    });
    if (!bestTable) return { headers: [], rows: [] };

    const allRows = Array.from(bestTable.querySelectorAll('tr'));
    const headers = Array.from(allRows[0]?.querySelectorAll('th, td') || [])
                        .map(c => c.innerText.trim());

    const rows = allRows.slice(1).map(row => {
        return Array.from(row.querySelectorAll('td'))
                    .map(c => c.innerText.trim());
    }).filter(r => r.some(c => c !== ''));

    return { headers, rows };
}
"""


class RaceFacerScraper(BaseScraper):
    """
    Provider per live.racefacer.com.

    Mantiene aperto un browser Playwright tra i poll per evitare
    l'overhead di avvio ad ogni lettura. La pagina viene ricaricata
    ogni REFRESH_EVERY poll per evitare che i dati si "congelino".
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
        print(f"🌐 Caricamento pagina: {url}")
        self._page.goto(url, wait_until="networkidle", timeout=30_000)
        print(f"✅ Pagina caricata ({url}). Inizio polling.")

    def scrape(self) -> dict:
        # Refresh periodico per mantenere i dati aggiornati
        if self._poll_count > 0 and self._poll_count % REFRESH_EVERY == 0:
            print(f"🔄 Refresh pagina... ({self._url})")
            self._page.goto(self._url, wait_until="networkidle", timeout=30_000)

        self._poll_count += 1
        result = self._page.evaluate(JS_EXTRACT)
        return {
            "headers": result.get("headers", []),
            "rows": result.get("rows", []),
        }

    def teardown(self) -> None:
        if self._browser:
            self._browser.close()
        if self._pw:
            self._pw.stop()
