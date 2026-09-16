# Test già eseguiti, non registrati singolarmente nel DD/RASD

La precedente revisione aveva eseguito **69 test backend**, riportandone il totale nella documentazione tecnica. I due documenti forniti definiscono i gruppi di test, ma non riportano i singoli esiti. Qui viene recuperata quella tracciabilità: tutti i 69 sono stati rieseguiti e passano ancora.

I file sono stati **spostati senza modificarne il contenuto** dalla vecchia directory backend. Il confronto con la versione Git precedente alla migrazione è stato verificato byte per byte. Gli esiti storici sono quelli comunicati nella sessione; la prova riproducibile attuale è il [run baseline](evidence/20260916T193702022475Z.json).

| Modulo | Casi | Gruppi DD | Cosa verifica | Esito attuale |
| --- | --- | --- | --- | --- |
| [test_access_integrity.py](backend/test_access_integrity.py) | 6 | T1, T2, T5, T8, T12 | Ruolo corrente, identità eliminata, WebSocket inattivo; CSV invalido/misto (A7). | PASS |
| [test_event_lifecycle.py](backend/test_event_lifecycle.py) | 4 | T9 | Chiusura a 48 ore, confini temporali, conversione UTC e invalidazione. | PASS |
| [test_event_registration_integrity.py](backend/test_event_registration_integrity.py) | 16 | T2, T3 | Dimensioni team, duplicati, modifiche, deadline e transizioni non consentite. | PASS |
| [test_event_reminders.py](backend/test_event_reminders.py) | 4 | T9 | Finestra sette giorni, deduplicazione, esclusioni e rollback. | PASS |
| [test_kartodromo_update.py](backend/test_kartodromo_update.py) | 5 | T5, T12 | Blocco con evento live, disconnessione selettiva, conflitti e timeout. | PASS |
| [test_lap_stats.py](backend/test_lap_stats.py) | 1 | T8 | Statistiche per kart e filtro dei giri oltre il 150% del best. | PASS |
| [test_live_message_scope.py](backend/test_live_message_scope.py) | 3 | T6 | Comandi globali, informazioni mirate, stop rosso/scacchi e avvio esplicito (A5/A9). | PASS |
| [test_notifications_integrity.py](backend/test_notifications_integrity.py) | 7 | T2, T3, T9, T12 | Persistenza reale, destinatari, atomicità, read/delete e notifiche avvio. | PASS |
| [test_pdf_browser.py](backend/test_pdf_browser.py) | 4 | T4, T12 | PDF temporaneo, scadenza, validazione e link sconosciuto; non l’intera liberatoria. | PASS |
| [test_penalty_configuration.py](backend/test_penalty_configuration.py) | 7 | T7 | Validazione valori, preservazione configurazione/seed e migrazioni. | PASS |
| [test_stint_monitor.py](backend/test_stint_monitor.py) | 5 | T6, T7 | Sforamento, marker una volta per stint, rimozione, pit, riarmo e sessioni DB (A6). | PASS |
| [test_ws_manager.py](backend/test_ws_manager.py) | 3 | T5, T10 | Pulizia socket falliti e continuità verso gli altri iscritti. | PASS |
| [test_ws_router.py](backend/test_ws_router.py) | 4 | T5, T10 | Input malformati, errori invio/ricezione, cancellazione e cleanup. | PASS |

**Totale: 69 casi in 13 moduli.** Il dettaglio di ogni metodo è nel [registro completo](TEST_INVENTORY.md). Non attribuiamo PASS a un intero gruppo DD solo perché alcuni suoi casi erano già presenti.

Particolarmente rilevanti: A7 era già coperto in `test_access_integrity.py`; A6 nei test del monitor; stop/riavvio A5/A9 nei test dei messaggi. La nuova suite aggiunge prove HTTP che esercitano anche le dipendenze di autorizzazione, assenti nei test che chiamano direttamente una funzione router.
