import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authState: AuthState
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if authState.isLoading {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading...")
                        .foregroundStyle(.secondary)
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
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        .tag(0)

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tag(1)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthState.shared)
}
