import SwiftUI
import FirebaseCore

// MARK: - App Entry Point

@main
struct VeloceApp: App {
    @StateObject private var authVM     = AuthViewModel()
    @StateObject private var subManager = SubscriptionManager.shared
    @StateObject private var vm         = ExpenseViewModel()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authVM)
                .environmentObject(subManager)
                .environmentObject(vm)
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
