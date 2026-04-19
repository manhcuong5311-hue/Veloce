import SwiftUI
import FirebaseCore
import FirebaseAuth
import Combine
// MARK: - App Entry Point

@main
struct VeloceApp: App {
    @StateObject private var authVM      = AuthViewModel()
    @StateObject private var subManager  = SubscriptionManager.shared
    @StateObject private var vm          = ExpenseViewModel()
    @StateObject private var notifMgr    = NotificationManager.shared
    @StateObject private var ratingMgr   = RatingManager.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        // Set currency and speech language from device locale on first install,
        // before any view renders so formatters always show the right symbol.
        if UserDefaults.standard.string(forKey: "veloce_currency") == nil {
            UserDefaults.standard.set(
                CategoryLocalization.defaultCurrency().rawValue,
                forKey: "veloce_currency"
            )
        }
        if UserDefaults.standard.string(forKey: "veloce_speech_language") == nil {
            UserDefaults.standard.set(
                CategoryLocalization.defaultSpeechCode(),
                forKey: "veloce_speech_language"
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authVM)
                .environmentObject(subManager)
                .environmentObject(vm)
                .environmentObject(notifMgr)
                .environmentObject(ratingMgr)
                .task {
                    try? await CurrencyManager.shared.refreshRates()
                }
                .onOpenURL { url in
                    // Required for Firebase OAuthProvider (Google sign-in) to receive
                    // the redirect callback from SFSafariViewController back into the app.
                    _ = Auth.auth().canHandle(url)
                }
        }
        // Drain any pending background writes before the OS can freeze / terminate the app.
        // This covers the window between a debounced Combine fire and the queue executing.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                print("[VeloceApp] scenePhase → \(newPhase) — flushing persistence queue")
                PersistenceStore.shared.flush()
            }
        }
    }
}

// MARK: - RootView (auth routing)

struct RootView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @AppStorage("veloce_onboarding_done") private var onboardingDone = false

    var body: some View {
        Group {
            if !authVM.isSignedIn {
                AuthView()
                    .transition(.opacity)
            } else if !onboardingDone {
                OnboardingView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ContentView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.38), value: authVM.isSignedIn)
        .animation(.easeInOut(duration: 0.38), value: onboardingDone)
    }
}
