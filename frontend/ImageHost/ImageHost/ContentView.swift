import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authState: AuthState
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if authState.isLoading {
                // Loading state with Google branding
                ZStack {
                    Color.googleSurface.ignoresSafeArea()

                    VStack(spacing: GoogleSpacing.lg) {
                        AppLogo(size: 80)

                        ProgressView()
                            .scaleEffect(1.2)

                        Text("Loading...")
                            .googleTypography(.bodyMedium, color: .googleTextSecondary)
                    }
                }
            } else if !authState.isAuthenticated {
                // Not logged in - show login
                LoginView()
            } else if !authState.isEmailVerified {
                // Logged in but email not verified
                EmailVerificationView()
            } else {
                // Fully authenticated - show main app
                TabView(selection: $selectedTab) {
                    HistoryView()
                        .tabItem {
                            Label("Photos", systemImage: "photo.on.rectangle.angled")
                        }
                        .tag(0)

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tag(1)
                }
                .tint(.googleBlue)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthState.shared)
}
