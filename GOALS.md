<<<<<<< HEAD
# 🏁 Kart Live Timing — Project Goals

## Overview

**Kart Live Timing** is a comprehensive system for managing and monitoring karting races in real time. The project was born with the goal of digitalizing and simplifying the entire race experience: from driver registration to live timing display, through waiver signing and final results consultation.

The system is composed of two macro-components:
- **Backend** – Python server (FastAPI) with SQLite database, headless scraping and WebSocket communication
- **Frontend** – Native iOS app (SwiftUI / MVVM) for drivers, team managers and race directors

---

## 🎯 Main Goals

### 1. Real-Time Live Timing
Provide drivers and teams with an immediate and accurate view of the standings during the race, collecting data through automatic scraping of third-party timing platforms (Apex Timing, RaceFacer).

- Persistent WebSocket connection between server and iOS client
- Continuous standings updates without the need for manual refresh
- High-contrast dark-mode interface, inspired by real trackside monitors
- Differentiated views for driver, team and race director

### 2. Complete Race Event Management
Allow Race Directors to create and configure events, manage registrations and coordinate the entire race logistics from the app.

- Event creation with customizable parameters (circuit, date, format)
- Individual and team registration system (with email invitations)
- Registration queue management and manual approval
- Final results upload after the race concludes

### 3. Authentication and User Roles
Ensure secure and differentiated access based on role, with a three-level permission system.

| Role | Main Capabilities |
|---|---|
| `user` | Race registration, live timing view, waiver signing |
| `race_director` | Event creation, registration management, kart assignment, race control messaging |
| `admin` | User registry management, role editing, access to signed waivers |

### 4. Digital Waiver Signing
Collect participants' biometric signatures directly on the app, generating a signed PDF document archived by the backend.

- Signature canvas on screen (PencilKit) with Base64 capture
- On-the-fly PDF generation via `fpdf2` on the server
- Consultation and download of signed waivers by admins

### 5. Automatic Server Discovery on Local Network
Eliminate the need for users to manually enter the server IP address, making the setup experience seamless.

- Server publishing on local network via **mDNS / Bonjour** protocol
- Automatic discovery in the iOS app via `NetServiceBrowser`
- Support for remote connection via **Tailscale Funnel** for sessions outside the local network

### 6. Post-Race Analysis
Allow drivers and teams to review performance from completed races through statistics and historical standings.

- Finalized results consultation per event
- Dedicated analysis view with aggregated statistics
- Admin panel with aggregated user metrics

---

## 🔮 Future Goals (Roadmap)

- [ ] **Push Notifications** – Real-time alerts on upcoming events, race status changes and messages from race control
- [ ] **Multi-provider Scraping** – Expansion of support to additional timing platforms beyond Apex Timing and RaceFacer
- [ ] **Advanced Statistics** – Telemetry charts (lap trends, driver comparison) in the Analysis section
- [ ] **Android / Web Version** – Client extension to additional platforms
- [ ] **Offline Mode** – Local data cache to continue consulting timing even in case of connection loss
- [ ] **Payment Integration** – Registration fee management directly in-app

---

## 🏗️ Design Principles

- **Real-time first** – Every architectural decision prioritizes low latency and interface responsiveness
- **Role separation** – Each actor (driver, director, admin) has a dedicated and optimized UX
- **Security** – JWT for authentication, bcrypt for passwords, Keychain for token storage on iOS
- **Extensibility** – Factory pattern for scrapers and MVVM architecture on the client facilitate adding new providers and features
- **Zero-config networking** – The user does not need to know or type IP addresses

---

*Last updated: September 2026*
=======
# 🏁 Kart Live Timing — Goal del Progetto

## Panoramica

**Kart Live Timing** è un sistema completo per la gestione e il monitoraggio in tempo reale di gare di karting. Il progetto nasce con l'obiettivo di digitalizzare e semplificare l'intera esperienza di gara: dalla registrazione dei piloti alla visualizzazione dei tempi live, fino alla firma delle liberatorie e alla consultazione dei risultati finali.

Il sistema è composto da due macro-componenti:
- **Backend** – Server Python (FastAPI) con database SQLite, scraping headless e comunicazione WebSocket
- **Frontend** – App iOS nativa (SwiftUI / MVVM) per piloti, team manager e direttori di gara

---

## 🎯 Goal Principali

### 1. Live Timing in Tempo Reale
Fornire a piloti e team una visualizzazione immediata e accurata della classifica durante la gara, raccogliendo i dati tramite scraping automatico delle piattaforme di timing di terze parti (Apex Timing, RaceFacer).

- Connessione WebSocket persistente tra server e client iOS
- Aggiornamento continuo della classifica senza necessità di refresh manuale
- Interfaccia dark-mode ad alto contrasto, ispirata ai veri monitor in pista
- Viste differenziate per pilota, team e race director

### 2. Gestione Completa degli Eventi di Gara
Consentire ai Race Director di creare e configurare eventi, gestire iscrizioni e coordinare l'intera logistica della gara dall'app.

- Creazione di eventi con parametri personalizzabili (circuito, data, formato)
- Sistema di iscrizioni individuali e a squadre (con inviti via email)
- Gestione delle code di iscrizione e approvazione manuale
- Upload dei risultati finali a gara conclusa

### 3. Autenticazione e Ruoli Utente
Garantire un accesso sicuro e differenziato in base al ruolo, con un sistema di permessi a tre livelli.

| Ruolo | Capacità principali |
|---|---|
| `user` | Iscrizione alle gare, visualizzazione live timing, firma liberatoria |
| `race_director` | Creazione eventi, gestione iscrizioni, assegnazione kart, invio messaggi in direzione gara |
| `admin` | Gestione anagrafica utenti, modifica ruoli, accesso alle liberatorie firmate |

### 4. Firma Digitale delle Liberatorie
Raccogliere la firma grafometrica dei partecipanti direttamente sull'app, generando un documento PDF firmato archiviato dal backend.

- Canvas firma su schermo (PencilKit) con acquisizione in Base64
- Generazione PDF on-the-fly tramite `fpdf2` sul server
- Consultazione e download delle liberatorie firmate da parte degli admin

### 5. Scoperta Automatica del Server in Rete Locale
Eliminare la necessità per l'utente di inserire manualmente l'indirizzo IP del server, rendendo l'esperienza di setup trasparente.

- Pubblicazione del server su rete locale tramite protocollo **mDNS / Bonjour**
- Rilevamento automatico nell'app iOS tramite `NetServiceBrowser`
- Supporto alla connessione remota via **Tailscale Funnel** per sessioni fuori dalla rete locale

### 6. Analisi Post-Gara
Permettere a piloti e team di rivedere le performance delle gare concluse tramite statistiche e classifiche storiche.

- Consultazione dei risultati finalizzati per evento
- Vista di analisi dedicata con statistiche aggregate
- Pannello admin con metriche aggregate sugli utenti

---

## 🔮 Goal Futuri (Roadmap)

- [ ] **Notifiche Push** – Avvisi in tempo reale su eventi imminenti, cambi di stato gara e messaggi dalla direzione corsa
- [ ] **Multi-provider Scraping** – Ampliamento del supporto a ulteriori piattaforme di timing oltre ad Apex Timing e RaceFacer
- [ ] **Statistiche avanzate** – Grafici di telemetria (andamento giri, confronto piloti) nella sezione Analisi
- [ ] **Versione Android / Web** – Estensione del client su ulteriori piattaforme
- [ ] **Modalità offline** – Cache locale dei dati per continuare a consultare timing anche in caso di perdita di connessione
- [ ] **Integrazione pagamenti** – Gestione delle quote di iscrizione direttamente in-app

---

## 🏗️ Principi di Progettazione

- **Real-time first** – Ogni decisione architetturale privilegia la bassa latenza e la reattività dell'interfaccia
- **Separazione dei ruoli** – Ogni attore (pilota, direttore, admin) ha una UX dedicata e ottimizzata
- **Sicurezza** – JWT per l'autenticazione, bcrypt per le password, Keychain per lo storage del token su iOS
- **Estensibilità** – Pattern Factory per gli scraper e architettura MVVM sul client facilitano l'aggiunta di nuovi provider e funzionalità
- **Zero-config networking** – L'utente non deve conoscere né digitare indirizzi IP

---

*Ultima modifica: Settembre 2026*
>>>>>>> origin/app_dev
