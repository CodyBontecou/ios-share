import SwiftUI
import StoreKit

@main
struct ImageHostApp: App {
    @StateObject private var authState = AuthState.shared
    @StateObject private var subscriptionState = SubscriptionState.shared

    init() {
        // Start listening for StoreKit transactions immediately
        Task {
            await StoreKitManager.shared.startListening()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authState)
                .environmentObject(subscriptionState)
                .task {
                    // Check auth status first
                    await authState.checkAuthStatus()

                    // Load StoreKit products
                    await StoreKitManager.shared.loadProducts()

                    // Check subscription status if authenticated
                    if authState.isAuthenticated && authState.isEmailVerified {
                        await subscriptionState.checkStatus()
                    }
                }
        }
    }
}
