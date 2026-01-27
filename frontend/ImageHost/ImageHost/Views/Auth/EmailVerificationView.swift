import SwiftUI

struct EmailVerificationView: View {
    @EnvironmentObject var authState: AuthState

    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var isResending = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: GoogleSpacing.lg) {
                // Header
                VStack(spacing: GoogleSpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.googleBlue, .googleYellow],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    Text("Verify Your Email")
                        .googleTypography(.headlineMedium)

                    if let email = authState.currentUser?.email {
                        Text("We sent a verification code to")
                            .googleTypography(.bodyMedium, color: .googleTextSecondary)

                        Text(email)
                            .googleTypography(.bodyLarge)
                    }
                }
                .padding(.top, GoogleSpacing.xxl)
                .padding(.bottom, GoogleSpacing.sm)

                // Info box
                GoogleCard(backgroundColor: Color.googleBlue.opacity(0.1)) {
                    HStack(spacing: GoogleSpacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: GoogleIconSize.md))
                            .foregroundStyle(Color.googleBlue)

                        Text("You need to verify your email before you can upload images.")
                            .googleTypography(.bodySmall, color: .googleTextSecondary)
                    }
                }
                .padding(.horizontal, GoogleSpacing.sm)

                // Form
                VStack(spacing: GoogleSpacing.sm) {
                    GoogleTextField(
                        label: "Verification Code",
                        text: $verificationCode,
                        autocapitalization: .never
                    )
                }
                .padding(.horizontal, GoogleSpacing.sm)

                // Messages
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .googleTypography(.bodySmall, color: .googleError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, GoogleSpacing.sm)
                }

                if let successMessage = successMessage {
                    Text(successMessage)
                        .googleTypography(.bodySmall, color: .googleGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, GoogleSpacing.sm)
                }

                // Verify button
                GooglePrimaryButton(
                    title: "Verify Email",
                    action: verifyEmail,
                    isLoading: isLoading,
                    isDisabled: verificationCode.isEmpty
                )
                .padding(.horizontal, GoogleSpacing.sm)

                // Resend code
                HStack(spacing: GoogleSpacing.xxs) {
                    if isResending {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    GoogleTextButton(title: "Resend Code", action: resendCode)
                }
                .disabled(isResending)

                Spacer(minLength: GoogleSpacing.xxl)

                // Logout option
                GoogleTextButton(title: "Sign Out", action: logout, color: .googleRed)
                    .padding(.bottom, GoogleSpacing.lg)
            }
        }
        .background(Color.googleSurface)
    }

    private func verifyEmail() {
        guard !verificationCode.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                try await AuthService.shared.verifyEmail(
                    token: verificationCode.trimmingCharacters(in: .whitespaces)
                )
                await MainActor.run {
                    authState.setEmailVerified(true)
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

    private func resendCode() {
        guard let email = authState.currentUser?.email else { return }

        isResending = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                try await AuthService.shared.resendVerification(email: email)
                await MainActor.run {
                    successMessage = "Verification code sent!"
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
                isResending = false
            }
        }
    }

    private func logout() {
        authState.logout()
    }
}

#Preview {
    EmailVerificationView()
        .environmentObject(AuthState.shared)
}
