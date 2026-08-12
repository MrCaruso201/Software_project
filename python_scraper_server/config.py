"""
Configurazione centralizzata del server.
Tutte le costanti e le funzioni di validazione URL vivono qui.
"""

from pathlib import Path
from urllib.parse import urlparse

# ---------------------------------------------------------------------------
# mDNS / Bonjour
# ---------------------------------------------------------------------------

SERVICE_TYPE = "_karttiming._tcp.local."
SERVICE_NAME = "Kart Live Timing._karttiming._tcp.local."
SERVICE_PORT = 8000

# ---------------------------------------------------------------------------
# Scraping
# ---------------------------------------------------------------------------

POLL_INTERVAL = 3       # secondi tra un poll e l'altro
REFRESH_EVERY = 10      # refresh pagina ogni N poll
SESSION_IDLE_GRACE = 15  # secondi di grazia prima di fermare una sessione senza iscritti

# Numero massimo di sessioni di scraping distinte attive in contemporanea.
# Protegge da un client che tenta di aprire tanti browser headless diversi
# per esaurire CPU/RAM del server.
MAX_CONCURRENT_SESSIONS = 5

# ---------------------------------------------------------------------------
# URL
# ---------------------------------------------------------------------------

SIMULATOR_URL = "https://simulator"

# Domini che i client possono richiedere via "set_url". Chiunque abbia il
# token può scegliere la propria sorgente, ma solo tra questi host: evita
# che un client possa far scrapare al server URL arbitrari (SSRF verso la
# rete interna, siti a caso, ecc.).
ALLOWED_URL_HOSTS = {
    "live.racefacer.com",
    "www.apex-timing.com",
    "apex-timing.com",
    "simulator",
    # "timing.altrapiattaforma.com",
}

# ---------------------------------------------------------------------------
# Percorsi
# ---------------------------------------------------------------------------

# Cartella data/ interna al progetto
DATA_DIR = Path(__file__).parent / "data"
DATA_DIR.mkdir(exist_ok=True)

SIMULATOR_JSON_PATH = (
    Path(__file__).parent.parent / "racefacer_sim" / "sim_data" / "live_timing.json"
)

# ---------------------------------------------------------------------------
# Validazione URL
# ---------------------------------------------------------------------------


def is_url_allowed(url: str) -> bool:
    """Controlla che l'URL sia https e appartenga a un host consentito."""
    try:
        parsed = urlparse(url)
    except Exception:
        return False
    if parsed.scheme not in ("http", "https"):
        return False
    return parsed.hostname in ALLOWED_URL_HOSTS
