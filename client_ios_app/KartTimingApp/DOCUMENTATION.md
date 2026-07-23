# Kart Live Timing — App iOS

Documentazione del client iOS (SwiftUI) che si collega al server backend, permettendo agli utenti di autenticarsi, gestire le proprie iscrizioni agli eventi, ricevere notifiche e visualizzare la classifica live.

---

## 1. Panoramica

L'app si sviluppa attorno a un'interfaccia basata su `TabView` per gli utenti autenticati:

1. **Autenticazione (`LoginView` / `RegisterView`)**: Solo gli utenti loggati possono accedere alle funzionalità principali.
2. **Home (`UserHomeView`)**: Dashboard riassuntiva con i prossimi eventi a cui l'utente è iscritto e un pannello notifiche interattivo.
3. **Eventi (`EventiView`)**: Esplorazione delle gare disponibili, registrazione (singola o a squadre), gestione del proprio team, e (per gli admin/organizzatori) strumenti di approvazione e modifica iscrizioni.
4. **Timing (`TimingView`)**: La schermata di dettaglio per la classifica live in tempo reale, ricevuta via WebSocket.
5. **Analisi (`AnalisiView`)**: Area placeholder per statistiche post-gara e telemetrie.
6. **Impostazioni (`SettingsView`)**: Gestione profilo, configurazione app e accesso all'area di amministrazione utenti (`AdminUsersView`).

---

## 2. Architettura e Flussi Principali

### 2.1 Autenticazione e Profilo (`AuthService` e `AuthState`)
- Usa **JWT** per identificare univocamente gli utenti.
- All'avvio verifica l'esistenza di un token salvato in modo sicuro nel sistema.
- Gestisce il Role-Based Access Control (RBAC): i ruoli (`user`, `race_director`, `admin`) vengono estratti o letti tramite API per mostrare o nascondere dinamicamente funzionalità organizzative avanzate nell'interfaccia (come la forzatura di iscrizioni o l'accesso al pannello Admin).

### 2.2 Gestione Eventi e Iscrizioni (`EventiViewModel`)
L'interfaccia per la gestione eventi modella due modalità di iscrizione:
- **Iscrizioni in Team**: il team leader crea il team e può aggiungere o rimuovere compagni indicandone le email.
- **Iscrizioni Singole**: per campionati individuali.
- **Strumenti Race Director**: gli utenti autorizzati (es. organizzatori) possono cambiare manualmente lo stato dell'evento (es. passare un utente in lista d'attesa a confermato), ricevere o respingere iscritti, e forzare forzatamente la creazione o assegnazione di team e iscritti individuali.

### 2.3 Sistema di Notifiche PUSH/in-app (`NotificationsPanelView`)
Un banner notifiche raggiungibile dalla Home (`UserHomeView` tramite icona a campanella) gestisce il feedback di sistema asincrono:
- Permette di vedere notifiche (es. quando si viene aggiunti a un team o si riceve una conferma).
- Usa indicatori visuali per le notifiche non lette (pallino e sfondo evidenziato).
- Supporta l'interazione profonda (Deep Linking simulato tramite `AppEnvironment.pendingEventIdToOpen`): toccando una notifica legata a un evento, l'app salta automaticamente alla scheda "Eventi" e apre la schermata dei dettagli "Maggiori Info" per l'evento corretto, risolvendo problematiche di caricamento asincrono.
- Supporta le gestures native iOS, come lo swipe a sinistra per eliminare fisicamente la notifica.

### 2.4 Live Timing (`TimingView.swift` + `KartTimingManager.swift`)
La connessione WebSocket (`wss://<SERVER>/ws?token=<ACCESS_TOKEN>`) riceve aggiornamenti JSON continui (es. comando `timing_update`). 
I dati sono decodificati (tramite `TimingPayload`) e mostrati tramite componenti visivi (Card e Tabelle). L'interfaccia è progettata con una palette scura ad alto contrasto adatta per uso "Trackside" o all'aperto sotto al sole:
- `kartBG`: Sfondo principale molto scuro
- `kartAccent`: Accenti, leaderboard gap e badge di notifica
- `kartGreen`/`kartRed`: Feedback operativi

---

## 3. Struttura dei File (Sotto-directory principali)

| Directory / File | Responsabilità |
| --- | --- |
| `App/KartTimingAppApp.swift` | Entry point, setup dell'ambiente e definizione della root view in base allo stato di login. |
| `App/AppEnvironment.swift` | Gestisce configurazioni globali (come la modalità Dev) e la navigazione asincrona "cross-tab" (es. apertura eventi da notifica). |
| `Features/Home/` | `HomeView` (il TabView principale dell'app), `UserHomeView`, e logica del pannello notifiche interagibile a scomparsa. |
| `Features/Events/` | Esplorazione eventi, logica del model `EventiViewModel`, maschere (Sheet) per l'iscrizione, per l'amministrazione, e modifica team. |
| `Features/Timing/` | Motore WebSocket (`KartTimingManager`), visualizzazione tabellare classifica e controllo dell'URL di scraping. |
| `Features/Settings/` | Opzioni account, pulsante di logout e bridge verso `AdminUsersView`. |
| `Network/` | Servizi client HTTP (`AuthService` e REST call generiche). |
| `Models/` | Entità di mappatura JSON (Event, EventRegistration, Notification, TimingPayload, User, Role). |

---

## 4. Considerazioni per RASD e DD

In previsione della stesura dei documenti accademici e di progettazione per l'intero sistema:

- **RASD (Requisiti)**:
  - Gli use case principali ruotano attorno a 3 tipologie di attori (Personas): Utente Base (pilota/spettatore), Race Director (organizzatore dell'evento/gara), e Admin (supervisore e manutentore del software).
  - La ricezione dati in real-time senza bisogno di refresh manuale (WebSockets), accoppiato alle Notifiche in-app affidabili e persistenti sono considerati requisiti non funzionali chiave del sistema, insieme all'usabilità e la compatibilità su schermi iOS ridotti.

- **DD (Design)**:
  - L'architettura software di alto livello è un classico **Client-Server**. Il client iOS implementa il design pattern **MVVM** (Model-View-ViewModel), delegando la reattività di UI a SwiftUI e i side-effect (API/Sockets) al ViewModel.
  - La comunicazione ibrida sfrutta **REST** (per le risorse CRUD come Eventi, Iscrizioni e Notifiche) e **WebSocket** (per i flussi di dati continui del live timing), evidenziando scelte architetturali basate sul trade-off tra facilità di caching/routing per REST e performance real-time per WS.
  - L'uso di `EnvironmentObject` in SwiftUI viene sfruttato per iniettare le dipendenze globali e orchestrare la navigazione profonda (Deep Linking) in maniera reattiva.
