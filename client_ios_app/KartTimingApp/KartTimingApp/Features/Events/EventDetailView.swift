import SwiftUI

/// Vista standalone del dettaglio evento.
/// Usata principalmente per i deep link da notifiche push (pendingEventIdToOpen)
/// che ora puntano alla nuova EventRootView.
/// Mantenuta per retrocompatibilità e per usi diretti futuri.
struct EventDetailView: View {
    @Environment(\.dismiss) var dismiss
    let server: DiscoveredServer
    let event: RaceEvent

    var body: some View {
        EventRootView(server: server, event: event)
    }
}
