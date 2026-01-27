import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var subscriptionState: SubscriptionState
    @Environment(\.dismiss) var dismiss

    @State private var isTesting = false
    @State private var isLoadingUser = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showClearConfirmation = false
    @State private var showLogoutConfirmation = false
    @State private var selectedLinkFormat: LinkFormat = LinkFormatService.shared.currentFormat
    @State private var customLinkTemplate: String = LinkFormatService.shared.customTemplate
    @State private var showCustomFormatSheet = false

    var body: some View {
        ZStack {
            Color.brutalBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SET-\nTINGS")
                            .font(.system(size: 56, weight: .black))
                            .foregroundStyle(.white)
                            .lineSpacing(-8)

                        HStack {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 24, height: 1)

                            Text("ACCOUNT & PREFERENCES")
                                .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                                .tracking(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 32)

                    // Profile Section
                    if let user = authState.currentUser {
                        VStack(spacing: 0) {
                            BrutalSectionHeader(title: "Account")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 12)

                            BrutalCard {
                                HStack(spacing: 16) {
                                    BrutalAvatar(text: user.email, size: 48)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(user.email)
                                            .brutalTypography(.bodyLarge)
                                            .lineLimit(1)

                                        HStack(spacing: 8) {
                                            BrutalBadge(
                                                text: user.subscriptionTier,
                                                style: user.subscriptionTier.lowercased() == "free" ? .default : .success
                                            )

                                            if user.emailVerified {
                                                Text("✓ VERIFIED")
                                                    .brutalTypography(.monoSmall, color: .brutalSuccess)
                                                    .tracking(1)
                                            }
                                        }
                                    }

                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.bottom, 24)
                    }

                    // Storage Section
                    if let user = authState.currentUser {
                        VStack(spacing: 0) {
                            BrutalSectionHeader(title: "Storage")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 12)

                            BrutalCard {
                                VStack(spacing: 16) {
                                    HStack {
                                        Text(user.storageUsedFormatted)
                                            .brutalTypography(.titleLarge)

                                        Text("/")
                                            .brutalTypography(.titleLarge, color: .brutalTextTertiary)

                                        Text(user.storageLimitFormatted)
                                            .brutalTypography(.titleLarge, color: .brutalTextSecondary)

                                        Spacer()

                                        Text("\(user.storagePercentUsed)%")
                                            .brutalTypography(.mono, color: user.storagePercentUsed > 90 ? .brutalError : .brutalTextSecondary)
                                    }

                                    BrutalProgressBar(progress: Double(user.storagePercentUsed) / 100.0)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.bottom, 24)
                    }

                    // Subscription Section
                    SubscriptionStatusView()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)

                    // Link Format Section
                    VStack(spacing: 0) {
                        BrutalSectionHeader(title: "Link Format")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)

                        BrutalCard(showBorder: true) {
                            VStack(spacing: 0) {
                                ForEach(Array(LinkFormat.allCases.enumerated()), id: \.element.id) { index, format in
                                    if index > 0 {
                                        Rectangle()
                                            .fill(Color.brutalBorder)
                                            .frame(height: 1)
                                    }

                                    Button {
                                        selectedLinkFormat = format
                                        LinkFormatService.shared.currentFormat = format
                                        if format == .custom {
                                            showCustomFormatSheet = true
                                        }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(format.displayName)
                                                    .brutalTypography(.body)

                                                Text(format == .custom ? customLinkTemplate : format.previewExample)
                                                    .brutalTypography(.monoSmall, color: .brutalTextTertiary)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            if selectedLinkFormat == format {
                                                Text("*")
                                                    .brutalTypography(.titleLarge, color: .brutalSuccess)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        // Edit custom format button
                        if selectedLinkFormat == .custom {
                            Button {
                                showCustomFormatSheet = true
                            } label: {
                                HStack {
                                    Text("EDIT CUSTOM FORMAT")
                                        .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                                        .tracking(1)
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.brutalTextSecondary)
                                }
                            }
                            .padding(.top, 12)
                        }

                        // Template variables hint
                        HStack(spacing: 8) {
                            Text("Variables:")
                                .brutalTypography(.monoSmall, color: .brutalTextTertiary)
                            Text("{url}")
                                .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                            Text("{filename}")
                                .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                        }
                        .padding(.top, 12)
                    }
                    .padding(.bottom, 24)

                    // Actions Section
                    VStack(spacing: 0) {
                        BrutalSectionHeader(title: "Actions")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)

                        BrutalCard(showBorder: true) {
                            VStack(spacing: 0) {
                                BrutalRow(
                                    title: "Refresh Account",
                                    subtitle: "Update storage and plan info",
                                    showChevron: true
                                ) {
                                    refreshUserInfo()
                                }
                                .overlay(alignment: .trailing) {
                                    if isLoadingUser {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                }
                                .disabled(isLoadingUser)

                                Rectangle()
                                    .fill(Color.brutalBorder)
                                    .frame(height: 1)

                                BrutalRow(
                                    title: "Test Connection",
                                    subtitle: "Verify server connectivity",
                                    showChevron: true
                                ) {
                                    testConnection()
                                }
                                .overlay(alignment: .trailing) {
                                    if isTesting {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                }
                                .disabled(isTesting)

                                Rectangle()
                                    .fill(Color.brutalBorder)
                                    .frame(height: 1)

                                BrutalRow(
                                    title: "Clear Upload History",
                                    subtitle: "Remove local history only",
                                    destructive: true
                                ) {
                                    showClearConfirmation = true
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 24)

                    // Server Info
                    HStack(spacing: 8) {
                        Text("●")
                            .brutalTypography(.monoSmall, color: .brutalSuccess)

                        Text(Config.backendURL)
                            .brutalTypography(.monoSmall, color: .brutalTextTertiary)
                    }
                    .padding(.bottom, 24)

                    // Sign Out
                    BrutalSecondaryButton(title: "Sign Out") {
                        showLogoutConfirmation = true
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brutalBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Text("DONE")
                        .brutalTypography(.mono)
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
        .sheet(isPresented: $showCustomFormatSheet) {
            CustomLinkFormatSheet(
                template: $customLinkTemplate,
                onSave: {
                    LinkFormatService.shared.customTemplate = customLinkTemplate
                }
            )
        }
        .preferredColorScheme(.dark)
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

// MARK: - Custom Link Format Sheet

struct CustomLinkFormatSheet: View {
    @Binding var template: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editingTemplate: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brutalBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CUSTOM\nFORMAT")
                            .font(.system(size: 40, weight: .black))
                            .foregroundStyle(.white)
                            .lineSpacing(-4)

                        Text("Define your own link template")
                            .brutalTypography(.body, color: .brutalTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                    // Template input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TEMPLATE")
                            .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                            .tracking(2)

                        TextField("Enter template...", text: $editingTemplate, axis: .vertical)
                            .textFieldStyle(.plain)
                            .brutalTypography(.mono)
                            .padding(16)
                            .background(Color.brutalSurface)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.brutalBorder, lineWidth: 1)
                            )
                            .lineLimit(3...6)
                    }
                    .padding(.horizontal, 24)

                    // Variables reference
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AVAILABLE VARIABLES")
                            .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                            .tracking(2)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("{url}")
                                    .brutalTypography(.mono, color: .brutalSuccess)
                                Text("- The image URL")
                                    .brutalTypography(.bodySmall, color: .brutalTextTertiary)
                            }
                            HStack {
                                Text("{filename}")
                                    .brutalTypography(.mono, color: .brutalSuccess)
                                Text("- Original filename")
                                    .brutalTypography(.bodySmall, color: .brutalTextTertiary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.brutalSurface)
                    }
                    .padding(.horizontal, 24)

                    // Preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PREVIEW")
                            .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                            .tracking(2)

                        Text(LinkFormatService.shared.preview(format: .custom, customTemplate: editingTemplate))
                            .brutalTypography(.monoSmall, color: .brutalTextPrimary)
                            .lineLimit(3)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.brutalSurfaceElevated)
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Save button
                    BrutalPrimaryButton(title: "Save Format") {
                        template = editingTemplate
                        onSave()
                        dismiss()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brutalBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("CANCEL")
                            .brutalTypography(.mono)
                    }
                }
            }
            .onAppear {
                editingTemplate = template
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthState.shared)
            .environmentObject(SubscriptionState.shared)
    }
}
