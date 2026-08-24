import SwiftUI

struct NotificationsPanelView: View {
    @ObservedObject var viewModel: UserHomeViewModel
    @Environment(\.dismiss) var dismiss

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
                                if let event = notification.associatedEvent {
                                    NotificationCenter.default.post(name: NSNotification.Name("OpenEventDetail"), object: nil, userInfo: ["eventId": event.id])
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
                                    Label("Elimina", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Notifiche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        viewModel.deleteAllNotifications()
                    }) {
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.kartRed)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
            .sheet(item: $activePaymentEvent) { event in
                PaymentInfoSheetView(event: event)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 52))
                .foregroundColor(.kartDim.opacity(0.5))
            Text("Nessuna notifica")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
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
        case .pendingPayment: return .orange
        case .waitlist:       return .purple
        case .upcomingEvent:  return Color(red: 1.0, green: 0.8, blue: 0.0)
        case .newEvent:       return .green
        case .adminAction(let serverNotif, _):
            switch serverNotif.type {
            case "registration_accepted", "registration_confirmed": return .green
            case "registration_unconfirmed": return .orange
            case "moved_to_waitlist": return .purple
            case "registration_deleted": return .red
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
                        .foregroundColor(.white)
                    Text(notification.message)
                        .font(.system(size: 13))
                        .foregroundColor(.kartDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(relativeTime)
                        .font(.system(size: 11))
                        .foregroundColor(.kartDim.opacity(0.7))
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
            .background(
                notification.isRead
                    ? Color.kartPanel
                    : Color.kartPanel.opacity(0.9)
            )
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
