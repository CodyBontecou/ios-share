import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isEmailSent = false
    @State private var showResetPassword = false

    var body: some View {
        ScrollView {
            VStack(spacing: GoogleSpacing.lg) {
                // Header
                VStack(spacing: GoogleSpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.googleYellow, .googleRed],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "key.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    Text("Reset Password")
                        .googleTypography(.headlineMedium)

                    Text(isEmailSent
                         ? "Check your email for a reset code"
                         : "Enter your email to receive a password reset code")
                        .googleTypography(.bodyMedium, color: .googleTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, GoogleSpacing.lg)
                .padding(.bottom, GoogleSpacing.sm)

                if isEmailSent {
                    // Success state
                    GoogleCard(backgroundColor: Color.googleGreen.opacity(0.1)) {
                        VStack(spacing: GoogleSpacing.sm) {
                            Image(systemName: "envelope.badge.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.googleGreen)

                            Text("We've sent a password reset code to:")
                                .googleTypography(.bodyMedium, color: .googleTextSecondary)

                            Text(email)
                                .googleTypography(.bodyLarge)

                            Text("Check your spam folder if you don't see it.")
                                .googleTypography(.labelSmall, color: .googleTextTertiary)
                        }
                    }
                    .padding(.horizontal, GoogleSpacing.sm)

                    // Enter reset code button
                    GooglePrimaryButton(
                        title: "Enter Reset Code",
                        action: { showResetPassword = true }
                    )
                    .padding(.horizontal, GoogleSpacing.sm)

                    // Send again button
                    GoogleTextButton(title: "Send Again") {
                        isEmailSent = false
                    }
                } else {
                    // Form
                    VStack(spacing: GoogleSpacing.sm) {
                        GoogleTextField(
                            label: "Email",
                            text: $email,
                            keyboardType: .emailAddress,
                            textContentType: .emailAddress,
                            autocapitalization: .never
                        )
                    }
                    .padding(.horizontal, GoogleSpacing.sm)

                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .googleTypography(.bodySmall, color: .googleError)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, GoogleSpacing.sm)
                    }

                    // Send button
                    GooglePrimaryButton(
                        title: "Send Reset Code",
                        action: sendResetEmail,
                        isLoading: isLoading,
                        isDisabled: !isFormValid
                    )
                    .padding(.horizontal, GoogleSpacing.sm)
                }

                Spacer()
            }
        }
        .background(Color.googleSurface)
        .navigationTitle("Forgot Password")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showResetPassword) {
            ResetPasswordView()
        }
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
