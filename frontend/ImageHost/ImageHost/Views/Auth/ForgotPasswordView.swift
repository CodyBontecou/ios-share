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
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue)

                    Text("Reset Password")
                        .font(.title)
                        .fontWeight(.bold)

                    Text(isEmailSent
                         ? "Check your email for a reset link"
                         : "Enter your email to receive a password reset link")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                .padding(.bottom, 10)

                if isEmailSent {
                    // Success state
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        Text("We've sent a password reset link to:")
                            .foregroundStyle(.secondary)

                        Text(email)
                            .fontWeight(.semibold)

                        Text("Check your spam folder if you don't see it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()

                    // Enter reset code button
                    Button("Enter Reset Code") {
                        showResetPassword = true
                    }
                    .fontWeight(.semibold)
                    .padding()

                    // Send again button
                    Button("Send Again") {
                        isEmailSent = false
                    }
                    .font(.footnote)
                } else {
                    // Form
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Send button
                    Button(action: sendResetEmail) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Send Reset Link")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isFormValid ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!isFormValid || isLoading)
                    .padding(.horizontal)
                }

                Spacer()
            }
        }
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
