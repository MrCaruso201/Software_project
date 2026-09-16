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
