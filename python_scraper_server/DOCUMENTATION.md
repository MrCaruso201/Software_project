# Kart Live Timing Server

Documentazione del server Python nella cartella `python_scraper_server`.

## Panoramica

Questo server fornisce un servizio backend completo per un'applicazione di gestione gare di kart e live timing. Espone API RESTful e WebSocket, appoggiandosi a un database SQLite e gestendo l'autenticazione tramite JWT. 

Funzionalità principali:
- **Scraping headless**: Estrazione dati live da pagine di timing karting tramite browser automatizzato (`playwright`).
- **Live Timing (WebSocket)**: Diffusione in tempo reale dei dati estratti basata su `FastAPI`.
- **Gestione Eventi e Iscrizioni**: Creazione gare, iscrizioni individuali e a squadre (team leader, membri), gestione stati (confermato, lista d'attesa, in attesa di pagamento).
- **Liberatorie Digitali**: Sistema per la ricezione di firme digitali, storicizzazione in Base64 e generazione dinamica on-the-fly di documenti PDF firmati completi di dati anagrafici e dell'evento (tramite `fpdf2`).
- **Sistema di Notifiche**: Notifiche in-app persistenti per gli utenti (aggiunta a team, conferme iscrizioni, modifiche da parte dell'admin, rifiuto liberatorie).
- **Autenticazione e Autorizzazione**: Autenticazione JWT e controllo degli accessi Role-Based (RBAC) con ruoli (`user`, `race_director`, `admin`).
- **Anagrafica Kartodromi**: Gestione centralizzata delle piste in cui si svolgono gli eventi.

## Architettura

Il progetto utilizza **FastAPI** come framework principale ed è strutturato nei seguenti moduli:

- `main.py`: Entrypoint dell'applicazione, setup di FastAPI, integrazione dei router, policy CORS e script di inizializzazione DB.
- `auth/`: Logica di autenticazione, gestione JWT, hashing password (bcrypt), definizione dei ruoli e gestione utenti.
- `db/`: Connessione al database SQLite tramite **SQLAlchemy** e modelli ORM (`User`, `Event`, `EventRegistration`, `Notification`, `Kartodromo`, `SignedRelease`).
- `events/`: Endpoint per la gestione di eventi, iscrizioni (singole e team) e firme liberatorie.
- `services/`: Moduli per servizi specifici, come `pdf_generator.py` che genera i PDF delle liberatorie usando `fpdf2`.
- `notifications/`: Endpoint per il recupero, la marcatura come lette e l'eliminazione delle notifiche, con un helper interno (`notify_user`) per generare eventi.
- `kartodromi/`: Gestione anagrafica piste.
- `scraper/`: Logica di scraping tramite **Playwright** e gestione sessioni globali (`ScraperSession`). Ottimizzato per istanziare un solo browser per URL richiesto, con auto-shutdown in caso di inattività.
- `ws/`: Gestione delle connessioni WebSocket per il live timing, iscrizione ai feed e broadcast differenziato per URL sorgente.

### Modello Dati (Database)

Il database SQLite (`data/kart_timing.db`) modella le seguenti entità principali:
- **User**: Dati anagrafici e credenziali (username, email, password, ruolo, immagine profilo).
- **Event**: Gare organizzate (nome, data, kartodromo, tipologia team/singolo, limiti partecipanti, regole di coda, testo liberatoria).
- **EventRegistration**: Iscrizioni agli eventi. Supporta logicamente iscrizioni singole o di squadra (tramite `team_id`), traccia lo stato e ruoli interni al team (`is_team_leader`, `accepts_extra_pilots`).
- **SignedRelease**: Registra la compilazione della liberatoria da parte di un utente per un determinato evento, includendo dati anagrafici (codice fiscale, residenza) e la stringa in Base64 contenente l'immagine della firma apposta dal touch-screen.
- **Notification**: Logica di notifica utente, indicatore di lettura (`is_read`), con riferimento opzionale all'evento.
- **Kartodromo**: Info sulla pista geografica.

## Autenticazione e Ruoli

L'applicazione espone endpoint REST in `/auth` per gestire l'identità:
- `POST /auth/register` e `POST /auth/login` (ritorna JWT `access_token` e payload dati base).
- `GET /auth/me`: Ritorna i dettagli dell'utente.

I ruoli gestiti:
- **user**: Utente base. Può iscriversi agli eventi, creare squadre, gestire i propri compagni.
- **race_director**: Organizzatore. Può creare/modificare eventi, gestire le iscrizioni, forzare stati, assegnare utenti in team, accettare da lista d'attesa.
- **admin**: Accesso completo, inclusa la promozione e retrocessione dei ruoli degli altri utenti.

## Logica Notifiche

Il server implementa un sistema di notifica automatizzato integrato nei flussi operativi. Le notifiche vengono generate quando:
- Un utente viene aggiunto/rimosso da un team (dal leader del team o da un admin).
- Lo stato di un'iscrizione cambia (es. iscrizione confermata, spostato in waitlist).
- Un admin forza un'iscrizione o modifica i dati di una squadra (informa il leader o gli utenti coinvolti).

Le notifiche sono interrogabili in `/notifications/me` e supportano la marcatura di lettura (`/read`) e la cancellazione visiva o logica (`DELETE`).

## Avvio del server

### Installazione dipendenze

```bash
cd python_scraper_server
python -m pip install -r requirements.txt
python -m playwright install
```

### Avvio

```bash
cd python_scraper_server
python main.py
```

Il database SQLite verrà generato automaticamente nella cartella `data/` al primo avvio, includendo account admin base e dati mock iniziali se configurato.
