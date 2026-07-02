# Kart Live Timing Server

Documentazione del server Python nella cartella `python_scraper_server`.

## Panoramica

Questo server fornisce un servizio di scraping live per pagine di timing karting, espone i dati via WebSocket e gestisce l'autenticazione degli utenti tramite JWT. Il servizio è pensato per essere pubblicato all'esterno tramite Tailscale Funnel.

Funzionalità principali:

- Scraping headless con `playwright`
- Server WebSocket basato su `FastAPI`
- Autenticazione e Autorizzazione (JWT, RBAC con ruoli viewer, race_director, admin)
- Database SQLite per gestione utenti e refresh token
- Supporto multi-client e multi-URL
- Persistenza temporanea dei payload in file JSON
- Modalità simulatore per test locale

## Architettura

Il progetto utilizza **FastAPI** come framework principale ed è strutturato nei seguenti moduli:

- `main.py`: Entrypoint dell'applicazione, setup di FastAPI e lifespan.
- `auth/`: Logica di autenticazione, gestione JWT, hashing password (bcrypt), definizione dei ruoli e router (`/auth` per login/register e `/admin` per gestione utenti).
- `db/`: Connessione al database SQLite tramite **SQLAlchemy** e modelli ORM (`User`, `RefreshToken`).
- `scraper/`: Logica di scraping (tramite **Playwright**), gestione delle sessioni (`ScraperSession`) e persistenza su disco.
- `ws/`: Gestione delle connessioni WebSocket, smistamento messaggi (broadcast e sottoscrizioni).

### `ScraperSession`

Ogni URL richiesto ha una propria `ScraperSession`. Il server mantiene una mappatura tra client WebSocket e URL richiesti.
- condivide lo stesso browser/thread tra tutti i client che guardano lo stesso URL
- avvia il browser solo quando serve
- ferma la sessione se resta senza client per un breve periodo (default 10s `SESSION_IDLE_GRACE`)
- esegue il polling della pagina ogni `POLL_INTERVAL` (default 15s) e ricarica la pagina dopo un certo numero di cicli (`REFRESH_EVERY`).
- salva i dati in file JSON nella cartella `data/` basati sull'hash dell'URL.

## Autenticazione e Ruoli

L'applicazione espone endpoint REST in `/auth` per gestire l'identità:
- `POST /auth/register`: Crea un nuovo account con ruolo di base (`viewer`).
- `POST /auth/login`: Autentica l'utente e restituisce `access_token` (JWT) e `refresh_token`.
- `POST /auth/refresh`: Emette un nuovo access token tramite il refresh token.
- `POST /auth/logout`: Revoca il refresh token.
- `GET /auth/me`: Ritorna i dettagli dell'utente.

La rotta `/admin/users` permette agli utenti con ruolo **admin** di cercare altri utenti e modificarne i ruoli (`viewer`, `race_director`, `admin`).
Al primo avvio, l'applicazione (`db.init_db()`) crea automaticamente un utente **admin** di default con password `admin`.

## API REST & WebSocket

### Endpoint REST (Auth)
Tutti gli endpoint REST usano token Bearer per le chiamate protette.

### Endpoint WebSocket

- `ws://<host>:8000/ws?token=<ACCESS_TOKEN>`

L'accesso al WebSocket richiede un **token JWT valido** passato come parametro di query. Se il token è assente o non valido, la connessione viene chiusa con codice `4401`.

#### Comandi WebSocket
Riceve in JSON i comandi dal client:
- `set_url`: Iscrive il client a un nuovo URL (avviando la sessione se non esiste). Risponde con `url_changed` o `error`.
- `get_status`: Richiede lo stato corrente. Risponde con `status` (se sta facendo scraping e su quale URL).

Il server invia aggiornamenti asincroni:
- `timing_update`: Inviato in broadcast a tutti i client iscritti a un determinato URL ogni volta che ci sono variazioni nei dati estratti.

## Avvio del server

### Installazione dipendenze

```bash
cd python_scraper_server
python -m pip install -r requirements.txt
python -m playwright install
```

### Esposizione su Tailscale

Per rendere accessibile l'API ai dispositivi remoti in modo sicuro:
```bash
tailscale funnel -bg 8000
```
Questo apre il traffico esterno alla porta 8000 sulla propria macchina (es. `https://marcos-macbook-pro.tail71e118.ts.net`).

### Avvio

```bash
cd python_scraper_server
python main.py
```

Il database SQLite verrà generato automaticamente nella cartella `data/` al primo avvio.

## Note
- Il server supporta una **modalità simulatore**: passando l'URL `https://live.racefacer.com/simulator`, il server leggerà dati fittizi dal file locale invece di lanciare Playwright.
- Il codice mDNS (`discovery/bonjour.py`) è rimasto come riferimento, ma attualmente le connessioni esterne sono pensate per passare tramite Tailscale Funnel in modo protetto via HTTPS.
