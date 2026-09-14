# Revisione rispetto a write-swift.md

Data: 14 settembre 2026. Riferimento: [write-swift.md](write-swift.md).
Analisi statica del client Swift, della configurazione Xcode e dei percorsi asincroni.
Non sono stati modificati sorgenti, impostazioni o test dell'app.

## Compatibilità del riferimento

Il documento dichiara una baseline 6.3 e cita funzionalità future 6.4. La toolchain
locale restituisce **Apple Swift 6.2.1**. Il target usa `SWIFT_VERSION = 5.0`, con
`SWIFT_APPROACHABLE_CONCURRENCY = YES` e `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
in Debug e Release. Compilatore e modalità del linguaggio sono due cose diverse.
Non consideriamo difetti l'assenza di API 6.3/6.4, né proponiamo di introdurle senza
aggiornare e verificare la toolchain. Il documento è il criterio richiesto per la
revisione, non una verifica indipendente di tutte le sue affermazioni sulle release.

## Criticità funzionali

Aggiornamento: SW01–SW04 implementati. Generazione della sessione controllata dopo
il refresh; logout solo per rifiuto 401 del refresh, credenziali conservate per errori
transitori. Generazione e cancellazione controllate nei tipi penalità; caricamento
iniziale con `.task`. Timer blu/drop-position cancellabili e annullati all'uscita.
Verifica di compilazione iOS Simulator; gli interleaving e il recupero rete devono
ancora essere provati con test Swift dedicati. Le descrizioni sotto sono storiche.


- [x] **SW01 — Alta: una risposta di refresh può sovrascrivere una sessione successiva.**
  **Documento:** §3, reentrancy e assunzioni dopo `await`; §5, lifetime dei task.
  **Codice:** `Auth/AuthState.swift`, `handleTokenExpiryWithReturn` (circa 54–70),
  `logout` e `setLoginData`.
  Dopo `await AuthService.refreshToken(...)`, il metodo salva sempre il token e
  aggiorna `currentUser`. Non verifica che l'utente sia ancora nella stessa sessione.
  **Scenario:** parte un refresh, poi avviene logout o login con un altro account;
  la vecchia risposta arriva dopo e riscrive il Keychain/utente. Il ramo di errore
  può invece eseguire logout sulla nuova sessione. Non viene necessariamente
  ripristinato `isLoggedIn`: il rischio comprende uno stato internamente incoerente.
  **Proposta:** identificativo di generazione della sessione, invalidato su logout/login,
  controllo prima di applicare successo o errore e gestione del task di refresh.
  **Test:** risposta differita, logout/login nel frattempo, completamento tardivo.
  **Evidenza:** percorso statico; interleaving da riprodurre con rete simulata.

- [x] **SW02 — Media: un errore transitorio del refresh causa logout definitivo.**
  **Documento:** §2, errori recuperabili con contesto sufficiente.
  **Codice:** `Auth/AuthState.swift`, catch di `handleTokenExpiryWithReturn`;
  `Auth/AuthService.swift`, `refreshToken`.
  Timeout, assenza rete e risposta del server temporaneamente fallita terminano
  tutti in `logout()`, che elimina access e refresh token dal Keychain.
  **Scenario:** access token scaduto durante una breve interruzione di rete;
  l'utente deve autenticarsi nuovamente pur avendo un refresh potenzialmente valido.
  **Proposta:** distinguere credenziali rifiutate da errori di trasporto/server;
  conservare la sessione recuperabile e offrire retry, senza invii automatici infiniti.
  **Test:** offline/timeout/500 non cancellano il refresh; rifiuto definitivo sì.
  **Evidenza:** percorso statico, non simulato in questa revisione.

- [x] **SW03 — Media: il caricamento/salvataggio dei tipi penalità non protegge i risultati tardivi.**
  **Documento:** §3 e §5, cancellazione e validità dello stato dopo sospensione.
  **Codice:** `Features/Live/LiveViewModel.swift`, `fetchPenaltyTypesOnly`,
  `updatePenaltyType`, `configure` e `stopPolling`; `GestionePenalitaView.onAppear`.
  Questi due metodi pubblicano il risultato dopo la rete senza confrontare
  `generation`, mentre `fetchSnapshot` e altre mutazioni live lo fanno già.
  Il Task aperto dalla vista non viene conservato e `stopPolling` non lo cancella.
  **Scenario:** uscita/riapertura o riconfigurazione dello stesso modello con altro
  server/account mentre la richiesta è in corso; i vecchi dati possono finire nel
  contesto nuovo. Il guard `isLoadingPenaltyTypes` può anche impedire il nuovo fetch.
  **Proposta:** portare su questo percorso la protezione già presente negli snapshot;
  associare il caricamento al lifecycle della vista e trattare la cancellazione separatamente.
  **Test:** completare A dopo la configurazione B; solo B deve aggiornare lo stato.
  **Evidenza:** rischio statico; non affermiamo che ogni chiusura della vista lo provochi.

- [x] **SW04 — Media: timer precedenti possono nascondere avvisi live più recenti.**
  **Documento:** §5, gestione esplicita del lavoro non strutturato.
  **Codice:** `Features/Live/User/PilotLiveView.swift`, `checkForNewBlueFlags` e
  `checkForNewDropPosition` (circa righe 543–574).
  Ogni avviso pianifica un `DispatchQueue.main.asyncAfter` che pone il medesimo Bool
  a false, senza identificare l'avviso corrente o cancellare il timer precedente.
  **Scenario:** bandiera blu A, poi B dopo 4 secondi; il timer di A nasconde B dopo
  circa un secondo invece di lasciarla visibile per il suo intervallo.
  Il nuovo flash cancellabile non copre questi timer, che sono percorsi distinti.
  **Proposta:** task cancellabile per avviso o scadenza/ID confrontati nel callback.
  **Test:** avvisi ravvicinati, cambio evento e uscita dalla vista.
  **Evidenza:** sequenza dedotta direttamente dai callback; prova UI ancora necessaria.

## Robustezza e manutenzione

- [ ] **SW05 — Media: completare la migrazione alla verifica di concorrenza Swift 6.**
  **Documento:** §4 e §16.
  **Codice:** `KartTimingApp.xcodeproj/project.pbxproj`, righe circa 289–294 e 325–330.
  MainActor di default e Approachable Concurrency sono già attivi, ma il target
  resta in modalità Swift 5; `SWIFT_STRICT_CONCURRENCY` non è esplicitato nel file.
  **Impatto:** non si può equiparare una build riuscita alla garanzia della modalità
  Swift 6. Questo non dimostra di per sé una data race.
  **Proposta:** esaminare le impostazioni effettive, abilitare checking completo,
  correggere i diagnostici, poi passare a Swift 6 in una modifica separata dai refactor.

- [ ] **SW06 — Media: il wrapper callback non espone la cancellazione dell'operazione.**
  **Documento:** §5 e §8.
  **Codice:** `Services/NetworkService.swift`, `NetworkTask` e `dataTask` (circa 78–98).
  `dataTask` avvia immediatamente un Task, ne perde l'handle e restituisce un oggetto
  con `resume()` vuoto. Non è una URLSessionDataTask e non offre `cancel()`.
  **Impatto:** il chiamante non può gestire il lifetime tramite l'oggetto restituito;
  il nome suggerisce semantica di avvio che non corrisponde al comportamento reale.
  **Proposta:** migrazione incrementale ad async/await o handle con contratto esplicito.
  Per richieste cache condivise, separare la cancellazione del singolo consumer da
  quella dell'operazione comune: cancellare indiscriminatamente romperebbe altri consumer.

- [ ] **SW07 — Media: manca una suite di test del client Swift.**
  **Documento:** §11.
  **Evidenza:** nessun file test Swift individuato e un solo target application nel
  progetto ispezionato. I test Python verificano il backend, non actor reentrancy,
  lifecycle SwiftUI, retry client o decodifica dei modelli iOS.
  **Proposta:** target Swift Testing per nuovi test di logica; XCTest UI solo dove
  serve guidare l'interfaccia. Partire da SW01–SW04, cache/retry e decodifica.
  Non è necessaria una migrazione dei test Python a Swift: coprono un livello diverso.

- [ ] **SW08 — Bassa: sostituire gradualmente print con logging strutturato.**
  **Documento:** §13.
  **Codice:** `Auth/AuthState.swift:68`, `Services/ServerBrowser.swift:31,38,72`,
  diversi rami errore in `Features/Events/EventsViewModel.swift`.
  **Impatto:** livelli, correlazione e trattamento della privacy non sono espliciti.
  **Proposta:** `Logger` con categorie auth/network/live e ID delle operazioni;
  nessun token o dato personale reso pubblico per comodità di debug.

## Aspetti già coerenti

- I DTO sono principalmente struct/enum; i view model hanno identità condivisa e
  il loro uso di class è motivato (§1). Non convertirli automaticamente in struct.
- `NetworkService` isola cache e richieste pendenti in un actor e usa generazioni/ID
  per non ripopolare cache invalidata (§3). L'actor ha uno scopo concreto.
- `LiveViewModel.fetchSnapshot` usa un numero fisso di `async let`, verifica la
  generazione dopo le sospensioni e pubblica lo snapshot in modo coordinato (§3–5).
- `BackgroundJSON` e il decoder snapshot separano esplicitamente il lavoro di
  decodifica con `@concurrent`. La necessità prestazionale va profilata, non indovinata.
- Il flash delle bandiere usa ora un Task conservato e cancellabile (§5).
- Le annotazioni `@MainActor` esplicite, anche dove ridondanti, non sono un bug.
- L'uso di `ObservableObject`/Combine rispetto a `@Observable` è un'opportunità di
  modernizzazione (§15), non una correzione urgente né una migrazione da fare alla cieca:
  il progetto usa publisher e cancellables che vanno considerati.

## Limiti e ordine suggerito

Priorità: SW01, poi SW02–SW04. Predisporre test Swift e affrontare il checking
Swift 6 come passaggio separato. Logging e modernizzazione possono seguire.

Non sono stati eseguiti nuovi build, test Swift, Instruments, Thread Sanitizer o
Memory Graph in questa revisione. Non si attribuiscono crash o rallentamenti a
pattern di codice senza riproduzione/profilazione. Non sono stati riscontrati motivi
per introdurre macro, puntatori, Span, InlineArray o nuove gerarchie di protocolli.
La copertura si concentra su autenticazione, rete, modello live e lifecycle delle
viste citate; non certifica l'assenza di problemi in ogni file del progetto.
