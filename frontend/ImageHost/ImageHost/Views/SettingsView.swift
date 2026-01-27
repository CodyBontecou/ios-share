import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    @State private var isTesting = false
    @State private var isLoadingUser = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showClearConfirmation = false
    @State private var showLogoutConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: GoogleSpacing.lg) {
                // Profile Header Card
                if let user = authState.currentUser {
                    ProfileHeaderCard(user: user, isLoading: isLoadingUser)
                        .padding(.horizontal, GoogleSpacing.sm)
                        .padding(.top, GoogleSpacing.sm)
                }

                // Storage Section
                if let user = authState.currentUser {
                    StorageCard(user: user)
                        .padding(.horizontal, GoogleSpacing.sm)
                }

                // Actions Section
                GoogleCard(padding: 0) {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "arrow.clockwise",
                            title: "Refresh Account",
                            subtitle: "Update storage and plan info",
                            iconColor: .googleBlue,
                            showChevron: false
                        ) {
                            refreshUserInfo()
                        }
                        .padding(.horizontal, GoogleSpacing.sm)
                        .overlay(alignment: .trailing) {
                            if isLoadingUser {
                                ProgressView()
                                    .padding(.trailing, GoogleSpacing.sm)
                            }
                        }
                        .disabled(isLoadingUser)

                        Divider().padding(.leading, GoogleSpacing.xxxl + GoogleSpacing.sm)

                        SettingsRow(
                            icon: "wifi",
                            title: "Test Connection",
                            subtitle: "Verify server connectivity",
                            iconColor: .googleGreen,
                            showChevron: false
                        ) {
                            testConnection()
                        }
                        .padding(.horizontal, GoogleSpacing.sm)
                        .overlay(alignment: .trailing) {
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, GoogleSpacing.sm)
                            }
                        }
                        .disabled(isTesting)

                        Divider().padding(.leading, GoogleSpacing.xxxl + GoogleSpacing.sm)

                        SettingsRow(
                            icon: "trash",
                            title: "Clear Upload History",
                            subtitle: "Remove local history only",
                            iconColor: .googleRed,
                            showChevron: false
                        ) {
                            showClearConfirmation = true
                        }
                        .padding(.horizontal, GoogleSpacing.sm)
                    }
                }
                .padding(.horizontal, GoogleSpacing.sm)

                // Server Info
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.googleGreen)
                    Text("Connected to \(Config.backendURL)")
                        .googleTypography(.labelSmall, color: .googleTextTertiary)
                }
                .padding(.top, GoogleSpacing.xxs)

                // Logout Section
                GoogleCard(padding: 0) {
                    Button {
                        showLogoutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .googleTypography(.labelLarge, color: .googleRed)
                            Spacer()
                        }
                        .padding(.vertical, GoogleSpacing.sm)
                    }
                }
                .padding(.horizontal, GoogleSpacing.sm)
                .padding(.top, GoogleSpacing.sm)

                Spacer(minLength: GoogleSpacing.xxl)
            }
        }
        .background(Color.googleSurface)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if authState.currentUser == nil || authState.currentUser?.storageUsedBytes == 0 {
                refreshUserInfo()
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog(
            "Clear History",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All History", role: .destructive) {
                clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all upload history from this device. Images on the server will not be affected.")
        }
        .confirmationDialog(
            "Sign Out",
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                authState.logout()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    private func refreshUserInfo() {
        isLoadingUser = true

        Task {
            do {
                let user = try await AuthService.shared.getCurrentUser()
                await MainActor.run {
                    authState.updateUser(user)
                    isLoadingUser = false
                }
            } catch {
                await MainActor.run {
                    showError(title: "Error", message: "Failed to load account info: \(error.localizedDescription)")
                    isLoadingUser = false
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true

        Task {
            do {
                try await UploadService.shared.testConnection()
                await MainActor.run {
                    showError(title: "Success", message: "Connection test successful!")
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    showError(title: "Connection Failed", message: error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }

    private func clearHistory() {
        do {
            try HistoryService.shared.clear()
            showError(title: "History Cleared", message: "All upload history has been removed.")
        } catch {
            showError(title: "Error", message: "Failed to clear history: \(error.localizedDescription)")
        }
    }

    private func showError(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

// MARK: - Profile Header Card

struct ProfileHeaderCard: View {
    let user: User
    let isLoading: Bool

    var body: some View {
        GoogleCard {
            HStack(spacing: GoogleSpacing.sm) {
                AvatarView(email: user.email, size: 56, backgroundColor: .googleBlue)

                VStack(alignment: .leading, spacing: GoogleSpacing.xxxs) {
                    Text(user.email)
                        .googleTypography(.titleMedium)
                        .lineLimit(1)

                    HStack(spacing: GoogleSpacing.xxs) {
                        PlanBadge(tier: user.subscriptionTier)

                        if user.emailVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.googleGreen)
                        }
                    }
                }

                Spacer()
            }
        }
    }
}

// MARK: - Plan Badge

struct PlanBadge: View {
    let tier: String

    private var badgeColor: Color {
        switch tier.lowercased() {
        case "premium", "pro":
            return .googleYellow
        case "enterprise":
            return .googleBlue
        default:
            return .googleTextTertiary
        }
    }

    var body: some View {
        Text(tier.capitalized)
            .googleTypography(.labelSmall, color: badgeColor)
            .padding(.horizontal, GoogleSpacing.xxs)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: GoogleCornerRadius.xs)
                    .fill(badgeColor.opacity(0.15))
            )
    }
}

// MARK: - Storage Card

struct StorageCard: View {
    let user: User

    var body: some View {
        GoogleCard {
            VStack(spacing: GoogleSpacing.sm) {
                HStack {
                    Text("Storage")
                        .googleTypography(.titleSmall)
                    Spacer()
                }

                HStack(alignment: .center, spacing: GoogleSpacing.lg) {
                    CircularStorageView(
                        usedBytes: user.storageUsedBytes,
                        limitBytes: user.storageLimitBytes,
                        size: 100,
                        lineWidth: 10
                    )

                    VStack(alignment: .leading, spacing: GoogleSpacing.xxs) {
                        StorageDetailRow(
                            color: user.storagePercentUsed > 90 ? .googleRed : .googleBlue,
                            label: "Used",
                            value: user.storageUsedFormatted
                        )
                        StorageDetailRow(
                            color: .googleOutline,
                            label: "Available",
                            value: formatAvailable(user)
                        )
                        StorageDetailRow(
                            color: .googleTextTertiary,
                            label: "Total",
                            value: user.storageLimitFormatted
                        )
                    }

                    Spacer()
                }
            }
        }
    }

    private func formatAvailable(_ user: User) -> String {
        let available = user.storageLimitBytes - user.storageUsedBytes
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(max(0, available)))
    }
}

// MARK: - Storage Detail Row

struct StorageDetailRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: GoogleSpacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .googleTypography(.labelSmall, color: .googleTextSecondary)
            Spacer()
            Text(value)
                .googleTypography(.labelMedium)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthState.shared)
    }
}
