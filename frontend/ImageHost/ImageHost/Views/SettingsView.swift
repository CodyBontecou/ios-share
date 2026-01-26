import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authState: AuthState

    @State private var isTesting = false
    @State private var isLoadingUser = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showClearConfirmation = false
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                // Account Section
                Section {
                    if let user = authState.currentUser {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(user.email)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Plan")
                            Spacer()
                            Text(user.subscriptionTier.capitalized)
                                .foregroundStyle(.secondary)
                        }

                        // Storage usage
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Storage")
                                Spacer()
                                Text("\(user.storageUsedFormatted) / \(user.storageLimitFormatted)")
                                    .foregroundStyle(.secondary)
                            }

                            ProgressView(value: min(user.storagePercentUsed / 100, 1.0))
                                .tint(user.storagePercentUsed > 90 ? .red : .blue)
                        }
                    } else {
                        HStack {
                            Text("Loading account info...")
                            Spacer()
                            if isLoadingUser {
                                ProgressView()
                            }
                        }
                    }

                    Button(action: refreshUserInfo) {
                        HStack {
                            if isLoadingUser {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Refresh Account Info")
                        }
                    }
                    .disabled(isLoadingUser)
                } header: {
                    Text("Account")
                }

                // Actions Section
                Section {
                    Button(action: testConnection) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTesting)

                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Text("Clear Upload History")
                    }
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Connected to \(Config.backendURL)")
                        .foregroundStyle(.green)
                }

                // Logout Section
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Log Out")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
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
                "Log Out",
                isPresented: $showLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Log Out", role: .destructive) {
                    authState.logout()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to log out?")
            }
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

#Preview {
    SettingsView()
        .environmentObject(AuthState.shared)
}
