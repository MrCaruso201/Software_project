# Checklist problemi di implementazione

Revisione del 14 settembre 2026 sul codice presente nel workspace.

Analizzati: autenticazione REST/WebSocket, eventi, importazione risultati e statistiche,
assegnazioni e messaggi live, configurazione penalità e relativo flusso iOS di rete.
Questa è una revisione mirata, non una certificazione completa del progetto.
Non sono stati modificati codice applicativo o database durante la revisione.

Priorità: **P1** = accessi non autorizzati, perdita dati o stato gara errato;
**P2** = malfunzionamento funzionale o gestione risorse da correggere.
Le caselle indicano correzioni ancora da effettuare, non verifiche già superate.

## Accessi e integrità dei dati

**Aggiornamento:** R01–R03 corretti. Le descrizioni sotto documentano i problemi
originari. Le scritture eventi richiedono race director/admin; il CSV viene preparato
prima della sostituzione e viene rifiutato se non contiene risultati validi (resta
ammessa l'importazione parziale con segnalazione errori). Le API rileggono account e
ruolo dal DB. I WebSocket rivalidano prima dei comandi e durante l'inattività ogni
5 secondi, chiudendo le connessioni con account eliminato o token scaduto.
Verifica: test HTTP tramite ASGI e test dei gestori su SQLite in memoria in
`python_scraper_server/tests/test_access_integrity.py`. Nessun DB reale utilizzato.


- [x] **R01 — P1: proteggere le API di scrittura degli eventi.**
  **Evidenza:** `create_event`, `update_event` e `delete_event` in
  [events/router.py](python_scraper_server/events/router.py) (righe 98, 145, 195)
  dipendono soltanto dal database; non richiedono autenticazione o ruolo.
  Né il router né la sua inclusione in `main.py` applicano una protezione globale.
  **Conseguenza:** chi raggiunge il server può creare, modificare o eliminare eventi
  senza token, indipendentemente dai controlli mostrati nell'app.
  **Verifica da aggiungere:** richieste anonime e con ruolo viewer devono essere
  rifiutate; i ruoli autorizzati devono continuare a funzionare.
  **Stato della verifica:** controllo statico delle dipendenze; nessuna richiesta
  di scrittura inviata al server reale.

- [x] **R02 — P1: evitare di cancellare la classifica quando il CSV non contiene risultati validi.**
  **Evidenza:** [results/router.py](python_scraper_server/results/router.py),
  `import_results_from_csv`, elimina i risultati ufficiali prima di validare le righe
  (circa riga 246) e fa commit anche quando `imported == 0` (circa riga 417).
  **Scenario:** esiste una classifica; si importa un file con sole intestazioni,
  oppure con tutte le posizioni non valide. La precedente classifica viene cancellata
  e la risposta restituisce zero risultati importati.
  **Correzione da valutare:** validare il contenuto prima della sostituzione e definire
  esplicitamente la politica per importazioni parzialmente valide.
  **Verifica da aggiungere:** un CSV senza righe valide deve lasciare intatta la classifica.
  **Stato della verifica:** analisi statica del flusso e della transazione.

- [x] **R03 — P1: applicare revoca account e cambi di ruolo ai token già emessi.**
  **Evidenza:** [auth/dependencies.py](python_scraper_server/auth/dependencies.py),
  `get_current_user` e `require_role`, verificano il JWT e usano il ruolo contenuto
  nel token senza rileggere l'utente. `update_role` in
  [auth/admin_router.py](python_scraper_server/auth/admin_router.py) aggiorna il DB;
  `delete_account` in [auth/router.py](python_scraper_server/auth/router.py) elimina
  l'utente, ma questi cambiamenti non invalidano il suo access token.
  **Scenario:** un amministratore viene declassato; con il vecchio token può ancora
  chiamare gli endpoint protetti dal precedente ruolo fino alla scadenza.
  Anche un account eliminato supera ancora il controllo JWT sugli endpoint che
  non verificano autonomamente l'esistenza dell'utente.
  **Verifica da aggiungere:** dopo declassamento/eliminazione il precedente token
  non deve mantenere i vecchi privilegi. Considerare anche le connessioni WebSocket.
  **Stato della verifica:** analisi statica; nessun account reale modificato.

## Live timing e connessioni

- [x] **R04 — P1: impedire che un messaggio destinato a un kart cambi i timer di tutti.**
  **Corretto:** il server rifiuta con HTTP 400 rosso/verde/scacchi e i comandi custom
  di inizio turno se `target_kart` è presente, prima di salvare messaggi o modificare
  timer. I broadcast e i messaggi informativi mirati restano supportati.
  Verificato in `tests/test_live_message_scope.py`; suite completa: 22 test superati.
  La descrizione seguente documenta il difetto originario.
  **Evidenza:** `send_message` in [live/router.py](python_scraper_server/live/router.py)
  salva `target_kart`, ma applica le transizioni rosso/verde/scacchi e il comando
  custom di inizio turno a tutti i kart senza verificare che il messaggio sia globale
  (circa righe 660–710).
  **Scenario API:** inviare `red_flag` con `target_kart: 7` ferma tutti i timer e mette
  l'evento in pausa. Analogamente, un messaggio custom `Turno Iniziato` rivolto a un
  singolo kart azzera tutti gli stint. I client ricostruiscono invece lo stato della
  gara dai soli messaggi broadcast, creando disallineamento col server.
  **Verifica da aggiungere:** un messaggio mirato non deve mutare lo stato globale;
  in alternativa, rifiutare esplicitamente queste combinazioni di tipo e destinatario.
  **Stato della verifica:** analisi statica server/client; scenario API da eseguire in isolamento.

- [x] **R05 — P2: rilasciare lo scraper anche quando fallisce un invio WebSocket.**
  **Corretto:** entrambi i broadcast chiamano `unsubscribe_client` in caso di errore.
  Test aggiunti in `tests/test_ws_manager.py`: rilascio e avvio del periodo di grazia
  una sola volta, conservazione degli altri client e gestione dei client iscritti
  soltanto a un evento. Suite completa: 19 test superati su risorse isolate.
  La descrizione seguente documenta il difetto originario.
  **Evidenza:** `broadcast_to_url` e `broadcast_to_event` in
  [ws/manager.py](python_scraper_server/ws/manager.py) eliminano direttamente
  `client_url`/`client_event` nel ramo di errore senza chiamare `unsubscribe_client`.
  Quest'ultima non può più decrementare il contatore quando l'URL è già stato rimosso.
  **Conseguenza:** `subscriber_count` può restare maggiore di zero senza client reali;
  il periodo di grazia in [scraper/session.py](python_scraper_server/scraper/session.py)
  non parte e lo scraper può occupare browser e uno slot sessione inutilmente.
  **Verifica da aggiungere:** simulare `send_text` che solleva un errore e controllare
  che mappe e contatore siano ripuliti una sola volta, anche alla successiva disconnessione.
  **Stato della verifica:** analisi statica del percorso di rilascio.

- [x] **R06 — P2: garantire la pulizia WebSocket anche per messaggi malformati.**
  **Corretto:** JSON e campi dei comandi vengono validati con risposta di errore;
  il client può inviare un comando valido successivo. Un blocco `finally` rilascia
  le sottoscrizioni anche per errori inattesi, cancellazione e revoca del token.
  Test in `tests/test_ws_router.py`: input malformati, recupero, errori di invio/ricezione
  e cancellazione. Suite completa: 26 test superati.
  La descrizione seguente documenta il difetto originario.
  **Evidenza:** [ws/router.py](python_scraper_server/ws/router.py) esegue `json.loads`,
  `.get` e `.strip` sugli input; intercetta soltanto `WebSocketDisconnect` e non ha
  un `finally` che richiami `unsubscribe_client`.
  **Scenario:** dopo l'iscrizione a una sorgente, inviare JSON non valido, un array
  invece di un oggetto o un URL non stringa. L'eccezione termina il gestore senza
  passare dalla normale pulizia delle sottoscrizioni.
  **Verifica da aggiungere:** input malformati devono produrre un errore controllato
  o una chiusura con rilascio completo delle risorse.
  **Stato della verifica:** analisi statica; nessun messaggio inviato a connessioni reali.

## Penalità e client iOS

- [x] **R07 — P2: validare anche i secondi delle penalità.**
  **Corretto:** secondi interi >= 0 validati nelle API di configurazione e assegnazione,
  con controllo nei due form iOS. Zero resta ammesso; dati storici non modificati.
  Suite: 28 test superati; controllo sintattico Swift superato.
  La descrizione seguente documenta il difetto originario.
  **Evidenza:** `PenaltyTypeUpdate.default_seconds` e `PenaltyCreate.seconds` in
  [live/schemas.py](python_scraper_server/live/schemas.py) sono interi opzionali
  senza limite inferiore. Il vincolo introdotto per `warning_threshold` non li copre.
  **Conseguenza:** è possibile configurare o assegnare una penalità di -10 secondi;
  il totale per kart somma quel valore e quindi diminuisce.
  **Verifica eseguita:** istanziati entrambi i modelli con -10; entrambi accettano il
  valore. Nessun accesso al database. Decidere se zero è ammesso, mantenendo distinti
  i secondi di penalità dalla soglia avvisi, che richiede almeno 1.
  **Verifica da aggiungere:** rifiuto API e messaggio comprensibile nel form iOS.

- [x] **R08 — P2: usare il rinnovo token anche nel salvataggio dei tipi di penalità.**
  **Corretto:** `updatePenaltyType` usa ora `NetworkService.shared.data(for:)`,
  che rinnova il token su HTTP 401 e ripete la richiesta con il nuovo token.
  Controllo sintattico Swift superato; rinnovo reale da verificare su app/server.
  La descrizione seguente documenta il difetto originario.
  **Evidenza:** `updatePenaltyType` in
  [LiveViewModel.swift](client_ios_app/KartTimingApp/KartTimingApp/Features/Live/LiveViewModel.swift)
  (circa riga 394) usa `URLSession.shared.data` direttamente, mentre
  [NetworkService.swift](client_ios_app/KartTimingApp/KartTimingApp/Services/NetworkService.swift)
  gestisce il refresh e il retry su 401.
  **Scenario:** lasciare aperta Gestione Penalità fino alla scadenza dell'access token,
  quindi salvare. Il salvataggio fallisce anche se il refresh token è ancora valido.
  Il modello conserva inoltre il token fornito alla configurazione iniziale.
  **Verifica da aggiungere:** access token scaduto e refresh valido devono permettere
  il salvataggio attraverso il normale meccanismo di rinnovo.
  **Stato della verifica:** confronto statico dei percorsi di rete; non eseguito su iOS.

- [ ] **R09 — P2: mostrare e consentire il recupero dagli errori di caricamento delle penalità.**
  **Evidenza:** `fetchPenaltyTypesOnly` e `fetchRawData` in
  [LiveViewModel.swift](client_ios_app/KartTimingApp/KartTimingApp/Features/Live/LiveViewModel.swift)
  ignorano errori HTTP, rete e decodifica; la vista
  [GestionePenalitaView.swift](client_ios_app/KartTimingApp/KartTimingApp/Features/Settings/GestionePenalitaView.swift)
  mostra il caricamento ogni volta che `penaltyTypes.isEmpty`.
  **Scenario:** aprire la pagina col server irraggiungibile o con risposta non valida:
  rimane “Caricamento tipi penalità...” senza errore né comando per riprovare.
  Anche una lista legittimamente vuota è indistinguibile da un caricamento in corso.
  **Verifica da aggiungere:** distinguere caricamento, lista vuota ed errore; provare
  un errore iniziale seguito da un tentativo riuscito.
  **Stato della verifica:** analisi statica; non eseguito su simulatore.

## Statistiche

- [ ] **R10 — P2: eliminare l'ambiguità dell'endpoint statistiche giri duplicato.**
  **Evidenza:** [results/router.py](python_scraper_server/results/router.py) registra
  due GET `/events/{event_id}/lap-stats`, alle righe 152 e 443.
  Il primo calcola la soglia del 150% sul miglior giro di ciascun kart;
  il secondo usa il miglior giro assoluto dell'evento e una query aggregata.
  **Conseguenza:** le richieste HTTP raggiungono la prima route; la seconda non la
  sostituisce, anche se la funzione Python ha lo stesso nome. Una modifica o un test
  diretto della seconda funzione può quindi non corrispondere al comportamento HTTP.
  La registrazione produce anche un Operation ID duplicato nella documentazione API.
  **Verifica eseguita:** scansione AST dei router conferma la coppia metodo/percorso
  duplicata. Le due strategie di calcolo sono state confrontate nel sorgente.
  **Verifica da aggiungere:** scegliere la regola desiderata e verificare il risultato
  via HTTP usando kart con migliori giri sensibilmente diversi.

## Vincoli e limiti della revisione

- Il reset degli stint con “Inizia Turno” dopo bandiera rossa è una regola approvata:
  non è segnalato come problema. R04 riguarda invece il destinatario del messaggio.
- Le correzioni già completate su persistenza impostazioni, secondi automatici stint,
  migrazione Track Limits, sincronizzazione form e soglia positiva non sono riproposte.
- Nessun server avviato, nessuna migrazione eseguita, nessun test contro il DB reale.
  Non è stata eseguita una build iOS o una prova end-to-end.
- Scraper dei singoli provider, simulatore, PDF e tutti i casi limite delle iscrizioni
  richiedono un ulteriore passaggio dedicato; non sono coperti in modo esaustivo.
