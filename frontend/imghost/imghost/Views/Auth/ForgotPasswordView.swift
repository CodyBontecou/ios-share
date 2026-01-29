import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isEmailSent = false
    @State private var showResetPassword = false

    var body: some View {
        ZStack {
            Color.brutalBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero text
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RESET\nPASS-\nWORD")
                            .font(.system(size: 56, weight: .black))
                            .foregroundStyle(.white)
                            .lineSpacing(-8)

                        HStack {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 24, height: 1)

                            Text(isEmailSent ? "CHECK YOUR EMAIL" : "ENTER YOUR EMAIL")
                                .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                                .tracking(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 40)

                    if isEmailSent {
                        // Success state
                        VStack(spacing: 24) {
                            BrutalCard(backgroundColor: .brutalSurface) {
                                VStack(spacing: 16) {
                                    Text("✓")
                                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.brutalSuccess)

                                    Text("RESET CODE SENT TO:")
                                        .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                                        .tracking(2)

                                    Text(email)
                                        .brutalTypography(.bodyLarge)

                                    Text("Check your spam folder if you don't see it.")
                                        .brutalTypography(.bodySmall, color: .brutalTextTertiary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 24)

                            BrutalPrimaryButton(
                                title: "Enter Reset Code",
                                action: { showResetPassword = true }
                            )
                            .padding(.horizontal, 24)

                            BrutalTextButton(title: "Send Again") {
                                isEmailSent = false
                            }
                        }
                    } else {
                        // Form
                        VStack(spacing: 24) {
                            BrutalTextField(
                                label: "Email",
                                text: $email,
                                keyboardType: .emailAddress,
                                textContentType: .emailAddress,
                                autocapitalization: .never
                            )
                            .padding(.horizontal, 24)

                            // Error message
                            if let errorMessage = errorMessage {
                                Text(errorMessage.uppercased())
                                    .brutalTypography(.monoSmall, color: .brutalError)
                                    .tracking(1)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }

                            BrutalPrimaryButton(
                                title: "Send Reset Code",
                                action: sendResetEmail,
                                isLoading: isLoading,
                                isDisabled: !isFormValid
                            )
                            .padding(.horizontal, 24)
                        }
                    }

                    Spacer()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brutalBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showResetPassword) {
            ResetPasswordView()
        }
        .preferredColorScheme(.dark)
    }

    private var isFormValid: Bool {
        !email.isEmpty && email.contains("@")
    }

    private func sendResetEmail() {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await AuthService.shared.forgotPassword(
                    email: email.trimmingCharacters(in: .whitespaces)
                )
                await MainActor.run {
                    isEmailSent = true
                }
            } catch let error as AuthError {
                await MainActor.run {
                    errorMessage = error.errorDescription
                }
            } catch {
                await MainActor.run {
                    errorMessage = "An unexpected error occurred."
                }
            }

            await MainActor.run {
                isLoading = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        ForgotPasswordView()
    }
}
