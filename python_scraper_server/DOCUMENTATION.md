# Kart Live Timing Server

Documentazione del server Python nella cartella `python_scraper_server`.

## Panoramica

Questo server fornisce un servizio di scraping live per pagine di timing karting, espone i dati via WebSocket e pubblica il servizio sulla rete locale con Bonjour/mDNS.

Funzionalità principali:

- Scraping headless con `playwright`
- Server WebSocket basato su `FastAPI`
- Scoperta di rete con `zeroconf`
- Supporto multi-client e multi-URL
- Persistenza temporanea dei payload in file JSON
- Modalità simulatore per test locale

## File principali

- `main.py`: logica del server, scraping, gestione delle sessioni e endpoint WebSocket
- `requirements.txt`: dipendenze Python
- `data/`: directory per i file di output JSON temporanei

## Architettura

Il server mantiene una mappatura tra client WebSocket e URL richiesti.
Ogni URL gestito ha una propria `ScraperSession`:

- condivide lo stesso browser/thread tra tutti i client che guardano lo stesso URL
- avvia il browser solo quando serve
- ferma la sessione se resta senza client per un breve periodo

### `ScraperSession`

- esegue il polling della pagina ogni `POLL_INTERVAL` secondi (default 15s)
- ricarica la pagina ogni `REFRESH_EVERY` poll (default refresh ogni 10 poll)
- tempo di `POLL_INTERVAL` tra un poll e l'altro (default 3s)
- salva payload JSON atomici in `data/live_timing_<hash>.json`
- invia ai client solo se i dati cambiano

## Configurazione

Le impostazioni principali sono definite in `main.py`:

- `SERVICE_TYPE`: `_karttiming._tcp.local.`
- `SERVICE_NAME`: `Kart Live Timing._karttiming._tcp.local.`
- `SERVICE_PORT`: `8000`
- `API_TOKEN`: token di accesso per i WebSocket
- `POLL_INTERVAL`: intervallo di polling
- `REFRESH_EVERY`: numero di poll prima del refresh di pagina
- `SESSION_IDLE_GRACE`: tempo di grazia prima di fermare una sessione inattiva

### URL predefiniti

- `DEFAULT_URL`: `https://live.racefacer.com/ottobianomotorsport`
- `SIMULATOR_URL`: `https://live.racefacer.com/simulator`

## Modalità simulatore

Se un client imposta l'URL `https://live.racefacer.com/simulator`, il server non usa Playwright.
Invece legge i dati da:

- `../racefacer_sim/sim_data/live_timing.json`

Questo permette di testare il server senza avviare un browser headless.

## WebSocket API

### Endpoint

- `ws://<host>:8000/ws`

### Autenticazione

Se `API_TOKEN` è impostato, il client deve fornire il token come parametro di query:

```txt
ws://localhost:8000/ws?token=miotokentest12345
```

Se il token è errato, la connessione viene chiusa con codice `4401`.

### Comandi supportati

Il server riceve messaggi JSON da client WebSocket. I comandi supportati sono:

- `set_url`
- `get_status`

#### `set_url`

Richiede il corpo:

```json
{
  "command": "set_url",
  "url": "https://live.racefacer.com/ottobianomotorsport"
}
```

Risposte possibili:

- `url_changed` quando l'URL è valido
- `error` quando l'URL non è valido

Dopo il cambio URL il client viene sottoscritto alla nuova sessione e riceve subito l'ultimo payload disponibile.

#### `get_status`

Richiede il corpo:

```json
{
  "command": "get_status"
}
```

Risposta:

```json
{
  "type": "status",
  "scraping": true,
  "url": "https://..."
}
```

### Messaggi inviati dal server

Quando i dati cambiano, il server invia messaggi di tipo `timing_update` ai client collegati allo stesso URL:

```json
{
  "type": "timing_update",
  "url": "...",
  "updated_at": "...",
  "headers": [...],
  "rows": [...]
}
```

## Scoperta Bonjour / mDNS

Il server annuncia il servizio locale con:

- tipo: `_karttiming._tcp.local.`
- nome: `Kart Live Timing._karttiming._tcp.local.`
- porta: `8000`

Questo consente ai client compatibili di scoprire automaticamente il server sulla stessa rete locale.

## Persistenza dei dati

I payload vengono salvati in `python_scraper_server/data/` con nomi file basati sull'hash dell'URL:

- `data/live_timing_<hash>.json`

I file vengono eliminati allo shutdown del server, all'avvio e quando una sessione resta senza client per `SESSION_IDLE_GRACE` secondi.

## Avvio del server

### Installazione dipendenze

```bash
cd python_scraper_server
python -m pip install -r requirements.txt
python -m playwright install
```

### Avvio Funnel tailscale (remote connections)

```bash
tailscale funnel -bg 8000
```

Avvio un tailscale funnel in background che indirizza il traffico esterno alla porta 8000 di localhost

### Avvio

```bash
cd python_scraper_server
python main.py
```

Il server ascolta su `0.0.0.0:8000`.

## Note

- Il browser headless viene creato con Playwright Chromium.
- I thread di scraping eseguono `sync_playwright` fuori dall'evento asincrono principale.
- Le sessioni vengono fermate automaticamente quando non ci sono più client.
- Il server supporta sia scraping reale che modalità simulatore.
