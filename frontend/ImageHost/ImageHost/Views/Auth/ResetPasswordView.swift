import SwiftUI

struct ResetPasswordView: View {
    @Environment(\.dismiss) var dismiss

    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isResetSuccessful = false

    var body: some View {
        ScrollView {
            VStack(spacing: GoogleSpacing.lg) {
                // Header
                VStack(spacing: GoogleSpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: isResetSuccessful ? [.googleGreen, .googleBlue] : [.googleBlue, .googleRed],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: isResetSuccessful ? "checkmark" : "lock.rotation")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    Text(isResetSuccessful ? "Password Reset!" : "Set New Password")
                        .googleTypography(.headlineMedium)

                    Text(isResetSuccessful
                         ? "You can now sign in with your new password"
                         : "Enter the reset code from your email and your new password")
                        .googleTypography(.bodyMedium, color: .googleTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, GoogleSpacing.lg)
                .padding(.bottom, GoogleSpacing.sm)

                if isResetSuccessful {
                    // Success state
                    GoogleCard(backgroundColor: Color.googleGreen.opacity(0.1)) {
                        HStack(spacing: GoogleSpacing.sm) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: GoogleIconSize.lg))
                                .foregroundStyle(Color.googleGreen)

                            Text("Your password has been updated successfully.")
                                .googleTypography(.bodyMedium, color: .googleTextSecondary)
                        }
                    }
                    .padding(.horizontal, GoogleSpacing.sm)

                    GooglePrimaryButton(
                        title: "Back to Sign In",
                        action: { dismiss() }
                    )
                    .padding(.horizontal, GoogleSpacing.sm)
                } else {
                    // Form
                    VStack(spacing: GoogleSpacing.sm) {
                        GoogleTextField(
                            label: "Reset Code",
                            text: $resetCode,
                            autocapitalization: .never
                        )

                        GoogleTextField(
                            label: "New Password",
                            text: $newPassword,
                            isSecure: true,
                            textContentType: .newPassword
                        )

                        GoogleTextField(
                            label: "Confirm Password",
                            text: $confirmPassword,
                            isSecure: true,
                            textContentType: .newPassword
                        )

                        // Password requirements
                        GoogleCard(backgroundColor: Color.googleSurfaceSecondary, padding: GoogleSpacing.sm) {
                            VStack(alignment: .leading, spacing: GoogleSpacing.xxs) {
                                PasswordRequirement(
                                    text: "At least 8 characters",
                                    isMet: newPassword.count >= 8
                                )
                                PasswordRequirement(
                                    text: "Passwords match",
                                    isMet: !newPassword.isEmpty && newPassword == confirmPassword
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, GoogleSpacing.sm)

                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .googleTypography(.bodySmall, color: .googleError)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, GoogleSpacing.sm)
                    }

                    // Reset button
                    GooglePrimaryButton(
                        title: "Reset Password",
                        action: resetPassword,
                        isLoading: isLoading,
                        isDisabled: !isFormValid
                    )
                    .padding(.horizontal, GoogleSpacing.sm)
                }

                Spacer()
            }
        }
        .background(Color.googleSurface)
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isFormValid: Bool {
        !resetCode.isEmpty &&
        newPassword.count >= 8 &&
        newPassword == confirmPassword
    }

    private func resetPassword() {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await AuthService.shared.resetPassword(
                    token: resetCode.trimmingCharacters(in: .whitespaces),
                    newPassword: newPassword
                )
                await MainActor.run {
                    isResetSuccessful = true
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
        ResetPasswordView()
    }
}
