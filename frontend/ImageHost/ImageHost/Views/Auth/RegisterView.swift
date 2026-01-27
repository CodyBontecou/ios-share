import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: GoogleSpacing.lg) {
                // Header
                VStack(spacing: GoogleSpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.googleBlue, .googleGreen],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    Text("Create Account")
                        .googleTypography(.headlineMedium)

                    Text("Sign up to start uploading images")
                        .googleTypography(.bodyMedium, color: .googleTextSecondary)
                }
                .padding(.top, GoogleSpacing.lg)
                .padding(.bottom, GoogleSpacing.sm)

                // Form
                VStack(spacing: GoogleSpacing.sm) {
                    GoogleTextField(
                        label: "Email",
                        text: $email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never
                    )

                    GoogleTextField(
                        label: "Password",
                        text: $password,
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
                                isMet: password.count >= 8
                            )
                            PasswordRequirement(
                                text: "Passwords match",
                                isMet: !password.isEmpty && password == confirmPassword
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

                // Register button
                GooglePrimaryButton(
                    title: "Create Account",
                    action: register,
                    isLoading: isLoading,
                    isDisabled: !isFormValid
                )
                .padding(.horizontal, GoogleSpacing.sm)

                Spacer(minLength: GoogleSpacing.xxl)

                // Back to login
                HStack(spacing: GoogleSpacing.xxxs) {
                    Text("Already have an account?")
                        .googleTypography(.bodySmall, color: .googleTextSecondary)
                    GoogleTextButton(title: "Sign In") {
                        dismiss()
                    }
                }
                .padding(.bottom, GoogleSpacing.lg)
            }
        }
        .background(Color.googleSurface)
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isFormValid: Bool {
        !email.isEmpty &&
        email.contains("@") &&
        password.count >= 8 &&
        password == confirmPassword
    }

    private func register() {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await AuthService.shared.register(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
                await MainActor.run {
                    authState.setAuthenticated(response: response)
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

struct PasswordRequirement: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: GoogleSpacing.xxs) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isMet ? Color.googleGreen : Color.googleTextTertiary)
                .font(.system(size: 14))
            Text(text)
                .googleTypography(.bodySmall, color: isMet ? .googleTextPrimary : .googleTextSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        RegisterView()
            .environmentObject(AuthState.shared)
    }
}
