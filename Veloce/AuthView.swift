import SwiftUI
import AuthenticationServices

// MARK: - AuthView

struct AuthView: View {
    @EnvironmentObject private var authVM: AuthViewModel

    @State private var showEmailForm = false
    @State private var isSignUp      = false
    @State private var email         = ""
    @State private var password      = ""
    @State private var logoScale     = 0.7
    @State private var logoOpacity   = 0.0
    @State private var buttonsOffset = 40.0
    @State private var buttonsOpacity = 0.0

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer()
                logoSection
                Spacer()
                Spacer()
                authButtons
                    .padding(.horizontal, 28)
                    .padding(.bottom, 52)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { animateEntrance() }
        .alert("Sign In Error", isPresented: .constant(authVM.errorMessage != nil)) {
            Button("OK") { authVM.errorMessage = nil }
        } message: {
            Text(authVM.errorMessage ?? "")
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(hex: "0C0918").ignoresSafeArea()

            // Purple glow top
            Circle()
                .fill(Color(hex: "7B6CF0").opacity(0.18))
                .frame(width: 500)
                .blur(radius: 90)
                .offset(x: 60, y: -260)

            // Teal accent bottom
            Circle()
                .fill(Color(hex: "4B3BD4").opacity(0.12))
                .frame(width: 360)
                .blur(radius: 70)
                .offset(x: -120, y: 320)
        }
    }

    // MARK: - Logo

    private var logoSection: some View {
        VStack(spacing: 24) {
            // App icon with glow
            ZStack {
                // Outer glow
                Circle()
                    .fill(Color(hex: "7B6CF0").opacity(0.25))
                    .frame(width: 130)
                    .blur(radius: 28)

                // Icon circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "A092F8"), Color(hex: "6B5CE7")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                    .shadow(color: Color(hex: "7B6CF0").opacity(0.6), radius: 28, y: 12)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)

            VStack(spacing: 10) {
                Text("Veloce")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(-0.5)

                Text("Your money, made simple.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(0.1)
            }
            .opacity(logoOpacity)
        }
    }

    // MARK: - Auth Buttons

    @ViewBuilder
    private var authButtons: some View {
        VStack(spacing: 11) {
            // ── Apple ──────────────────────────────────────────
            SignInWithAppleButton(isSignUp ? .signUp : .signIn) { request in
                request.requestedScopes = [.fullName, .email]
                request.nonce           = authVM.prepareAppleNonce()
            } onCompletion: { result in
                Task { await authVM.handleAppleResult(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // ── Google ─────────────────────────────────────────
            darkAuthButton(
                label: "Continue with Google",
                icon:  "globe"
            ) {
                authVM.signInWithGoogle()
            }

            // ── Divider ────────────────────────────────────────
            HStack(spacing: 12) {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                Text("or")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
                    .fixedSize()
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }
            .padding(.vertical, 2)

            // ── Email form / button ────────────────────────────
            if showEmailForm {
                emailForm
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal:   .opacity
                        )
                    )
            } else {
                Button(action: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        showEmailForm = true
                    }
                }) {
                    Text("Continue with Email")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .transition(.opacity)
            }
        }
        .offset(y: buttonsOffset)
        .opacity(buttonsOpacity)
    }

    // MARK: - Email Form

    @ViewBuilder
    private var emailForm: some View {
        VStack(spacing: 10) {
            authTextField("Email", text: $email, icon: "envelope",
                          keyboard: .emailAddress, content: .emailAddress, secure: false)

            authTextField("Password", text: $password, icon: "lock",
                          keyboard: .default,
                          content: isSignUp ? .newPassword : .password, secure: true)

            // Primary CTA
            Button(action: handleEmailAuth) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "A092F8"), Color(hex: "6B5CE7")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 54)
                        .shadow(color: Color(hex: "7B6CF0").opacity(0.4), radius: 14, y: 6)

                    if authVM.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty ||
                      password.isEmpty ||
                      authVM.isLoading)

            // Toggle mode
            Button(action: {
                withAnimation(.spring(response: 0.3)) { isSignUp.toggle() }
            }) {
                Text(
                    isSignUp
                    ? "Already have an account? **Sign In**"
                    : "New here? **Create Account**"
                )
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.38))
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Reusable dark button

    @ViewBuilder
    private func darkAuthButton(
        label: String,
        icon:  String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 24)

                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.11), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - TextField helper

    @ViewBuilder
    private func authTextField(
        _ placeholder: String,
        text:          Binding<String>,
        icon:          String,
        keyboard:      UIKeyboardType,
        content:       UITextContentType?,
        secure:        Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 18)

            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(keyboard)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(Color(hex: "A092F8"))
            .if(content != nil) { $0.textContentType(content!) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                )
        )
    }

    // MARK: - Actions

    private func handleEmailAuth() {
        Task {
            if isSignUp {
                await authVM.signUpWithEmail(email.trimmingCharacters(in: .whitespaces), password)
            } else {
                await authVM.signInWithEmail(email.trimmingCharacters(in: .whitespaces), password)
            }
        }
    }

    private func animateEntrance() {
        withAnimation(.spring(response: 0.75, dampingFraction: 0.78).delay(0.05)) {
            logoScale   = 1.0
            logoOpacity = 1.0
        }
        withAnimation(.spring(response: 0.65, dampingFraction: 0.82).delay(0.25)) {
            buttonsOffset  = 0
            buttonsOpacity = 1.0
        }
    }
}

// MARK: - Conditional modifier helper

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Preview

#Preview {
    AuthView().environmentObject(AuthViewModel())
}
