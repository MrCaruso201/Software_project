import SwiftUI

struct PaymentInfoSheetView: View {
    let event: RaceEvent
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("Seleziona il metodo di pagamento per")
                        .foregroundColor(.kartDim)
                        .font(.headline)
                        .padding(.top, 20)
                    
                    Text(event.title)
                        .foregroundColor(.white)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    if let cost = event.registrationCost {
                        Text("Totale: € \(String(format: "%.2f", cost))")
                            .foregroundColor(.kartAccent)
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    
                    VStack(spacing: 16) {
                        Button(action: {}) {
                            HStack {
                                Image(systemName: "applelogo")
                                Text("Apple Pay")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(10)
                        }
                        
                        Button(action: {}) {
                            HStack {
                                Image(systemName: "creditcard")
                                Text("Google Pay")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(10)
                        }
                        
                        Button(action: {}) {
                            HStack {
                                Image(systemName: "p.square.fill")
                                Text("PayPal")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 0.0, green: 0.45, blue: 0.74)) // Paypal blue
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    .padding(.top, 20)
                    
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Pagamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
        }
    }
}
