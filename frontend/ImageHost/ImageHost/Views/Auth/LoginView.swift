import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authState: AuthState

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var isAppleSignInLoading = false
    @State private var errorMessage: String?
    @State private var showRegister = false
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GoogleSpacing.lg) {
                    // App Logo
                    VStack(spacing: GoogleSpacing.sm) {
                        AppLogo(size: 100)

                        Text("ImageHost")
                            .googleTypography(.headlineLarge)

                        Text("Sign in to your account")
                            .googleTypography(.bodyMedium, color: .googleTextSecondary)
                    }
                    .padding(.top, GoogleSpacing.xxl)
                    .padding(.bottom, GoogleSpacing.md)

                    // Sign in with Apple Button
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        handleAppleSignInResult(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: GoogleCornerRadius.full))
                    .padding(.horizontal, GoogleSpacing.sm)
                    .disabled(isAppleSignInLoading || isLoading)
                    .overlay {
                        if isAppleSignInLoading {
                            RoundedRectangle(cornerRadius: GoogleCornerRadius.full)
                                .fill(Color.black.opacity(0.3))
                            ProgressView()
                                .tint(.white)
                        }
                    }

                    // Divider
                    GoogleDivider(label: "or")
                        .padding(.horizontal, GoogleSpacing.sm)

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
                            textContentType: .password
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

                    // Login button
                    GooglePrimaryButton(
                        title: "Sign In",
                        action: login,
                        isLoading: isLoading,
                        isDisabled: !isFormValid
                    )
                    .padding(.horizontal, GoogleSpacing.sm)

                    // Forgot password
                    GoogleTextButton(title: "Forgot Password?") {
                        showForgotPassword = true
                    }

                    Spacer(minLength: GoogleSpacing.xxl)

                    // Register link
                    HStack(spacing: GoogleSpacing.xxxs) {
                        Text("Don't have an account?")
                            .googleTypography(.bodySmall, color: .googleTextSecondary)
                        GoogleTextButton(title: "Create Account") {
                            showRegister = true
                        }
                    }
                    .padding(.bottom, GoogleSpacing.lg)
                }
            }
            .background(Color.googleSurface)
            .navigationDestination(isPresented: $showRegister) {
                RegisterView()
            }
            .navigationDestination(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
        }
    }

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }

    private func login() {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await AuthService.shared.login(
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

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Invalid Apple ID credential."
                return
            }

            guard let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = "Could not retrieve identity token."
                return
            }

            let appleResult = AppleSignInResult(
                identityToken: identityToken,
                userIdentifier: appleIDCredential.user,
                email: appleIDCredential.email,
                fullName: appleIDCredential.fullName
            )

            signInWithApple(result: appleResult)

        case .failure(let error):
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                return
            }
            errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
        }
    }

    private func signInWithApple(result: AppleSignInResult) {
        isAppleSignInLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await AuthService.shared.signInWithApple(result: result)
                await MainActor.run {
                    authState.setAuthenticated(response: response)
                }
            } catch let error as AuthError {
                await MainActor.run {
                    errorMessage = error.errorDescription
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Apple Sign-In failed. Please try again."
                }
            }

            await MainActor.run {
                isAppleSignInLoading = false
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthState.shared)
}
