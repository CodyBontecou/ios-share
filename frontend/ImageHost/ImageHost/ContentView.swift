import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authState: AuthState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                // First time user - show onboarding
                OnboardingView()
            } else if authState.isLoading {
                // Loading state with brutal design
                ZStack {
                    Color.brutalBackground.ignoresSafeArea()

                    VStack(spacing: 24) {
                        Image("AppIconImage")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        BrutalLoading()
                    }
                }
                .preferredColorScheme(.dark)
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

                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(1)
                }
                .tint(.white)
                .preferredColorScheme(.dark)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthState.shared)
}
