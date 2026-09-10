import SwiftUI

struct EventiFormView: View {
    @Environment(\.dismiss) var dismiss
    let server: DiscoveredServer
    let authState: AuthState
    let viewModel: EventiViewModel

    var editingEvent: RaceEvent? = nil
    var onSaved: (() -> Void)? = nil

    /// Se true (es. quando usato come tab), non chiude la view dopo il salvataggio
    /// ma mostra un banner "Modifiche salvate" e chiama comunque onSaved.
    var suppressDismissOnSave: Bool = false

    @StateObject private var kartodromoVM = KartodromoViewModel()

    // MARK: - Form fields
    @State private var title: String = ""
    @State private var location: String = ""
    @State private var eventDate: Date = roundedToQuarterHour(Date())
    @State private var registrationCost: String = ""
    @State private var maxParticipants: String = ""
    @State private var minPeoplePerGroup: String = ""
    @State private var maxPeoplePerGroup: String = ""
    @State private var weightLimit: String = ""
    @State private var kart: String = ""
    @State private var description: String = ""
    @State private var raceDuration: String = ""
    @State private var maxStintDuration: String = ""
    @State private var daysBeforeDeadline: String = ""

    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var saveError: String? = nil
    @State private var showSavedBanner = false

    var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !location.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Color.kartBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {

                    // ── Informazioni Obbligatorie ─────────────────────────
                    formSection(title: "Informazioni Obbligatorie", icon: "star.fill") {

                        formRow(label: "Nome Evento", icon: "flag.checkered") {
                            TextField("Es. Gran Premio", text: $title)
                                .foregroundColor(.kartForeground)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 180)
                        }

                        rowDivider()

                        formRow(label: "Circuito", icon: "mappin.and.ellipse") {
                            if kartodromoVM.isLoading {
                                ProgressView().tint(.kartAccent).scaleEffect(0.8)
                            } else {
                                Picker("", selection: $location) {
                                    Text("Seleziona...").tag("")
                                    ForEach(kartodromoVM.kartodromi, id: \.nome) { k in
                                        Text(k.nome).tag(k.nome)
                                    }
                                }
                                .labelsHidden()
                                .tint(.kartAccent)
                            }
                        }

                        rowDivider()

                        formRow(label: "Data Evento", icon: "calendar") {
                            DatePicker("", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .tint(.kartAccent)
                        }
                    }

                    // ── Costi & Partecipanti ──────────────────────────────
                    formSection(title: "Costi & Partecipanti", icon: "person.3.fill") {

                        formRow(label: "Costo (€)", icon: "eurosign") {
                            TextField("Es. 150.00", text: $registrationCost)
                                .foregroundColor(.kartForeground)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 120)
                        }

                        rowDivider()

                        formRow(label: "Max Partecipanti", icon: "person.fill") {
                            TextField("Es. 60", text: $maxParticipants)
                                .foregroundColor(.kartForeground)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .frame(maxWidth: 80)
                        }

                        rowDivider()

                        formRow(label: "Min per Squadra", icon: "person.2") {
                            TextField("Es. 2", text: $minPeoplePerGroup)
                                .foregroundColor(.kartForeground)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .frame(maxWidth: 80)
                        }

                        rowDivider()

                        formRow(label: "Max per Squadra", icon: "person.2.fill") {
                            TextField("Es. 5", text: $maxPeoplePerGroup)
                                .foregroundColor(.kartForeground)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .frame(maxWidth: 80)
                        }

                        rowDivider()

                        formRow(label: "Chiudi iscrizioni", icon: "clock.fill") {
                            HStack(spacing: 4) {
                                TextField("Es. 3", text: $daysBeforeDeadline)
                                    .foregroundColor(.kartForeground)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.numberPad)
                                    .frame(maxWidth: 60)
                                Text("giorni prima")
                                    .font(.system(size: 11))
                                    .foregroundColor(.kartDim)
                            }
                        }
                    }

                    // ── Regolamento ───────────────────────────────────────
                    formSection(title: "Regolamento", icon: "list.clipboard.fill") {

                        formRow(label: "Peso Min. (kg)", icon: "scalemass") {
                            TextField("Es. 85.0", text: $weightLimit)
                                .foregroundColor(.kartForeground)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 100)
                        }

                        rowDivider()

                        formRow(label: "Kart", icon: "steeringwheel") {
                            TextField("Es. Sodi SR5", text: $kart)
                                .foregroundColor(.kartForeground)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 160)
                        }

                        rowDivider()

                        formRow(label: "Durata Gara", icon: "clock") {
                            HStack(spacing: 4) {
                                TextField("60", text: $raceDuration)
                                    .foregroundColor(.kartForeground)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.numberPad)
                                    .frame(maxWidth: 50)
                                Text("min")
                                    .font(.system(size: 11))
                                    .foregroundColor(.kartDim)
                            }
                        }

                        rowDivider()

                        formRow(label: "Max Stint", icon: "stopwatch") {
                            HStack(spacing: 4) {
                                TextField("30", text: $maxStintDuration)
                                    .foregroundColor(.kartForeground)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.numberPad)
                                    .frame(maxWidth: 50)
                                Text("min")
                                    .font(.system(size: 11))
                                    .foregroundColor(.kartDim)
                            }
                        }
                    }

                    // ── Descrizione ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader(title: "Descrizione", icon: "text.alignleft")

                        ZStack(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("Scrivi una descrizione libera dell'evento...")
                                    .font(.system(size: 13))
                                    .foregroundColor(.kartDim)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $description)
                                .frame(minHeight: 110)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundColor(.kartForeground)
                                .font(.system(size: 13))
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                        }
                        .padding(.bottom, 6)
                    }
                    .background(Color.kartPanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartBorder(opacity: 0.05), lineWidth: 1))

                    // ── Errore ────────────────────────────────────────────
                    if let err = saveError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text(err).font(.system(size: 12)).foregroundColor(.red)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.3), lineWidth: 1))
                    }

                    // ── Azioni ────────────────────────────────────────────
                    VStack(spacing: 12) {

                        // Salva Modifiche
                        Button(action: saveEvent) {
                            HStack(spacing: 10) {
                                if isSaving {
                                    ProgressView()
                                        .tint(isFormValid ? .black : .kartDim)
                                        .scaleEffect(0.85)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 17, weight: .semibold))
                                    Text("Salva Modifiche")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                Spacer()
                            }
                            .foregroundColor(isFormValid ? .black : .kartDim)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                            .background(
                                isFormValid
                                    ? Color.kartAccent
                                    : Color.kartForeground.opacity(0.08)
                            )
                            .cornerRadius(14)
                            .shadow(color: isFormValid ? Color.kartAccent.opacity(0.35) : .clear,
                                    radius: 10, x: 0, y: 4)
                        }
                        .disabled(!isFormValid || isSaving)

                        // Elimina Evento (solo in modifica)
                        if editingEvent != nil {
                            Button(action: { showDeleteConfirm = true }) {
                                HStack(spacing: 10) {
                                    if isDeleting {
                                        ProgressView()
                                            .tint(.red)
                                            .scaleEffect(0.85)
                                    } else {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("Elimina Evento")
                                            .font(.system(size: 15, weight: .bold))
                                    }
                                    Spacer()
                                }
                                .foregroundColor(.red)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.red.opacity(0.4), lineWidth: 1)
                                )
                            }
                            .disabled(isDeleting)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }

            // ── Banner "Modifiche salvate" ─────────────────────────────────
            if showSavedBanner {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Modifiche salvate")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.85))
                            .shadow(color: Color.green.opacity(0.4), radius: 10, x: 0, y: 4)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }
        }
        .alert("Elimina Evento", isPresented: $showDeleteConfirm) {
            Button("Elimina", role: .destructive) { deleteEvent() }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Sei sicuro di voler eliminare questo evento? L'azione non può essere annullata.")
        }
        .onAppear {
            kartodromoVM.fetchAll(serverURL: server.httpURL, token: authState.currentToken)
            populateFields()
        }
    }

    // MARK: - Shared UI components

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.kartAccent)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.kartAccent)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.kartAccent.opacity(0.08))
    }

    private func formSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: title, icon: icon)
            VStack(spacing: 0) { content() }
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartBorder(opacity: 0.05), lineWidth: 1))
    }

    /// Riga standard: icona + etichetta a sx, contenuto a dx (Picker / TextField / DatePicker)
    private func formRow<Content: View>(
        label: String,
        icon: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.kartAccent)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.kartDim)
            Spacer(minLength: 8)
            trailing()
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func rowDivider() -> some View {
        Divider()
            .background(Color.kartForeground.opacity(0.05))
            .padding(.leading, 44)
    }

    // MARK: - Logic

    private func populateFields() {
        guard let ev = editingEvent else { return }
        title    = ev.title
        location = ev.location

        let isoFull  = ISO8601DateFormatter(); isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        let dfT      = DateFormatter(); dfT.dateFormat      = "yyyy-MM-dd'T'HH:mm:ss"
        let dfT2     = DateFormatter(); dfT2.dateFormat     = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        let dfSpace  = DateFormatter(); dfSpace.dateFormat  = "yyyy-MM-dd HH:mm:ss"

        if      let d = isoFull.date(from: ev.eventDate)  { eventDate = d }
        else if let d = isoBasic.date(from: ev.eventDate) { eventDate = d }
        else if let d = dfT.date(from: ev.eventDate)      { eventDate = d }
        else if let d = dfT2.date(from: ev.eventDate)     { eventDate = d }
        else if let d = dfSpace.date(from: ev.eventDate)  { eventDate = d }

        if let v = ev.registrationCost   { registrationCost   = String(v) }
        if let v = ev.maxParticipants    { maxParticipants    = String(v) }
        if let v = ev.minPeoplePerGroup  { minPeoplePerGroup  = String(v) }
        if let v = ev.maxPeoplePerGroup  { maxPeoplePerGroup  = String(v) }
        if let v = ev.weightLimit        { weightLimit        = String(v) }
        if let v = ev.kart               { kart               = v }
        if let v = ev.description        { description        = v }
        if let v = ev.raceDuration       { raceDuration       = String(v) }
        if let v = ev.maxStintDuration   { maxStintDuration   = String(v) }
        if let v = ev.daysBeforeDeadline { daysBeforeDeadline = String(v) }
    }

    private func saveEvent() {
        isSaving  = true
        saveError = nil

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.timeZone   = TimeZone.current

        var data: [String: Any] = [
            "title":      title,
            "location":   location,
            "event_date": fmt.string(from: eventDate)
        ]

        // Campi opzionali: se compilati invia il valore, se svuotati invia null (solo in modifica)
        let isEditing = editingEvent != nil

        if let v = Double(registrationCost) {
            data["registration_cost"] = v
        } else if isEditing {
            data["registration_cost"] = NSNull()
        }

        if let v = Int(maxParticipants) {
            data["max_participants"] = v
        } else if isEditing {
            data["max_participants"] = NSNull()
        }

        if let v = Int(minPeoplePerGroup) {
            data["min_people_per_group"] = v
        } else if isEditing {
            data["min_people_per_group"] = NSNull()
        }

        if let v = Int(maxPeoplePerGroup) {
            data["max_people_per_group"] = v
        } else if isEditing {
            data["max_people_per_group"] = NSNull()
        }

        if let v = Double(weightLimit) {
            data["weight_limit"] = v
        } else if isEditing {
            data["weight_limit"] = NSNull()
        }

        let tk = kart.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tk.isEmpty {
            data["kart"] = tk
        } else if isEditing {
            data["kart"] = NSNull()
        }

        let td = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !td.isEmpty {
            data["description"] = td
        } else if isEditing {
            data["description"] = NSNull()
        }

        if let v = Int(raceDuration) {
            data["race_duration"] = v
        } else if isEditing {
            data["race_duration"] = NSNull()
        }

        if let v = Int(maxStintDuration) {
            data["max_stint_duration"] = v
        } else if isEditing {
            data["max_stint_duration"] = NSNull()
        }

        if let v = Int(daysBeforeDeadline) {
            data["days_before_deadline"] = v
        } else if isEditing {
            data["days_before_deadline"] = NSNull()
        }

        if let ev = editingEvent {
            viewModel.updateEvent(
                serverURL: server.httpURL, eventId: ev.id,
                eventData: data, token: authState.currentToken
            ) { success in
                isSaving = false
                if success {
                    if suppressDismissOnSave {
                        withAnimation(.spring(response: 0.4)) { showSavedBanner = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { showSavedBanner = false }
                            // Aggiorna i dati dopo che il banner è scomparso
                            onSaved?()
                        }
                    } else {
                        onSaved?()
                        dismiss()
                    }
                } else {
                    saveError = "Salvataggio fallito. Riprova."
                }
            }
        } else {
            viewModel.createEvent(
                serverURL: server.httpURL, eventData: data,
                token: authState.currentToken
            ) { success in
                isSaving = false
                if success { onSaved?(); dismiss() }
                else       { saveError = "Creazione fallita. Riprova." }
            }
        }
    }

    private func deleteEvent() {
        guard let ev = editingEvent else { return }
        isDeleting = true
        viewModel.deleteEvent(
            serverURL: server.httpURL, eventId: ev.id,
            token: authState.currentToken
        ) { success in
            isDeleting = false
            if success { onSaved?(); dismiss() }
        }
    }
}

// MARK: - Helpers

private func roundedToQuarterHour(_ date: Date) -> Date {
    let cal     = Calendar.current
    let minutes = cal.component(.minute, from: date)
    return cal.date(bySetting: .minute, value: (minutes / 15) * 15, of: date) ?? date
}

private struct MinuteIntervalKey: EnvironmentKey {
    static let defaultValue: Int = 1
}
extension EnvironmentValues {
    var minuteInterval: Int {
        get { self[MinuteIntervalKey.self] }
        set { self[MinuteIntervalKey.self] = newValue }
    }
}
