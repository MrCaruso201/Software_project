# Race Manager — App iOS

Aggiornamento: 16 settembre 2026. Questa documentazione descrive il codice SwiftUI presente in `KartTimingApp/`, confrontato con le API backend. La revisione è statica: non è stata eseguita una build Xcode né una prova su dispositivo. Vedere anche [architettura](../../ARCHITECTURE.md) e [documentazione backend](../../python_scraper_server/DOCUMENTATION.md).

## 1. Progetto e navigazione

Aprire `KartTimingApp.xcodeproj` in Xcode. Il deployment target configurato nel progetto è **iOS 26.1**; servono un SDK/toolchain adeguati ed eventuale signing per il dispositivo. Questo valore non costituisce verifica di compatibilità con sistemi precedenti.

`App/KartTimingAppApp.swift` sceglie la root in base alla sessione. `HomeView` presenta:

| Accesso | Navigazione |
| --- | --- |
| Sessione normale | Home, Eventi, Timing, Impostazioni; Analisi è esclusa per il ruolo esatto `race_director`, ma disponibile per user/admin. |
| Sessione ospite | Solo Timing dentro NavigationStack, senza barra delle schede. |

L'ospite non usa un WebSocket anonimo: `LoginView` autentica l'account viewer predefinito e imposta `isGuestSession`. La sessione viewer non viene ripristinata automaticamente al successivo avvio: `AuthState` rimuove i relativi token salvati.

I ruoli sono `viewer`, `user`, `race_director`, `admin`. Il leader team è un attributo dell'iscrizione. La UI personalizza visibilità e navigazione, ma il server deve autorizzare ogni operazione protetta.

## 2. Ambiente, autenticazione e rete

### Endpoint e discovery

`AppEnvironment` contiene il `productionBaseURL` HTTPS e la modalità sviluppo. Host/porta locali selezionati sono persistiti in UserDefaults; `ServerBrowser` cerca servizi Bonjour `_karttiming._tcp.local.`. I `DiscoveredServer` costruiscono endpoint REST e WebSocket coerenti con TLS/ambiente.

L'accesso remoto usa l'endpoint configurato per Tailscale Funnel, non una scoperta automatica su Internet. La configurazione locale può usare HTTP/WS sulla rete di sviluppo. Il backend deve essere avviato e raggiungibile; il client non avvia il server né il tunnel.

### Sessione

`AuthService` invia le richieste di autenticazione. `AuthState` conserva lo stato osservabile e coordina rinnovo token, profilo/avatar e logout; `KeychainService` conserva access e refresh token. Il JWT viene decodificato localmente per la UI, senza verificarne la firma: la verifica autorevole e il controllo del ruolo corrente avvengono sul backend.

Il rinnovo protegge dall'applicazione di risposte appartenenti a una sessione precedente tramite un identificatore di generazione. Un refresh rifiutato provoca logout; un errore di rete non viene necessariamente interpretato come revoca delle credenziali. Il logout elimina subito i token locali e tenta la revoca server del refresh.

### `NetworkService`

Il servizio HTTP condiviso è un actor in `Services/NetworkService.swift`:

- Dopo una risposta 401 tenta un refresh condiviso fra chiamate concorrenti e ripete la richiesta con il nuovo token; esclude login/register/refresh da questa intercettazione.
- Offre cache GET **opzionale**, con durata scelta dal chiamante, chiave URL/header (inclusa Authorization), deduplicazione delle richieste in corso e invalidazione sulle mutazioni.
- Offre un'interfaccia callback per le chiamate legacy e la funzione `BackgroundJSON.decode` per il decoding fuori dal main actor.

Non tutte le chiamate passano da questo servizio: ad esempio `PDFBrowser` usa direttamente URLSession, quindi non beneficia di quel retry automatico su 401. Non c'è una cache offline completa né una garanzia di replay sicuro per tutte le mutazioni.

## 3. Eventi, partecipazione e liberatorie

`EventsViewModel` e le viste in `Features/Events/` gestiscono elenco, dettaglio, form, iscrizioni e strumenti organizzatore. `EventRootView` e `AdminManageEventView` completano i percorsi di navigazione/gestione.

| Flusso | Implementazione e comportamento |
| --- | --- |
| Iscrizione individuale | Richiesta al backend; visualizzazione `pending_payment`, `waitlist` o `confirmed`. |
| Iscrizione team | Nome, leader e membri identificati da email; backend verifica dimensione e duplicati. Inserire un'email non invia un invito email. |
| Modifica/uscita team | Modifica del leader e operazione separata di uscita del membro; i controlli server decidono la validità. |
| Gestione organizzatore | Code, ammissione, conferma/revoca, rimozione, aggiunta iscritti e assegnazione team. |
| Pagamento | `PaymentInfoSheetView` mostra informazioni; non processa transazioni. |
| Firma | `ReleaseFormSignView` e `SignaturePadView` raccolgono dati e immagine della firma con PencilKit. |
| Amministrazione firme | Consultazione/rimozione e PDF tramite endpoint admin, anche se le viste hanno nomi organizzativi generici. |
| Import risultati | `UploadResultsView` e funzioni live inviano CSV; il backend permette import/rimozione ufficiali solo agli admin. |

Stato iscrizione, firma e stato evento sono separati. La firma disegnata non è una firma crittografica. L'inizio organizzativo dell'evento può rimuovere le iscrizioni non confermate; l'avvio del turno e dei timer è un altro comando.

## 4. Notifiche in-app

`UserHomeViewModel`, `AppNotification` e `NotificationsPanelView` gestiscono la casella persistente fornita dal backend: non è implementato push APNs. L'interfaccia mostra lette/non lette, consente marcatura e cancellazione e apre l'evento associato.

`HomeView` riceve `OpenEventDetail`, seleziona Eventi e trasferisce l'ID attraverso `AppEnvironment.pendingEventIdToOpen`. Il backend produce anche promemoria una tantum per eventi futuri entro sette giorni, per iscrizioni confirmed/pending_payment; cancellare il messaggio non riabilita il promemoria persistente.

## 5. Timing e aggiornamenti live

### `KartTimingManager`

La connessione usa `/ws?token=<access_token>`. Dopo l'apertura richiede `get_status`; selezione sorgente con `set_url` e sottoscrizione evento con `subscribe_event` restano indipendenti.

Il manager riceve `timing_update`, `status`, `url_changed`, `error` ed `event_update`. Mantiene connessione, sorgente e ultimo timing come stati distinti. Ignora callback di socket sostituiti, usa un timeout iniziale di 15 secondi e un heartbeat con ping dopo 5 secondi e timeout di ulteriori 5 secondi. Il timer di connessione non certifica che la pagina del provider sia aggiornata.

Alla chiusura 4401 tenta il refresh e la riconnessione, ripristinando sorgente/evento attraverso `reconnect`. Gli errori generici portano allo stato disconnesso; non va attribuita al manager una strategia universale di retry con backoff. Alcuni percorsi conservano l'ultimo timing per la visualizzazione, che non equivale a dati freschi.

### `LiveViewModel`

Le viste live leggono kart, penalità, messaggi, risultati e stato evento tramite REST. Il view model:

- Accorpa i refresh concorrenti e ignora risposte di una generazione precedente quando cambia evento/sessione.
- Riceve invalidazioni generiche con debounce di 150 ms e aggiornamenti mirati pit/messaggi/penalità.
- Usa `X-Request-ID` per riconoscere le proprie invalidazioni ed evitare refresh duplicati; il backend non usa l'ID come deduplicazione della mutazione.
- Aggiorna lo stato autorevole dopo le mutazioni e gestisce separatamente risorse e cache dei tipi di penalità.
- Mantiene indici delle penalità per kart e relativi totali, evitando di ricalcolarli in ogni vista.

Il nome `startPolling()` è rimasto per compatibilità: il metodo esegue un fetch iniziale; il vecchio ciclo di polling continuo è stato rimosso da questo view model. Gli aggiornamenti successivi dipendono dalle invalidazioni e dalle azioni di refresh.

### Viste

`TimingView`/`TimingPilotView` rappresentano la tabella della sorgente. `LiveRootView` e le viste Director/User aggiungono il contesto dell'evento: assegnazioni, pit wall, messaggi, penalità e dati del proprio kart/team.

`GestioneLiveView`, `ClassificaLiveView`, `AssegnazioneKartView`, `PitWallLiveView` e `DirectorMessaggiView` offrono i controlli organizzatore. `PilotLiveView`, `TeamLiveView` e `UserMessaggiView` mostrano il contesto partecipante.

## 6. «Inizia Turno», bandiere e timer

Il pulsante visualizzato in `GestioneLiveView` è **«Inizia Turno»**. Invia `message_type=custom`, `text="Turno Iniziato"`, `target_kart=nil`: non invia `green_flag`.

| Azione | Effetto backend attuale |
| --- | --- |
| Inizia Turno | Stato `running`, kart assegnati fuori pit, stint azzerati e riavviati, marker penalità resettato. |
| Bandiera rossa | Stato `stopped`, stint congelati mantenendo il tempo trascorso. |
| Bandiera a scacchi | Stesso effetto della rossa sullo stato turno e sugli stint. |
| Bandiera verde dopo stop | Il messaggio è registrato, ma non riavvia i timer. Serve Inizia Turno. |
| Ingresso/uscita pit | Ingresso congela; uscita inizia un nuovo stint, che avanza solo con turno running. |

Il limite stint è valutato sul backend anche con app chiusa. Il telefono visualizza secondi accumulati e timestamp; non è responsabile dell'emissione della penalità automatica. Le selezioni locali di cambio pilota presenti nei modelli non costituiscono uno storico server completo dei turni individuali.

**Discrepanza UI ancora presente:** `LiveViewModel.syncRaceTimesFromMessages` ricava `raceEndTime` soltanto da `checkered_flag`, mentre la rossa ora ferma anche il backend. Il cronometro complessivo derivato dai messaggi non è quindi completamente allineato alla nuova semantica; non va confuso con i timer stint persistiti. La vista gestione mostra comunque «Inizia Turno» dopo la rossa tramite il controllo della bandiera corrente.

## 7. Analisi e risultati

La sezione Analisi è implementata, non è più un placeholder. `AnalisiViewModel`, `AnalisiView`, `EventResultModels` e `ClassificationPDFGenerator` supportano:

- Storico risultati e iscrizioni dell'utente; percorsi amministrativi per consultare altri utenti autorizzati.
- Classifiche evento e penalità, con associazioni account/team quando disponibili.
- Statistiche giri per kart fornite dal backend e grafici Swift Charts dei dati disponibili.
- Risultati personali dei circuiti e generazione di una classifica PDF sul dispositivo.

Le statistiche non costituiscono telemetria completa: il backend salva giri osservati durante l'acquisizione e filtra quelli oltre il 150% del best nel calcolo media/worst. Dati assenti o mancanti associazioni non devono essere interpretati come valori zero o risultati ufficiali.

Il metodo client `selfDeclareResult` invia un POST a `/events/{eventId}/results/me/best_lap`, ma il router backend corrente non registra quella route. La funzione non può essere considerata completa end-to-end. Il POST per dichiarare un risultato personale circuito esiste invece in `kartodromi/router.py`.

Le classifiche ufficiali rimangono nel database dopo chiusura app e riavvio backend. Un nuovo CSV valido sostituisce tutti gli ufficiali dell'evento, indipendentemente dal tipo di sessione; la scadenza del PDF non cancella la classifica.

## 8. PDF nel browser

Nonostante il nome del file, `Features/Events/PDFViewer.swift` contiene `PDFBrowser`, non un visualizzatore PDF incorporato:

1. Riceve i byte PDF, prodotti sul client per le classifiche oppure ottenuti dai servizi documentali.
2. Li invia con autenticazione a `POST /documents/pdf`.
3. Decodifica il percorso temporaneo restituito e lo apre con `UIApplication.shared.open` nel browser.

Il backend accetta al massimo **10 MiB (10.485.760 byte)**. Il link dura **un'ora dal salvataggio** e non richiede autenticazione al download: il possesso del link consente la consultazione fino alla scadenza. Riaprire il link non prolunga la durata. Occorre ripubblicare il documento per ottenere un nuovo link valido.

I risultati e le firme nel DB sono indipendenti dalla copia temporanea. L'upload del PDF usa direttamente URLSession; un token scaduto può produrre un errore di preparazione anziché attivare il retry di `NetworkService`.

## 9. Velocità GPS

`Services/GPSSpeedMonitor.swift` usa CoreLocation mentre la vista pilota è attiva, con richiesta di autorizzazione when-in-use. Converte la velocità da m/s a km/h, scarta campioni con età superiore a 5 secondi o accuratezza orizzontale oltre 50 m e gestisce permessi negati/errori.

È una misura locale del telefono. Non invia posizione/velocità al backend e non sostituisce i tempi ufficiali del provider. Su simulatore o senza campioni validi mostra uno stato di attesa/indisponibilità.

## 10. Mappa delle directory

| Directory/file | Contenuto |
| --- | --- |
| `App/` | Entrypoint e ambiente di esecuzione/navigazione. |
| `Auth/` | Servizi auth, stato globale, Keychain e schermata login/registrazione/ospite. |
| `Services/` | HTTP, decoding, Bonjour e GPS; non esiste una directory `Network/`. |
| `Models/` | DTO condivisi, ruolo e decodifica JWT per UI. |
| `Features/Home/` | Home, dashboard, notifiche. |
| `Features/Events/` | Eventi, iscrizioni/team, firme, gestione organizzatore, CSV e browser PDF. |
| `Features/Timing/` | Manager WebSocket e viste timing. |
| `Features/Live/` | Coordinamento live, modelli, viste Director/User e pit wall. |
| `Features/Analisi/` | Storico, grafici, statistiche e generazione PDF. |
| `Features/Admin/` | Utenti, ruoli, circuiti e analisi amministrativa. |
| `Features/Settings/` | Profilo, password, logout, ambiente e configurazione penalità (`GestionePenalitaView`). |
| `UI/`, `Assets.xcassets`, `Info.plist` | Tema, risorse grafiche e permessi/configurazione app. |

## 11. Verifiche e limiti

La suite originale di **69 test backend** continua a passare. La verifica DD/RASD estesa conta **94 test: 90 superati e 4 falliti**; vedere il [report](../../project_tests/TEST_REPORT.md) per difetti e limiti. I test sono ora in `project_tests/` nella root. Non sono stati eseguiti test UI, build o collaudi GPS/browser su dispositivo.

Restano da riconciliare il cronometro derivato dopo rossa, l'autodichiarazione giro evento e alcune differenze di permesso: `UserRole.canChangeURL` consente solo director/admin mentre il backend permette la selezione della propria sorgente da viewer in su. Le restrizioni guest di navigazione non dimostrano una restrizione equivalente su ogni endpoint.

Non sono implementati pagamenti, inviti email, push APNs, client Android/web completo o modalità offline completa. I grafici esistenti e la misura GPS locale non implicano un sistema di telemetria remota.
