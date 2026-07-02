# Kart Live Timing — App iOS

Documentazione del client iOS (SwiftUI) che si collega al server di live timing, permettendo agli utenti di autenticarsi, visualizzare la classifica e, se hanno i privilegi necessari, amministrare gli utenti.

---

## 1. Panoramica

L'app si sviluppa attorno a un flusso autenticato:

1. **`LoginView` / `RegisterView`**: Gestisce l'autenticazione. Solo gli utenti loggati possono accedere all'app.
2. **`WelcomeView`**: La dashboard principale in cui l'utente può scegliere di avviare il Live Timing, fare il logout, o accedere all'area di gestione utenti (se ha privilegi di amministratore).
3. **`TimingView`**: La schermata di dettaglio per la classifica live in tempo reale, ricevuta via WebSocket.
4. **`AdminUsersView`**: Pannello di amministrazione per ricercare gli utenti iscritti e modificarne i ruoli (Spettatore, Direttore di Gara, Admin).

---

## 2. Struttura dei file

| File | Responsabilità |
| --- | --- |
| `KartTimingAppApp.swift` | Entry point dell'app (`@main`), definisce l'albero di navigazione e gestisce lo stato di autenticazione (`AuthState`). |
| `WelcomeView.swift` | Hub centrale dopo il login; naviga verso Timing o Admin. |
| `AdminUsersView.swift` | UI riservata agli admin per la ricerca e il cambio ruolo degli utenti. |
| `TimingView.swift` | UI della classifica live: tabella/card dei piloti, stato connessione, editor URL sorgente. |
| `AuthService.swift` | Wrapper delle chiamate REST (`/auth/*` e `/admin/*`) verso l'URL remoto. Gestisce token di accesso e di refresh. |
| `KartTimingManager.swift` | Gestisce la connessione WebSocket verso il server: connessione, invio comandi, parsing messaggi in arrivo. |
| `Models.swift` | Modelli dati: `TimingPayload` (dati di classifica) e definizioni di rete. |
| `Color+Theme.swift` | Palette colori dell'interfaccia (tema scuro "kartodromo"). |

---

## 3. Flusso di Autenticazione (`AuthService` e `AuthState`)

L'app utilizza **JWT** per l'identità.
- Il server di base è fisso e accessibile via internet tramite Tailscale Funnel (es. `https://marcos-macbook-pro.tail71e118.ts.net`).
- In fase di avvio, l'app verifica la presenza di un refresh token salvato. Se valido, genera un nuovo access token senza richiedere le credenziali; altrimenti mostra la schermata di Login.
- I ruoli (`viewer`, `race_director`, `admin`) vengono estratti dal token decodificato per adattare l'interfaccia (nascondere/mostrare pulsanti in `WelcomeView`).

---

## 4. Schermata classifica live (`TimingView.swift` + `KartTimingManager.swift`)

### 4.1 Connessione

La `TimingView` utilizza l'`access_token` JWT attivo passandolo nel WebSocket:
`wss://<SERVER>/ws?token=<ACCESS_TOKEN>`

`KartTimingManager.connect(to:)`:
1. Chiude un'eventuale connessione precedente.
2. Apre una `URLSessionWebSocketTask`.
3. Avvia il loop di ricezione messaggi JSON.
4. Invia il comando `get_status` per sincronizzarsi.

### 4.2 Messaggi dal server

`KartTimingManager` interpreta i messaggi JSON in arrivo in base al campo `"type"`:

| Tipo messaggio | Effetto lato client |
| --- | --- |
| `timing_update` | Aggiorna i dati della tabella e imposta lo stato LIVE. |
| `status` | Aggiorna `currentURL` e se c'è attività di scraping in corso. |
| `url_changed` | Conferma che il server ha cambiato sorgente; aggiorna `currentURL`. |
| `error` | Loggato in console. |

### 4.3 Rendering della classifica

La struttura è generica e interprete degli `headers` (colonne) che arrivano. L'app cerca per parole chiave (es. "Pos", "Kart", "Pilota", "Ultimo giro", "Distacco") per determinare il mapping delle colonne.

Le righe di classifica sono renderizzate in **card** (`kartCard`). Le colonne non direttamente riconosciute o secondarie vengono compattate; cliccando su una card si espande la visualizzazione per mostrare tutte le chiavi/valore aggiuntive.

### 4.4 Cambio sorgente (URL)

Un utente loggato può cambiare la sorgente dello scraping tramite l'icona URL in alto a destra, inserendo un nuovo link (es. la pagina di live timing web ufficiale).
Il server aggiornerà la sessione, ricaricherà Playwright e riprenderà a mandare via WebSocket i dati aggiornati.

---

## 5. Pannello Admin (`AdminUsersView.swift`)

L'utente con ruolo `admin` o chiunque sia in grado di chiamare gli endpoint di `AdminUsersView` può:
- Ricercare utenti (tramite API `/admin/users/search`).
- Cambiare il ruolo ad un utente da un picker segmentato (`viewer`, `race_director`, `admin`).
- I cambiamenti vengono persistiti immediatamente chiamando `AuthService.updateUserRole()`.

---

## 6. Tema visivo (`Color+Theme.swift`)

Palette scura personalizzata, pensata per l'uso "trackside" con alta visibilità:
- `kartBG`: Sfondo principale (quasi nero)
- `kartPanel`: Sfondo di pannelli/card
- `kartAccent`: Rosso acceso (leader, evidenziazioni)
- `kartGreen`: Connesso, miglior tempo
- `kartDim`: Testo secondario disattivato

---

## 7. Flusso completo (riepilogo)

1. L'app si avvia verificando il login. Mostra la view di autenticazione se necessaria.
2. Una volta dentro (`WelcomeView`), un utente normale vede le opzioni "Live Timing" e "Logout". Un admin vede anche "Gestisci Utenti".
3. Entrando nel "Live Timing", l'app apre una connessione WebSocket con l'URL Tailscale, validando la connessione con il proprio JWT.
4. I payload arrivano sul dispositivo appena lo scraper Python intercetta aggiornamenti dalla pista e vengono renderizzati nella vista.
5. Dal "Gestisci Utenti", un admin cerca e aggiorna i permessi degli iscritti che avranno effetto immediato dal loro prossimo login.
