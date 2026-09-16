# Race Manager — Backend Python

Aggiornamento: 16 settembre 2026. Descrizione dell'implementazione corrente, verificata sui router, modelli, monitor e test. Per la mappa dei componenti vedere [ARCHITECTURE.md](../ARCHITECTURE.md); per il comportamento del client vedere [documentazione iOS](../client_ios_app/KartTimingApp/DOCUMENTATION.md).

## 1. Avvio e configurazione

Dalla directory `python_scraper_server`, con un ambiente Python compatibile con le dipendenze:

```sh
python -m pip install -r requirements.txt
python -m playwright install chromium
```

Impostare `JWT_SECRET` nell'ambiente o nel file `.env` locale prima dell'avvio. `auth/jwt.py` rifiuta di caricarsi se il valore manca. Non versionare il segreto.

```sh
python main.py
```

Uvicorn ascolta su `0.0.0.0:8000`. Il DB è `data/kart_timing.db`; viene inizializzato tramite SQLAlchemy con migrazioni manuali e seed per account di sviluppo, circuiti e tipi di penalità. L'inizializzazione include account predefiniti admin/viewer: il provisioning va rivisto prima di un'esposizione operativa.

Il client ha un endpoint remoto HTTPS configurato per Tailscale Funnel e una modalità locale Bonjour. Il processo Python non configura Funnel né il certificato TLS. La discovery `_karttiming._tcp.local.` viene avviata nel lifespan; non è corretto descrivere il backend come esclusivamente remoto.

Le sessioni scraper e le sottoscrizioni sono process-local: usare il modello a singolo worker per il comportamento documentato. Non è presente un broker condiviso per il deployment multi-worker.

### Lifespan

All'avvio: inizializzazione DB, chiusura eventi già scaduti, pulizia JSON timing, annuncio Bonjour, creazione task promemoria/stint/scadenze. Allo shutdown: cancellazione task, stop sessioni scraper, chiusura discovery e pulizia snapshot. Non vengono cancellate le classifiche persistenti.

## 2. Autenticazione e autorizzazione

- Password: hash bcrypt tramite passlib; non cifratura reversibile.
- Access token: JWT HS256, durata 30 minuti.
- Refresh token: valore casuale, durata 30 giorni, solo hash SHA-256 nel DB. Il refresh emette un nuovo access token; logout revoca il refresh indicato.
- REST: `Authorization: Bearer <access_token>` sulle operazioni protette.
- WebSocket: `/ws?token=<access_token>`, chiusura `4401` per identità non valida. Rivalidazione a ogni comando e ogni 5 secondi di inattività.
- Account e ruolo sono riletti dal DB: il ruolo contenuto in un vecchio JWT non è l'unico riferimento per l'autorizzazione.

Gerarchia: `viewer < user < race_director < admin`. Il leader è una proprietà della partecipazione al team, non un ruolo globale. Direttori e admin possono effettuare operazioni organizzative; import/rimozione classifiche ufficiali, ruoli, circuiti e configurazione tipi di penaltà sono riservati agli admin. Le route liberatorie non hanno guard uniformi: download e rimozione ammettono anche direttori; il download usa il ruolo nel JWT senza rileggere l'account, come dimostrato dai nuovi test falliti.

Il meccanismo `token_version` (colonna aggiunta con migrazione idempotente) garantisce che REST e WebSocket rifiutino token emessi prima di un cambio ruolo o di una cancellazione account: l'account e il ruolo correnti sono riletti dal DB a ogni richiesta autenticata. Il vecchio finding sull'accesso al PDF da parte di identità eliminate/declassate è risolto.

Esistono differenze fra policy desiderata e applicazione attuale: la lista/dettaglio eventi non richiede autenticazione; l'iscrizione richiede un account ma non verifica un ruolo minimo `user`. La sola limitazione guest nella UI non protegge queste API.

## 3. Superficie REST

Le route sotto sono una guida alle famiglie implementate. I payload e le validazioni effettive sono definiti nei rispettivi `schemas.py` e router; FastAPI genera lo schema OpenAPI.

| Modulo | Route rappresentative e operazioni |
| --- | --- |
| `auth` | `POST /auth/register`, `/login`, `/refresh`, `/logout`; `GET/PATCH/DELETE /auth/me`; `POST /auth/me/avatar`, `/auth/change-password`. |
| `admin` | `GET /admin/users`, `/admin/users/search`; `PATCH /admin/users/{user_id}/role`; configurazione, preview, elenco/rimozione firme e PDF sotto `/admin/events/{event_id}/...`. |
| `events` | `GET/POST /events/`, `GET/PATCH/DELETE /events/{event_id}`; registrazioni personali e operazioni individuo/team. |
| `live` | `PATCH /events/{event_id}/status`; `/live/{event_id}/karts`, `/penalties`, `/messages`, `/my-kart`; pit con `PATCH /live/{event_id}/karts/{kart_number}/pit`. |
| Tipi penalità | `GET /live/penalty-types`, `PATCH /live/penalty-types/{type_id}` (modifica admin-only). |
| `results` | `GET /events/results/me`, storico utente autorizzato, classifiche evento/personali, `GET /events/{event_id}/lap-stats`, `POST /events/{event_id}/results/import_csv`, `DELETE /events/{event_id}/results`. |
| `notifications` | `GET/DELETE /notifications/me`, `POST /notifications/{notification_id}/read`, `DELETE /notifications/{notification_id}`. |
| `kartodromi` | CRUD circuiti, elenco completo admin `/kartodromi/tutti`, immagini, storico risultati personali e `POST /kartodromi/{kartodromo_id}/results/me/best_lap`. |
| `documents` | `POST /documents/pdf` per pubblicare byte PDF; `GET /documents/pdf/{filename}` per aprire il link. |

Il router risultati è montato prima del router eventi affinché `/events/results/me` non venga interpretato come un identificatore evento. La presenza di una route in un commento non ne prova l'implementazione: il POST evento `/events/{event_id}/results/me/best_lap`, ancora citato in commenti e nel client, non è registrato nel router attuale.

## 4. Eventi, iscrizioni e team

L'evento contiene date, deadline, costi informativi, limiti di partecipazione/team, durata, limite stint, testo liberatoria e stati. `location` è testo: non esiste una foreign key diretta a `Kartodromo`.

Gli stati di iscrizione sono `pending_payment`, `waitlist`, `confirmed`. Le richieste oltre deadline o capienza vanno in waitlist; un individuo senza team in una gara a squadre attende in lista. Per l'ingresso team la capienza considera le squadre. Il pagamento resta verificato fuori dall'app.

I membri condividono `team_id`, nome e riferimento evento; uno è leader. Si possono inserire email senza account (`user_id` nullable). Non c'è un servizio di invio email né un flusso separato di accettazione inviti. Le notifiche riguardano gli account collegati.

Le operazioni dedicate permettono ammissione dalla waitlist, conferma, revoca conferma, spostamento in waitlist, rimozione e inserimento organizzatore. Non si deve usare un generico cambio stato per aggirare le transizioni dedicate. La cancellazione autonoma di un'iscrizione confermata è bloccata; l'uscita del membro non leader dal team è un'operazione distinta.

Il DB garantisce unicità account/evento per le iscrizioni collegate. Le identità email e la capienza richiedono controlli applicativi: non tutte le regole di ammissione sono vincoli univoci SQL.

### Avvio e scadenza evento

`PATCH /events/{event_id}/status` gestisce il ciclo evento. Nel passaggio a `started` da uno stato diverso, rimuove le iscrizioni non confermate e le relative firme, notifica gli interessati e i confermati e inizializza i timer dei kart assegnati senza avviarli. L'avvio del turno avviene tramite il messaggio custom descritto sotto.

`events/lifecycle.py` porta a `finished` gli eventi scheduled/started almeno 48 ore dopo `event_date`, all'avvio e poi ogni 30 secondi, notificando i client dell'evento. Questa operazione cambia solo `status`: non modifica `race_status`, non congela i timer e non pubblica risultati.

## 5. Turni, bandiere, pit e penalità

`Event.status` e `Event.race_status` sono distinti. La tabella descrive il codice effettivo di `live/router.py`.

| Comando | Stato turno e timer |
| --- | --- |
| `custom`, testo `Turno Iniziato` o `Gara Iniziata` (trim/case-insensitive) | Imposta `running`; per i kart assegnati azzera stint e marker penalità, imposta fuori pit e avvia i timer. |
| `red_flag` | Imposta `stopped`, conserva il tempo accumulato e annulla `stint_last_resume`. |
| `checkered_flag` | Stesso effetto della rossa sullo stato e sui timer. |
| `green_flag` | Se non `stopped`, imposta `running` e riprende i timer dei kart fuori pit senza reset. Se `stopped`, il messaggio viene registrato ma non riavvia il turno. |
| `yellow_flag`, messaggi informativi/custom ordinari | Registra il messaggio senza questa transizione di stato. |
| Ingresso pit | Accumula il tempo attivo, congela il timer e imposta `is_in_pit`. |
| Uscita pit | Azzera lo stint e il marker automatico; avvia il nuovo timer solo se il turno è `running`. |

I comandi globali rosso/verde/scacchi e avvio custom rifiutano `target_kart`, anche se vale zero. I messaggi ordinari possono essere diretti a un kart. `paused` resta uno stato riconosciuto, ma la rossa non lo produce più.

Le assegnazioni hanno un vincolo univoco `(event_id, kart_number)`. I timer usano secondi accumulati e timestamp di ripresa; il limite configurato è in minuti. I record `unassigned` non vengono trattati come kart assegnati per i comandi turno.

### Penalità automatiche

`live/stint_monitor.py` controlla gli stint circa ogni secondo anche senza client connessi. Valuta il limite con tempo backend; in una transazione SQLite `BEGIN IMMEDIATE`, acquisisce il marker `stint_penalty_assessed` e inserisce la penalità. La cancellazione della penalità non azzera il marker: lo stesso stint non viene sanzionato ripetutamente. Uscita pit e nuovo avvio riabilitano la valutazione.

L'assessment viene eseguito anche prima di alcune transizioni pit/bandiera per non perdere uno sforamento fra due scansioni. I tipi di penalità configurano azione, secondi e, per gli avvisi, soglia e conseguenza automatica. I parametri si modificano tramite endpoint admin e vengono usati dal backend, non decisi dal telefono. Per gli avvisi il codice applica la conseguenza a ogni nuovo avviso con conteggio maggiore o uguale alla soglia: con soglia 3, scatta al terzo, al quarto e ai successivi, non soltanto ai multipli di 3. Questo meccanismo è distinto dal marker una-volta-per-stint.

## 6. Acquisizione e WebSocket

`BaseScraper` offre `setup(url)`, `scrape()` e `teardown()`. Il risultato comune è una tabella `headers`/`rows`, non un DTO completamente tipizzato per kart. La factory seleziona Apex Timing, RaceFacer, simulatore o fallback generico; la validazione della sorgente rimane separata.

| Impostazione corrente | Valore |
| --- | --- |
| Intervallo polling | 3 secondi, oltre al tempo necessario per acquisire la pagina |
| Sessioni sorgente contemporanee | Massimo 5 |
| Grace period senza iscritti | 15 secondi |
| Simulatore | `https://simulator`, letto da `racefacer_sim/sim_data/live_timing.json` |
| Host consentiti | `live.racefacer.com`, `www.apex-timing.com`, `apex-timing.com`, `simulator` |

`is_url_allowed` accetta schemi HTTP o HTTPS con host consentito. Il controllo iniziale dell'host non documenta una verifica completa di redirect e navigazioni del browser.

| Messaggio | Significato |
| --- | --- |
| Client `set_url` con `url` | Sceglie la sorgente del singolo socket; ammesso da viewer in su. |
| Client `get_status` | Richiede URL, ruolo e indicatore scraper della propria sessione. |
| Client `subscribe_event` con `event_id` | Associa il socket a un evento; verifica intero positivo. |
| Server `url_changed` | Conferma la selezione; può seguire l'ultimo snapshot in cache. |
| Server `timing_update` | `url`, `updated_at`, `headers`, `rows`. |
| Server `status` / `error` | Stato connessione/sorgente o errore applicativo. |
| Server `event_update` | Invita a rileggere dati evento; alcuni producer includono `event_id`, `change`, `karts_changed`, `request_id`, altri solo `type`. |

La distribuzione timing è per URL; quella operativa è per evento. Dopo un errore di invio il client viene rimosso dalle mappe. La modifica di un circuito è rifiutata con 409 se esiste un evento started associato tramite location; sono controllati anche conflitti di URL. Se ammessa, blocca temporaneamente nuove sottoscrizioni al vecchio URL e disconnette i socket interessati prima del salvataggio; una disconnessione non completata per timeout produce rollback e 503.

`X-Request-ID` correla mutazione e invalidazione, ma non deduplica il comando sul server. Il WebSocket non è una coda durevole: dopo una perdita di aggiornamenti occorre rileggere lo stato REST. `scraping=true` non garantisce freschezza del provider; `updated_at` è attualmente una data locale senza timezone esplicita.

## 7. Risultati, giri e PDF

### Classifiche persistenti

I risultati ufficiali sono record `EventResult` nel DB. Import e cancellazione richiedono admin. Il parser legge un CSV, valida righe e tenta l'associazione con kart, partecipanti e team; può salvare risultati senza account e restituire problemi di associazione.

Se non esiste alcuna riga valida, risponde con errore e conserva la classifica precedente. Se ci sono righe valide, sostituisce **tutti i risultati ufficiali dell'evento**, indipendentemente da `result_type`, e inserisce quelli accettati. Anche DELETE rimuove tutti gli ufficiali dell'evento, non soltanto il tipo indicato dal parametro.

Non c'è una scadenza temporale dei risultati. Possono essere eliminati esplicitamente, sostituiti o rimossi tramite cascade quando si elimina l'evento o l'utente associato. L'assenza di un account collegato è diversa dall'assenza del risultato.

### Giri osservati

`lap_tracker.py` registra l'ultimo giro quando cresce il contatore; un salto di più giri non ricostruisce quelli mancanti. Trova il circuito per URL e l'evento started più recente con `Event.location == Kartodromo.nome`. Non c'è un'associazione esplicita sessione/evento né raccolta continua garantita senza iscritti.

`GET /events/{event_id}/lap-stats` calcola best/worst/media per kart. Per media e worst esclude tempi superiori al 150% del best, e restituisce il numero di giri considerati. Questi dati non pubblicano automaticamente una classifica ufficiale.

### Liberatorie e documenti browser

Le firme sono immagini disegnate in Base64 salvate in `SignedRelease`, con unicità utente/evento. Le anteprime e i PDF amministrativi sono generati da `pdf_generator.py`. Non si tratta di una firma crittografica e il record non contiene una revisione immutabile separata del testo liberatoria.

Il servizio documenti temporanei è distinto:

- `POST /documents/pdf`: richiede autenticazione, riceve byte grezzi, controlla prefisso `%PDF-` e limite **10 MiB = 10.485.760 byte**. Un byte oltre il limite produce HTTP 413; il prefisso non è una validazione completa della struttura PDF.
- Salva il documento nella directory temporanea `kart-timing-pdfs` con nome casuale e restituisce un percorso browser.
- `GET /documents/pdf/{filename}`: non richiede JWT; chi possiede il link può aprirlo entro **3.600 secondi** dal salvataggio. Le letture non rinnovano la durata.
- Un file scaduto ancora presente viene cancellato all'accesso e produce 410. Un file già rimosso produce 404. Anche i successivi upload puliscono i file scaduti; non esiste un job di cancellazione puntuale allo scadere dell'ora.
- Le risposte PDF hanno `Cache-Control: no-store`. Scadenza del link e persistenza della classifica/firma sono indipendenti.

## 8. Notifiche

Le notifiche sono record per destinatario, consultabili, marcabili come lette ed eliminabili dall'utente proprietario. Accompagnano creazione evento, modifiche iscrizione/team, avvio evento e operazioni liberatoria. Non è presente invio push APNs.

Il monitor promemoria seleziona eventi scheduled futuri entro 7 giorni e utenti collegati con iscrizione confirmed o pending_payment. `EventReminderDelivery`, con chiave user/event, impedisce duplicati anche dopo riavvio o cancellazione della notifica. Un promemoria già emesso non viene automaticamente riabilitato da una semplice rischedulazione.

## 9. Limiti di implementazione

- **F1 (aperto)** — `main.py` monta tutto `data/` su `/static`: il mount non separa DB e altri dati privati dalle immagini pubbliche.
- **F2 (aperto)** — la firma vuota (`signature_base64: ""`) viene accettata dal backend: `SignedRelease` può essere persistita senza una firma reale.
- Gli eventi non hanno un proprietario organizzatore per isolamento multi-tenant.
- `subscribe_event` non applica una policy completa di accesso all'evento. `GET .../messages` filtra per kart solo se il chiamante specifica il parametro; non vincola quel kart alla sua appartenenza.
- Le sessioni/source map non sono condivise fra processi e i broadcast non hanno garanzia di consegna durevole.
- Chiudere automaticamente l'evento non equivale a fermare il turno. L'interruzione del backend durante uno stint richiede una politica di riconciliazione, non dimostrata dai soli timestamp persistenti.
- L'acquisizione provider e la piena freschezza del dato richiedono verifiche operative: i test unitari non stabiliscono disponibilità o prestazioni in pista.

## 10. Test e verifica

I test sono stati centralizzati in `project_tests/backend/`, nella root. Dalla root del repository:

```sh
.venv/bin/python project_tests/run.py
.venv/bin/python project_tests/benchmark.py
```

Il runner configura percorsi import e un segreto JWT casuale di test, salva log/esiti per caso e usa fixture isolate. Non richiede il segreto operativo.

Il 16 settembre 2026 i **69 test originali** sono stati rieseguiti con successo. La suite estesa DD/RASD conta **98 casi: 96 superati, 2 falliti**. I finding aperti sono **F1** (esposizione del database via mount statico, verificata con file fittizi) e **F2** (firma vuota accettata, nessuna validazione su `signature_base64: ""`). I precedenti finding sulle identità eliminate/declassate nel download PDF sono **risolti**: il meccanismo `token_version` + lettura corrente del ruolo dal DB copre tutti i percorsi REST e WebSocket, confermato dai nuovi test `TokenRenewalTests` e dalla verifica della migrazione su DB legacy. I fallimenti rimangono visibili e producono exit code 1; non sono stati corretti in questa attività di verifica.

Vedere [report e copertura](../project_tests/TEST_REPORT.md), [elenco dei test già svolti](../project_tests/ALREADY_EXECUTED.md) e [istruzioni](../project_tests/README.md). Le misure prestazionali sono locali e ridotte; un tentativo a 50 client è inconclusivo. Non sono stati eseguiti collaudi UI su dispositivo o prove con provider reali.
