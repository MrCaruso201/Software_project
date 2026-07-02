# Kart Live Timing — App iOS

Documentazione del client iOS (SwiftUI) che si collega al server di live timing per visualizzare in tempo reale la classifica di una sessione di kartodromo, scaricata via WebSocket.

---

## 1. Panoramica

L'app è divisa in due schermate principali:

1. **`ServerListView`** — schermata iniziale: permette di trovare un server sulla rete locale (via Bonjour/mDNS), collegarsi manualmente tramite IP, oppure collegarsi al server remoto predefinito (via Tailscale Funnel).
2. **`TimingView`** — schermata di dettaglio: mostra la classifica live in tempo reale, ricevuta via WebSocket, con possibilità di cambiare l'URL della pagina sorgente da cui il server sta facendo scraping.

Il flusso è: `ServerListView` → (selezione server) → `TimingView`.

---

## 2. Struttura dei file

| File | Responsabilità |
| --- | --- |
| `KartTimingAppApp.swift` | Entry point dell'app (`@main`), imposta `ServerListView` come schermata radice. |
| `ServerListView.swift` | UI di selezione server: input manuale, server remoto fisso, lista di server scoperti via Bonjour. |
| `ServerBrowser.swift` | Discovery Bonjour/mDNS dei server sulla rete locale (`_karttiming._tcp.`). |
| `TimingView.swift` | UI della classifica live: tabella/card dei piloti, stato connessione, editor URL sorgente. |
| `KartTimingManager.swift` | Gestisce la connessione WebSocket verso il server: connessione, invio comandi, parsing messaggi in arrivo. |
| `Models.swift` | Modelli dati: `TimingPayload` (dati di classifica) e `DiscoveredServer` (server da contattare). |
| `Color+Theme.swift` | Palette colori dell'interfaccia (tema scuro "kartodromo"). |
| `Info.plist` | Permessi di rete: `NSAppTransportSecurity` (permette connessioni non-HTTPS in locale) e `NSBonjourServices` per la discovery. |

---

## 3. Modelli dati (`Models.swift`)

### `DiscoveredServer`

Rappresenta un server a cui l'app può collegarsi (scoperto via Bonjour, inserito manualmente, oppure il server remoto fisso).

```swift
struct DiscoveredServer: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let host: String
    let port: Int
    var useTLS: Bool = false
    var token: String? = nil
}
```

- `wsURL` costruisce l'URL WebSocket effettivo: schema `ws://` o `wss://` (se `useTLS`), host, porta (omessa se TLS, dato che si assume 443 standard), path `/ws`, e il `token` come query param se presente.
- `DiscoveredServer.remoteServer` è una costante statica che punta al server esposto pubblicamente via Tailscale Funnel (`marcos-macbook-pro.tail71e118.ts.net`, porta 443, TLS attivo).

### `TimingPayload`

Rappresenta l'ultimo stato di classifica ricevuto dal server:

```swift
struct TimingPayload {
    let updatedAt: String     // timestamp ISO
    let headers: [String]     // intestazioni colonna, es. ["Pos", "Kart", "Pilota", ...]
    let rows: [[String]]      // righe di classifica, una per pilota
    let url: String           // URL sorgente da cui provengono i dati
}
```

I dati sono generici (header + righe di stringhe): l'app non conosce a priori la struttura della tabella, la interpreta a runtime (vedi §5.3).

---

## 4. Discovery dei server (`ServerBrowser.swift`)

`ServerBrowser` è un `ObservableObject` che usa `NetServiceBrowser` per cercare automaticamente server sulla rete locale che pubblicano il servizio Bonjour `_karttiming._tcp.` (pubblicato dal backend Python via `zeroconf`).

Flusso:

1. `startBrowsing()` avvia la ricerca (`NetServiceBrowser.searchForServices`).
2. Quando trova un servizio (`didFind`), lo mette in coda di risoluzione e chiama `resolve(withTimeout:)` per ottenerne l'indirizzo IP.
3. Quando la risoluzione ha successo (`netServiceDidResolveAddress`), estrae l'indirizzo IPv4 da `sockaddr_storage` e costruisce un `DiscoveredServer` (con un token fisso hardcoded, vedi §7 — Nota sulla sicurezza), pubblicandolo in `@Published var servers`.
4. `stopBrowsing()` interrompe la ricerca (chiamato in `onDisappear` della `ServerListView`).

I server scoperti vengono deduplicati per `host` + `port`.

---

## 5. Schermata classifica live (`TimingView.swift` + `KartTimingManager.swift`)

### 5.1 Connessione

All'apertura della view (`onAppear`), `KartTimingManager.connect(to:)`:

1. Chiude un'eventuale connessione precedente.
2. Apre una `URLSessionWebSocketTask` verso `server.wsURL`.
3. Avvia il loop di ricezione messaggi (`listen()`, ricorsivo: ogni messaggio ricevuto richiama `receive` per il successivo).
4. Invia subito il comando `get_status` per sincronizzarsi con lo stato corrente del server (URL attivo e se lo scraping è in corso).

Alla chiusura della view (`onDisappear`), la connessione viene chiusa (`disconnect()`), che resetta anche lo stato pubblicato (`isConnected`, `timing`, `isScrapingActive`).

### 5.2 Messaggi dal server

`KartTimingManager` interpreta i messaggi JSON in arrivo in base al campo `"type"`:

| Tipo messaggio | Effetto lato client |
| --- | --- |
| `timing_update` | Aggiorna `timing` con il nuovo `TimingPayload`; imposta `isScrapingActive = true`. |
| `status` | Aggiorna `currentURL` e `isScrapingActive` in base allo stato riportato dal server. |
| `url_changed` | Conferma che il server ha cambiato sorgente; aggiorna `currentURL`. |
| `error` | Loggato in console (nessun aggiornamento di stato). |

Ogni connessione WebSocket è indipendente: cambiare URL da un dispositivo non influisce sulla classifica visualizzata dagli altri dispositivi collegati allo stesso server (il server gestisce le sessioni di scraping per client, vedi la documentazione lato server).

### 5.3 Rendering della classifica

`TimingView` non assume una struttura fissa delle colonne: analizza gli `headers` ricevuti e cerca per parole chiave (case-insensitive, con supporto italiano/inglese) l'indice delle colonne principali:

- **Posizione**: `pos`, `pos.`, `p`, `#`
- **Numero kart**: `kart`, `num`, `n°`, `no`, `bib`
- **Nome pilota**: `driver`, `pilota`, `name`, `nome`, `pilot`
- **Ultimo giro**: `last`, `lap`, `giro`, `time`, `tempo`
- **Distacco**: `gap`, `diff`, `distanza`, `behind`
- **Miglior giro**: `best`, `migliore`, `fastest`, `record`

Tutte le altre colonne non riconosciute vengono trattate come "extra" e mostrate in forma compatta sotto il nome del pilota; espandendo la card (tap) vengono mostrate tutte in una griglia a due colonne con etichetta e valore.

Ogni riga di classifica è renderizzata come una **card** (`kartCard`): posizione, numero kart, nome abbreviato (prime 3 lettere maiuscole), ultimo tempo, eventuale miglior tempo e distacco dal leader. La card del primo classificato (`pos == "1"`) è evidenziata con un bordo/sfondo accentato. Il tap su una card la espande mostrando tutti i dettagli disponibili (nome completo e tutte le colonne extra).

### 5.4 Cambio sorgente (URL)

Il pulsante nella toolbar apre uno sheet (`urlSheet`) con un campo di testo per inserire un nuovo URL. Confermando, viene inviato il comando:

```json
{ "command": "set_url", "url": "https://..." }
```

Il server aggiorna la sorgente da cui fa scraping **solo per questo client** (o per i client eventualmente già iscritti allo stesso URL); altri client collegati continuano a vedere la propria sorgente senza interruzioni.

### 5.5 Stati dell'interfaccia

- **Connesso / Disconnesso**: pallino verde/rosso in alto, basato su `manager.isConnected`.
- **LIVE**: badge lampeggiante mostrato quando `isScrapingActive == true`.
- **Empty state**: se non sono ancora arrivati dati, mostra uno spinner ("Attendo dati dal kartodromo…") se connesso, oppure un'icona di disconnessione ("Connessione persa") se la connessione è caduta.

---

## 6. Tema visivo (`Color+Theme.swift`)

Palette scura personalizzata, pensata per l'uso "trackside" (buona leggibilità anche in condizioni di luce diretta):

| Colore | Uso |
| --- | --- |
| `kartBG` | Sfondo principale (quasi nero) |
| `kartPanel` | Sfondo di pannelli/card |
| `kartAccent` | Rosso acceso — evidenziazioni, leader, azioni primarie |
| `kartGreen` | Stato connesso, miglior tempo |
| `kartRed` | Stato disconnesso |
| `kartDim` | Testo secondario/disattivato (bianco a opacità ridotta) |

---

## 7. Configurazione di rete e permessi

`Info.plist` dichiara:

- `NSAppTransportSecurity` (vuoto): consente connessioni non cifrate (`ws://`) verso i server sulla rete locale, necessarie per il server in LAN che non usa TLS.
- `NSBonjourServices`: dichiara `_karttiming._tcp.` come servizio Bonjour che l'app è autorizzata a cercare (richiesto da iOS per la discovery locale).

**Nota sulla sicurezza**: il token di autenticazione (`miotokentest12345`) è attualmente hardcoded sia in `ServerBrowser.swift` (per i server scoperti via Bonjour) sia in `ServerListView.swift` (per la connessione manuale) sia in `Models.swift` (per il server remoto). Va considerato un valore di sviluppo/test: in un'app distribuita andrebbe sostituito con un meccanismo di configurazione o inserimento a runtime, per evitare che sia visibile nel binario compilato.

---

## 8. Flusso completo (riepilogo)

1. L'app si apre su `ServerListView`.
2. `ServerBrowser` cerca automaticamente server Bonjour sulla rete locale.
3. L'utente sceglie un server (scoperto, manuale, o quello remoto fisso).
4. La navigazione porta a `TimingView`, che apre una connessione WebSocket dedicata tramite `KartTimingManager`.
5. Il client riceve subito lo stato corrente (`get_status` → `status`) e successivamente aggiornamenti live (`timing_update`) ogni volta che il server rileva un cambiamento nei dati scrapati.
6. L'utente può cambiare in autonomia la sorgente (`set_url`) senza impattare gli altri client collegati allo stesso server.
7. Alla chiusura della view, la connessione WebSocket viene chiusa correttamente.
