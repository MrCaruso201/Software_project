import SwiftUI

struct NotificationsPanelView: View {
    @ObservedObject var viewModel: UserHomeViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Evento su cui aprire il sheet di pagamento (se tappato da questa view)
    @State private var activePaymentEvent: RaceEvent? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()

                if viewModel.notifications.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(viewModel.notifications) { notification in
                            NotificationRowView(notification: notification) {
                                // Marca come letta
                                viewModel.markNotificationRead(id: notification.id)
                                if let eventId = notification.associatedEventId {
                                    NotificationCenter.default.post(name: NSNotification.Name("OpenEventDetail"), object: nil, userInfo: ["eventId": eventId])
                                    dismiss()
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.deleteSingleNotification(id: notification.id)
                                } label: {
                                    Label {
                                        Text("Elimina")
                                    } icon: {
                                        Image(uiImage: swipeTrashIcon)
                                            .renderingMode(.original)
                                    }
                                }
                                .tint(colorScheme == .dark ? .white : .black)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .task { viewModel.refreshNotifications() }
            .safeAreaInset(edge: .top) {
                if let error = viewModel.notificationError {
                    VStack(spacing: 8) {
                        Text(error).font(.footnote)
                        Button("Riprova") { viewModel.refreshNotifications() }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.kartPanel)
                }
            }
            .navigationTitle("Notifiche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.deleteAllNotifications()
                    }) {
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.kartRed)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartForeground)
                }
            }
            .sheet(item: $activePaymentEvent) { event in
                PaymentInfoSheetView(event: event)
            }
        }
    }

    private var swipeTrashIcon: UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        guard let symbol = UIImage(systemName: "trash", withConfiguration: configuration) else {
            return UIImage()
        }
        let tintedSymbol = symbol.withTintColor(colorScheme == .dark ? .black : .white,
                                               renderingMode: .alwaysOriginal)
        // Rasterize the symbol so the native swipe control cannot reapply its white symbol tint.
        return UIGraphicsImageRenderer(size: symbol.size).image { _ in
            tintedSymbol.draw(in: CGRect(origin: .zero, size: symbol.size))
        }.withRenderingMode(.alwaysOriginal)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 52))
                .foregroundColor(.kartDim)
            Text("Nessuna notifica")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.kartForeground)
            Text("Quando ci saranno aggiornamenti sulle tue iscrizioni o nuovi eventi, li troverai qui.")
                .font(.subheadline)
                .foregroundColor(.kartDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Notification Row

struct NotificationRowView: View {
    let notification: AppNotification
    let onTap: () -> Void

    private var iconColor: Color {
        switch notification.type {
        case .pendingPayment: return .kartWarning
        case .waitlist:       return .purple
        case .upcomingEvent:  return Color(red: 1.0, green: 0.8, blue: 0.0)
        case .newEvent:       return .green
        case .adminAction(let serverNotif, _):
            switch serverNotif.type {
            case "registration_accepted", "registration_confirmed": return .green
            case "registration_unconfirmed": return .kartWarning
            case "moved_to_waitlist": return .purple
            case "registration_deleted", "release_rejected": return .red
            default: return .blue
            }
        }
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: notification.timestamp, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                // Icona
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: notification.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                // Testi
                VStack(alignment: .leading, spacing: 4) {
                    if let event = notification.associatedEvent {
                        Text(event.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.kartAccent)
                            .textCase(.uppercase)
                    }
                    Text(notification.title)
                        .font(.system(size: 14, weight: notification.isRead ? .regular : .bold))
                        .foregroundColor(.kartForeground)
                    Text(notification.message)
                        .font(.system(size: 13))
                        .foregroundColor(.kartDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(relativeTime)
                        .font(.system(size: 11))
                        .foregroundColor(.kartDim)
                        .padding(.top, 2)
                }

                Spacer()

                // Pallino "non letto"
                if !notification.isRead {
                    Circle()
                        .fill(Color.kartAccent)
                        .frame(width: 9, height: 9)
                        .padding(.top, 4)
                }
            }
            .padding(14)
            .background {
                Color.kartPanel
                if !notification.isRead {
                    iconColor.opacity(0.08)
                }
            }
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        notification.isRead ? Color.clear : iconColor.opacity(0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
