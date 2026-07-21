import SwiftUI

struct NotificationsPanelView: View {
    @ObservedObject var viewModel: UserHomeViewModel
    @Environment(\.dismiss) var dismiss

    /// Evento su cui aprire il sheet di pagamento (se tappato da questa view)
    @State private var activePaymentEvent: RaceEvent? = nil

    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()

                if viewModel.notifications.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.notifications) { notification in
                                NotificationRowView(notification: notification) {
                                    // Marca come letta
                                    viewModel.markNotificationRead(id: notification.id)
                                    // Azione specifica per tipo
                                    if case .pendingPayment(let event) = notification.type {
                                        activePaymentEvent = event
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Notifiche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.unreadCount > 0 {
                        Text("\(viewModel.unreadCount) non lette")
                            .font(.caption)
                            .foregroundColor(.kartDim)
                    }
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
        }
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
                    Text(notification.title)
                        .font(.system(size: 14, weight: notification.isRead ? .regular : .bold))
                        .foregroundColor(.white)
                    Text(notification.message)
                        .font(.system(size: 13))
                        .foregroundColor(.kartDim)
                        .fixedSize(horizontal: false, vertical: true)
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
