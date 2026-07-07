import SwiftUI

struct EventiFormView: View {
    @Environment(\.dismiss) var dismiss
    let server: DiscoveredServer
    let authState: AuthState
    let viewModel: EventiViewModel
    
    // Se `editingEvent` è nil, siamo in modalità Creazione.
    var editingEvent: RaceEvent?

    @StateObject private var kartodromoVM = KartodromoViewModel()
    
    @State private var title: String = ""
    @State private var location: String = ""
    @State private var eventDate: Date = roundedToQuarterHour(Date())
    
    // Campi opzionali
    @State private var registrationCost: String = ""
    @State private var maxParticipants: String = ""
    @State private var maxGroups: String = ""
    @State private var minPeoplePerGroup: String = ""
    @State private var maxPeoplePerGroup: String = ""
    @State private var weightLimit: String = ""
    
    @State private var isSaving = false
    
    // Intervalli da 15 minuti: stride genera gli orari selezionabili nel DatePicker
    private static let minuteInterval = 15
    
    var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !location.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // ── Obbligatori ───────────────────────────────────────────────
                Section(header: Text("Informazioni Obbligatorie").foregroundColor(.primary)) {
                    HStack {
                        Text("Nome Evento")
                            .foregroundColor(.secondary)
                            .frame(width: 130, alignment: .leading)
                        TextField("Es. Gran Premio", text: $title)
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Luogo / Pista")
                            .foregroundColor(.secondary)
                            .frame(width: 130, alignment: .leading)
                        if kartodromoVM.isLoading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Picker("Seleziona Circuito", selection: $location) {
                                Text("Seleziona...").tag("")
                                ForEach(kartodromoVM.kartodromi, id: \.nome) { k in
                                    Text(k.nome).tag(k.nome)
                                }
                            }
                            .labelsHidden()
                            .tint(.primary)
                        }
                    }
                    // DatePicker con step di 15 minuti tramite minuteInterval
                    HStack {
                        Text("Data Evento")
                            .foregroundColor(.secondary)
                            .frame(width: 130, alignment: .leading)
                        DatePicker("", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                }
                
                // ── Opzionali ─────────────────────────────────────────────────
                Section(header: Text("Impostazioni Aggiuntive").foregroundColor(.primary)) {
                    HStack {
                        Text("Costo (€)")
                            .foregroundColor(.secondary)
                            .frame(width: 130, alignment: .leading)
                        TextField("Es. 150.00", text: $registrationCost)
                            .keyboardType(.decimalPad)
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Max Partecipanti")
                            .foregroundColor(.secondary)
                            .frame(width: 130, alignment: .leading)
                        TextField("Es. 60", text: $maxParticipants)
                            .keyboardType(.numberPad)
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Max Gruppi")
                            .foregroundColor(.secondary)
                            .frame(width: 130, alignment: .leading)
                        TextField("Es. 3", text: $maxGroups)
                            .keyboardType(.numberPad)
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Min x Gruppo")
                            .foregroundColor(.secondary)
                            .frame(width: 130, alignment: .leading)
                        TextField("Es. 10", text: $minPeoplePerGroup)
                            .keyboardType(.numberPad)
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Max x Gruppo")
                            .foregroundColor(.secondary)
                            .frame(width: 130, alignment: .leading)
                        TextField("Es. 20", text: $maxPeoplePerGroup)
                            .keyboardType(.numberPad)
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Peso Min. (kg)")
                            .foregroundColor(.secondary)
                            .frame(width: 130, alignment: .leading)
                        TextField("Es. 85.0", text: $weightLimit)
                            .keyboardType(.decimalPad)
                            .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle(editingEvent == nil ? "Nuovo Evento" : "Modifica Evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Salva") {
                            saveEvent()
                        }
                        .disabled(!isFormValid)
                        .foregroundColor(isFormValid ? .kartAccent : .gray)
                    }
                }
            }
            .onAppear {
                kartodromoVM.fetchAll(serverURL: server.httpURL, token: authState.currentToken)
                
                if let ev = editingEvent {
                    title = ev.title
                    location = ev.location
                    
                    // Prova a parsare la data ISO8601 dal server
                    let isoFull = ISO8601DateFormatter()
                    isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let isoBasic = ISO8601DateFormatter()
                    
                    let dfT = DateFormatter()
                    dfT.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    let dfT2 = DateFormatter()
                    dfT2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                    let dfSpace = DateFormatter()
                    dfSpace.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    
                    if let d = isoFull.date(from: ev.eventDate) {
                        eventDate = d
                    } else if let d = isoBasic.date(from: ev.eventDate) {
                        eventDate = d
                    } else if let d = dfT.date(from: ev.eventDate) {
                        eventDate = d
                    } else if let d = dfT2.date(from: ev.eventDate) {
                        eventDate = d
                    } else if let d = dfSpace.date(from: ev.eventDate) {
                        eventDate = d
                    }
                    
                    if let cost = ev.registrationCost { registrationCost = String(cost) }
                    if let part = ev.maxParticipants { maxParticipants = String(part) }
                    if let grp = ev.maxGroups { maxGroups = String(grp) }
                    if let minP = ev.minPeoplePerGroup { minPeoplePerGroup = String(minP) }
                    if let maxP = ev.maxPeoplePerGroup { maxPeoplePerGroup = String(maxP) }
                    if let w = ev.weightLimit { weightLimit = String(w) }
                }
            }
        }
    }
    
    private func saveEvent() {
        isSaving = true
        
        // Invia la data come ISO8601 — il backend FastAPI la accetta
        let formatter = ISO8601DateFormatter()
        let dateString = formatter.string(from: eventDate)
        
        var data: [String: Any] = [
            "title": title,
            "location": location,
            "event_date": dateString
        ]
        
        if let cost = Double(registrationCost) { data["registration_cost"] = cost }
        if let part = Int(maxParticipants) { data["max_participants"] = part }
        if let grp = Int(maxGroups) { data["max_groups"] = grp }
        if let minP = Int(minPeoplePerGroup) { data["min_people_per_group"] = minP }
        if let maxP = Int(maxPeoplePerGroup) { data["max_people_per_group"] = maxP }
        if let w = Double(weightLimit) { data["weight_limit"] = w }
        
        if let ev = editingEvent {
            viewModel.updateEvent(
                serverURL: server.httpURL,
                eventId: ev.id,
                eventData: data,
                token: authState.currentToken
            ) { success in
                isSaving = false
                if success { dismiss() }
            }
        } else {
            viewModel.createEvent(
                serverURL: server.httpURL,
                eventData: data,
                token: authState.currentToken
            ) { success in
                isSaving = false
                if success { dismiss() }
            }
        }
    }
}

/// Arrotonda una data al quarto d'ora più vicino per inizializzare il DatePicker
private func roundedToQuarterHour(_ date: Date) -> Date {
    let cal = Calendar.current
    let minutes = cal.component(.minute, from: date)
    let roundedMinutes = (minutes / 15) * 15
    return cal.date(bySetting: .minute, value: roundedMinutes, of: date) ?? date
}

// Estensione per supportare minuteInterval nell'environment
private struct MinuteIntervalKey: EnvironmentKey {
    static let defaultValue: Int = 1
}

extension EnvironmentValues {
    var minuteInterval: Int {
        get { self[MinuteIntervalKey.self] }
        set { self[MinuteIntervalKey.self] = newValue }
    }
}
