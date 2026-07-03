import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authState: AuthState
    
    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()
            
            VStack {
                Spacer()
                
                Button {
                    authState.logout()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.title3)
                        Text("Logout")
                            .font(.title2.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.kartPanel)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 30)
                
                Spacer()
            }
        }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
    }
}
