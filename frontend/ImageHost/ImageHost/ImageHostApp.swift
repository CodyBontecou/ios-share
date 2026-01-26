import SwiftUI

@main
struct ImageHostApp: App {
    @StateObject private var authState = AuthState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authState)
                .task {
                    await authState.checkAuthStatus()
                }
        }
    }
}
