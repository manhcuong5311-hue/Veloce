import SwiftUI
import FirebaseAuth
import AuthenticationServices
import CryptoKit
import Combine
// MARK: - AuthViewModel

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var currentUser: User?
    @Published var isLoading    = false
    @Published var errorMessage: String?

    /// True when signed in with a real (non-anonymous) account
    var isSignedIn: Bool {
        guard let u = currentUser else { return false }
        return !u.isAnonymous
    }

    // Stored during Apple sign-in request so the completion handler can use it
    private(set) var pendingNonce: String = ""
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        currentUser = Auth.auth().currentUser
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.currentUser = user }
        }
    }

    deinit {
        if let h = handle { Auth.auth().removeStateDidChangeListener(h) }
    }

    // MARK: - Apple Sign-In

    /// Call this before presenting the Apple sign-in button to prepare a nonce.
    /// Returns the SHA-256 hash of the nonce (pass to ASAuthorizationAppleIDRequest.nonce).
    func prepareAppleNonce() -> String {
        let nonce = randomNonce()
        pendingNonce = nonce
        return sha256(nonce)
    }

    func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard
                let cred       = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData  = cred.identityToken,
                let tokenStr   = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Unable to read Apple credentials."
                return
            }
            let firebaseCred = OAuthProvider.appleCredential(
                withIDToken: tokenStr,
                rawNonce:    pendingNonce,
                fullName:    cred.fullName
            )
            await performSignIn(firebaseCred)

        case .failure(let error):
            // Ignore cancel
            let nsErr = error as NSError
            guard nsErr.code != ASAuthorizationError.canceled.rawValue else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Google Sign-In (stub)
    // To enable Google Sign-In:
    // 1. Add package: https://github.com/google/GoogleSignIn-iOS
    // 2. Add REVERSED_CLIENT_ID from GoogleService-Info.plist as a URL scheme in Info.plist
    // 3. Replace this stub with the GIDSignIn implementation

    func signInWithGoogle() {
        errorMessage = "Google Sign-In coming soon. Use Apple or Email for now."
    }

    // MARK: - Email / Password

    func signInWithEmail(_ email: String, _ password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = friendlyError(error)
        }
        isLoading = false
    }

    func signUpWithEmail(_ email: String, _ password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            errorMessage = friendlyError(error)
        }
        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        try? Auth.auth().signOut()
        UserDefaults.standard.removeObject(forKey: "veloce_onboarding_done")
    }

    // MARK: - Private Helpers

    private func performSignIn(_ credential: AuthCredential) async {
        isLoading = true
        do {
            try await Auth.auth().signIn(with: credential)
        } catch {
            errorMessage = friendlyError(error)
        }
        isLoading = false
    }

    private func friendlyError(_ error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .wrongPassword:     return "Incorrect password. Please try again."
        case .userNotFound:      return "No account found. Try creating one."
        case .emailAlreadyInUse: return "That email is already in use. Sign in instead."
        case .weakPassword:      return "Password must be at least 6 characters."
        case .invalidEmail:      return "Please enter a valid email address."
        case .networkError:      return "Network error. Check your connection."
        default:                 return error.localizedDescription
        }
    }

    private func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return bytes.map { String(chars[Int($0) % chars.count]) }.joined()
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}
