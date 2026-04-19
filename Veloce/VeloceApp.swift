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
