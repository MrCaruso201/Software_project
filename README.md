già in possesso

# Kart Timing App

Questa repository contiene il codice per l'ecosistema **Kart Timing App**, un'applicazione completa per il tracciamento e la visualizzazione in tempo reale dei tempi sul giro per gare di kart.

Il progetto si divide in due componenti principali:

1. **App iOS (Client)**: Un'applicazione nativa per iOS (scritta in Swift) che offre un'interfaccia utente fluida per seguire gli eventi in tempo reale, esplorare gare passate e gestire team e piloti.
2. **Server (Scraper & WebSocket API)**: Un server Python basato su FastAPI che estrae i dati dei tempi live (tramite Playwright) e li trasmette ai client connessi via WebSocket.

---

## 📸 Screenshot dell'applicazione

<div align="center">
  <!-- INSERIRE QUI GLI SCREENSHOT -->
  <img src="[URL_IMMAGINE_1]" width="250" alt="Screenshot Schermata Home">
  <img src="[URL_IMMAGINE_2]" width="250" alt="Screenshot Schermata Live Timing">
  <img src="[URL_IMMAGINE_3]" width="250" alt="Screenshot Schermata Dettaglio Gara">
</div>

---

## ✨ Funzionalità Principali

### Lato App (iOS)

- **Live Timing**: Visualizzazione in tempo reale dei tempi sul giro, distacchi e posizioni tramite connessione WebSocket.
- **Gestione Eventi**: Possibilità di esplorare eventi passati, attuali e futuri.
- **Dettagli Piloti e Team**: Pagine dedicate alle statistiche e alle formazioni dei team.
- **Interfaccia Moderna**: Sviluppata in SwiftUI per offrire un'esperienza utente reattiva e nativa.

### Lato Server (Python)

- **Scraping Real-Time**: Motore di scraping basato su Playwright (headless browser) in grado di estrarre e parsare tempestivamente i dati dalle board dei tempi.
- **WebSocket Streaming**: Architettura multi-client gestita in tempo reale. I dati estratti vengono diffusi tramite WebSocket unicamente agli utenti interessati (logica a stanze/URL).
- **Gestione Risorse**: Avvio dinamico delle sessioni di scraping in base alle richieste e spegnimento automatico quando non ci sono più client connessi, per risparmiare risorse.
- **Autenticazione**: Sistema sicuro tramite JWT e ruoli differenziati (viewer, race_director, admin).

---

## 🚀 Istruzioni di Deploy del Server

Segui questi passaggi per configurare ed avviare il server backend `python_scraper_server`.

### Prerequisiti

- **Python 3.13+** installato
- **pip** e/o un gestore di ambienti virtuali (es. `venv`)

### 1. Configurazione dell'ambiente

Naviga all'interno della cartella del server:

```bash
cd python_scraper_server
```

Crea e attiva un ambiente virtuale (consigliato):

```bash
python -m venv .venv

# Su macOS/Linux:
source .venv/bin/activate
# Su Windows:
# .venv\Scripts\activate
```

### 2. Installazione delle dipendenze

Installa i pacchetti richiesti:

```bash
pip install -r requirements.txt
```

Poiché il progetto utilizza Playwright per l'estrazione dei dati, devi installare i browser necessari:

```bash
playwright install
```

### 3. Configurazione delle variabili d'ambiente

Copia il file di esempio per creare la tua configurazione locale:

```bash
cp .env.example .env
```

*(Apri il file `.env` appena creato e compila i campi richiesti, come chiavi segrete JWT o configurazioni database, se necessarie).*

### 4. Avvio del server

Per avviare il server, è sufficiente eseguire direttamente l'entry point:

```bash
python main.py
```

Il server sarà ora in ascolto.

Per il testing si accede da rete locale selezionando l'apposito switch nell'app e selezionando il server scoperto automaticamente sulla rete.

Per accedere da internet bisogna definire un proprio dominio di cui si è già in possesso in 'client_ios_app/KartTimingApp/KartTimingApp/App/AppEnvironment.swift' che riporti punti all'indirizzo del server locale. Il servizio è esposto sulla porta 8000, bisogna configurare di conseguenza mettendolo dietro ad un reverse proxy o apposita configurazione di un tunnel VPN (es. tailscale).

---
