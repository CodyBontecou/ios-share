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
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)

                    Text("Verify Your Email")
                        .font(.title)
                        .fontWeight(.bold)

                    if let email = authState.currentUser?.email {
                        Text("We sent a verification code to")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(email)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 10)

                // Info box
                VStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("You need to verify your email before you can upload images.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)

                // Form
                VStack(spacing: 16) {
                    TextField("Verification Code", text: $verificationCode)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                // Messages
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if let successMessage = successMessage {
                    Text(successMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Verify button
                Button(action: verifyEmail) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Verify Email")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(!verificationCode.isEmpty ? Color.blue : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                .disabled(verificationCode.isEmpty || isLoading)
                .padding(.horizontal)

                // Resend code
                Button(action: resendCode) {
                    HStack {
                        if isResending {
                            ProgressView()
                        }
                        Text("Resend Code")
                    }
                }
                .disabled(isResending)
                .font(.footnote)

                Spacer()

                // Logout option
                Button(action: logout) {
                    Text("Log Out")
                        .foregroundStyle(.red)
                }
                .font(.footnote)
                .padding(.bottom, 20)
            }
        }
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
