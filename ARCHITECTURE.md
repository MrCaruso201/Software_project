# Documentazione Architetturale e Mappa dei File

Questo documento descrive in dettaglio l'architettura del sistema Kart Live Timing, seguendo esattamente l'organizzazione fisica delle cartelle e dei file. Il progetto si divide in due macro-aree: il server backend (Python/FastAPI) e il client mobile (iOS/SwiftUI).

---

## 1. Server Python (Backend) - `python_scraper_server/`

Il server è basato su FastAPI e utilizza un database SQLite. Svolge i ruoli di API RESTful e gestore WebSocket per i dati in tempo reale estratti tramite uno scraper Playwright.

- **`main.py`**: Entry point del server FastAPI. Configura CORS, mappa i router e inizializza il database.
- **`config.py`**: Carica e rende disponibili le variabili d'ambiente (es. dal file `.env`).
- **`requirements.txt`**: Elenco delle librerie Python necessarie.
- **`DOCUMENTATION.md`**: Documentazione isolata specifica per il setup del server.

### `auth/` - Autenticazione e Autorizzazione
- **`__init__.py`**: Inizializzatore del modulo.
- **`admin_router.py`**: Endpoint API riservati agli amministratori per gestire utenti.
- **`dependencies.py`**: Funzioni di Dependency Injection (es. `get_current_user`) per proteggere le rotte API.
- **`jwt.py`**: Logica di creazione, decodifica e validazione dei token JWT.
- **`password.py`**: Utility per l'hashing sicuro delle password tramite bcrypt (passlib).
- **`roles.py`**: Definizione dei ruoli di sistema (`user`, `race_director`, `admin`) e logiche associate.
- **`router.py`**: Endpoint per login, registrazione e recupero del profilo corrente (`/me`).
- **`schemas.py`**: Modelli Pydantic per validare i payload in ingresso e uscita relativi all'auth.
- **`token.py`**: Modelli Pydantic per i payload del token JWT.

### `db/` - Database
- **`__init__.py`**: Inizializzatore del modulo.
- **`database.py`**: Configurazione del motore SQLAlchemy e gestione delle sessioni SQLite.
- **`models.py`**: Definisce tutte le tabelle (ORM) del database (es. `User`, `Event`, `Kartodromo`, ecc.).

### `discovery/` - Network Discovery
- **`__init__.py`**: Inizializzatore del modulo.
- **`bonjour.py`**: Pubblica il server sulla rete locale usando il protocollo mDNS (Bonjour), facilitando la connessione dell'app senza inserire IP manualmente.

### `events/` - Gare e Iscrizioni
- **`router.py`**: Endpoint per creare eventi e gestire le iscrizioni di singoli o squadre.
- **`schemas.py`**: Modelli Pydantic per la validazione di gare, iscrizioni e squadre.

### `kartodromi/` - Anagrafica Piste
- **`__init__.py`**: Inizializzatore del modulo.
- **`router.py`**: Endpoint per la creazione e la consultazione dei circuiti.
- **`schemas.py`**: Modelli Pydantic per la validazione dei dati delle piste.

### `live/` - Stato in Diretta
- **`__init__.py`**: Inizializzatore del modulo.
- **`router.py`**: Endpoint per gestire e notificare lo stato in corso delle gare.
- **`schemas.py`**: Modelli Pydantic per il controllo dello stato live.

### `notifications/` - Notifiche Utente
- **`router.py`**: Endpoint per interrogare, contrassegnare come lette o eliminare le notifiche persistenti salvate nel DB.
- **`schemas.py`**: Modelli Pydantic per le notifiche in-app.

### `results/` - Classifiche Finali
- **`__init__.py`**: Inizializzatore del modulo.
- **`router.py`**: Endpoint per il caricamento o recupero dei risultati finalizzati di un evento.
- **`schemas.py`**: Modelli Pydantic per i risultati definitivi.

### `scraper/` - Motore Headless Scraping
Recupera i tempi live su interfacce web di fornitori terzi.
- **`__init__.py`**: Inizializzatore del modulo.
- **`base.py`**: Interfaccia astratta (BaseScraper) da cui ereditano tutti gli scraper.
- **`factory.py`**: Pattern Factory per instanziare la classe di scraping adatta in base all'URL.
- **`session.py`**: Gestione del ciclo di vita globale di Playwright (avvio/spegnimento browser in background).
- **`storage.py`**: Meccanismo per mettere in cache e organizzare i payload grezzi estratti.
- **`providers/`**: Cartella con le implementazioni per fornitori specifici.
  - **`apex_timing.py`**: Algoritmi di estrazione per i circuiti basati su Apex Timing.
  - **`generic.py`**: Scraper generico/fallback.
  - **`racefacer.py`**: Algoritmi di estrazione per i circuiti basati su RaceFacer.
  - **`simulator.py`**: Scraper di test che emula un live timing senza connettersi ad internet.

### `services/` - Integrazioni Extra
- **`pdf_generator.py`**: Utilizza `fpdf2` per costruire on-the-fly liberatorie in PDF con i dati dell'utente e la firma inserita su schermo mobile.

### `ws/` - Comunicazione WebSocket
- **`__init__.py`**: Inizializzatore del modulo.
- **`manager.py`**: Tiene traccia dei client connessi al WebSocket e implementa i metodi di broadcasting.
- **`router.py`**: Endpoint `/ws` principale in attesa delle connessioni dal client iOS.

---

## 2. App iOS (Frontend) - `client_ios_app/KartTimingApp/KartTimingApp/`

L'applicazione mobile è scritta in SwiftUI utilizzando l'architettura **MVVM**.

- **`Info.plist`**: File di metadati di sistema (permessi, configurazioni bundle).

### `App/` - Entry point
- **`KartTimingAppApp.swift`**: L'avvio dell'applicazione. Sceglie se mostrare la dashboard o la schermata di login.
- **`AppEnvironment.swift`**: Oggetto di stato globale usato per smistare comportamenti di navigazione profonda (come toccare una notifica che apre i dettagli di una gara).

### `Auth/` - Autenticazione Client-side
- **`AuthService.swift`**: Interfaccia di rete per le chiamate API di login e registrazione.
- **`AuthState.swift`**: View Model globale che conserva in memoria l'utente corrente e il suo token JWT.
- **`KeychainService.swift`**: Wrapper per salvare e recuperare in modo criptato il token nel Keychain di iOS.
- **`LoginView.swift`**: Interfaccia utente grafica per la pagina di benvenuto e accesso.

### `Features/` - Interfacce e View Models (Dominio Applicativo)
Raggruppa le funzionalità principali nei vari tab/percorsi.

#### `Features/Admin/` - Pannelli di Back-Office
- **`AdminAnalisiView.swift`**: Visualizzazione macro delle statistiche utente per gli amministratori.
- **`AdminKartodromoView.swift`**: Schermata per la lista delle piste gestibili dagli admin.
- **`AdminUserDetailView.swift` / `AdminUserSearchCard.swift`**: Visualizzazione di dettaglio e card sintetica per l'anagrafica utenti.
- **`AdminUserSearchViewModel.swift` / `AdminUsersView.swift`**: Motore e interfaccia di ricerca per trovare e modificare ruoli utenti.
- **`Kartodromo.swift` / `KartodromoFormView.swift` / `KartodromoViewModel.swift`**: Modello UI, form di creazione/modifica e logica associata alle piste.

#### `Features/Analisi/`
- **`AnalisiView.swift` / `AnalisiViewModel.swift`**: Schermata e logica per l'esplorazione dei risultati di gare concluse.
- **`EventResultModels.swift`**: Strutture dati di supporto alle statistiche.

#### `Features/Events/` - Gestione Gare
- **`EventiView.swift` / `EventiViewModel.swift`**: Elenco delle gare imminenti e chiamate di rete.
- **`EventDetailView.swift` / `EventDetailContentView.swift`**: Dettaglio della singola gara con lista partecipanti.
- **`EventiFormView.swift`**: Form accessibile ai Race Director per configurare una nuova gara.
- **`EventRegistrationSheetView.swift` / `EventTeamEditSheetView.swift`**: Modali per iscriversi e gestire il proprio team (inviti tramite mail).
- **`AdminEventView.swift` / `AdminEventRegistrationsView.swift`**: Strumenti per Race Director per gestire le code e forzare iscrizioni.
- **`AdminAddRegistrationSheetView.swift` / `AdminReleaseFormSheetView.swift`**: Approvazione delle iscrizioni e consultazione firme ricevute.
- **`ReleaseFormSignView.swift` / `SignaturePadView.swift`**: Interfaccia per raccogliere dati anagrafici e un canvas (PencilKit) per acquisire la firma grafometrica in Base64.
- **`PDFViewer.swift`**: Lettore PDF per visualizzare il documento finale generato dal backend.
- **`PaymentInfoSheetView.swift`**: Modale per le direttive di pagamento.
- **`UploadResultsView.swift`**: Form per consentire al Race Director l'upload dei risultati finali.
- **`RaceEvent.swift` / `TeamMemberView.swift`**: View Model di evento locale e componente UI per visualizzare il membro di un team.
- **`UserEventView.swift`**: Interfaccia di visualizzazione eventi dalla prospettiva del pilota.

#### `Features/Home/` - Dashboard e Notifiche
- **`HomeView.swift`**: Contenitore TabView primario.
- **`UserHomeView.swift` / `UserHomeViewModel.swift`**: La dashboard principale in cui atterra un utente loggato.
- **`NotificationsPanelView.swift` / `AppNotification.swift`**: Il pannello a comparsa contenente le notifiche (alert di sistema) che consentono di navigare verso gli eventi tramite tap.
- **`GuestLiveTimingPlaceholderView.swift`**: Vista segnaposto per chi non è autenticato.

#### `Features/Live/` - Esperienza durante la Gara
- **`LiveRootView.swift` / `LiveViewModel.swift` / `Models/LiveModels.swift`**: Radice della navigazione, gestione della logica real-time e modelli dati per il timing dal vivo.
- **`Director/`**: Sotto-cartella con controlli per il Race Director.
  - `ClassificaLiveView.swift`, `DirectorLiveView.swift`: Interfacce per manipolare l'andamento della gara.
  - `KartAssignmentView.swift`, `KartPenaltyView.swift`: Finestre per l'assegnazione fisica del numero kart al pilota o di eventuali sanzioni.
  - `MessaggiView.swift`: UI per l'invio di messaggi in direzione corsa.
- **`User/`**: Sotto-cartella con viste per i normali utenti.
  - `PilotLiveView.swift`, `TeamLiveView.swift`, `UserLiveView.swift`: Schermate specifiche (spesso orizzontali ad alto contrasto) con telemetria utile al pilota o al team ai box.

#### `Features/Settings/` - Gestione Profilo
- **`SettingsView.swift`**: Menu impostazioni per profilazione e tasto disconnessione.
- **`EditProfileView.swift` / `ChangePasswordView.swift`**: Aggiornamento credenziali.

#### `Features/Timing/` - Motore WebSocket Client-Side
- **`KartTimingManager.swift`**: Cuore pulsante che si collega a `/ws`, riceve gli update live in JSON continuo dal server e ne notifica le View iscritte.
- **`TimingView.swift` / `PilotView.swift`**: Tabelle UI dark-mode (ispirate ai veri monitor in pista) che renderizzano ciclicamente la classifica estratta dal WebSocket.

### `Models/` - Data Transfer Object
- **`Models.swift` / `UserRole.swift`**: Strutture conformi al protocollo `Codable` per il matching esatto dei JSON inviati dalle chiamate REST di FastAPI (es. Utente, Ruolo, Gara).

### `Services/` - Utility di Sistema
- **`ServerBrowser.swift`**: Implementazione Bonjour (`NetServiceBrowser`) per cercare il server sulla rete Wi-Fi locale, aggirando il bisogno per l'utente di inserire manualmente un IP statico.

### `UI/` - Estetica e Design System
- **`Color+Theme.swift`**: Definizione di accenti, tinte di contrasto e scale cromatiche specifiche del progetto (es. `kartGreen`, `kartAccent`, ottimizzati sia per il dark che per il light mode).
