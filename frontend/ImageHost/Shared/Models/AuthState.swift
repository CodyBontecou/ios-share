import Foundation
import SwiftUI

@MainActor
final class AuthState: ObservableObject {
    static let shared = AuthState()

    @Published var isAuthenticated = false
    @Published var isEmailVerified = false
    @Published var currentUser: User?
    @Published var isLoading = true

    private let keychainService = KeychainService.shared

    private init() {}

    /// Check authentication status on app launch
    func checkAuthStatus() async {
        isLoading = true

        // Check if we have tokens stored
        guard keychainService.hasValidTokens else {
            isAuthenticated = false
            isEmailVerified = false
            currentUser = nil
            isLoading = false
            return
        }

        // Try to get current user to validate token
        do {
            let user = try await AuthService.shared.getCurrentUser()
            currentUser = user
            isAuthenticated = true
            isEmailVerified = user.emailVerified
        } catch {
            // Token might be expired, try to refresh
            do {
                try await AuthService.shared.refreshTokens()
                let user = try await AuthService.shared.getCurrentUser()
                currentUser = user
                isAuthenticated = true
                isEmailVerified = user.emailVerified
            } catch {
                // Refresh failed, user needs to log in again
                logout()
            }
        }

        isLoading = false
    }

    /// Set authenticated state after successful login/register
    func setAuthenticated(response: AuthResponse) {
        // Save tokens
        try? keychainService.saveAccessToken(response.accessToken)
        try? keychainService.saveRefreshToken(response.refreshToken)

        // Calculate and save expiry
        let expiry = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        try? keychainService.saveTokenExpiry(expiry)

        // Update state
        isAuthenticated = true
        isEmailVerified = response.emailVerified

        // Create user from response
        currentUser = User(
            id: response.userId,
            email: response.email,
            subscriptionTier: response.subscriptionTier,
            emailVerified: response.emailVerified,
            storageUsedBytes: 0,
            storageLimitBytes: 0
        )
    }

    /// Update email verified status
    func setEmailVerified(_ verified: Bool) {
        isEmailVerified = verified
        if var user = currentUser {
            currentUser = User(
                id: user.id,
                email: user.email,
                subscriptionTier: user.subscriptionTier,
                emailVerified: verified,
                storageUsedBytes: user.storageUsedBytes,
                storageLimitBytes: user.storageLimitBytes
            )
        }
    }

    /// Update current user
    func updateUser(_ user: User) {
        currentUser = user
        isEmailVerified = user.emailVerified
    }

    /// Logout and clear all tokens
    func logout() {
        keychainService.clearAllTokens()
        isAuthenticated = false
        isEmailVerified = false
        currentUser = nil
    }
}
