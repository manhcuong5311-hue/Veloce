import SwiftUI
import FirebaseAuth
import Combine
// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var authVM:     AuthViewModel
    @EnvironmentObject private var subManager: SubscriptionManager
    @EnvironmentObject private var vm:         ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("veloce_ai_suggestions") private var aiSuggestionsEnabled = true
    @State private var showPaywall         = false
    @State private var showSignOutConfirm  = false

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                List {
                    accountSection
                    subscriptionSection
                    preferencesSection
                    aboutSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subManager)
        }
        .confirmationDialog(
            "Sign out of Veloce?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) { authVM.signOut() }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            if let user = authVM.currentUser {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(VeloceTheme.accentBg)
                            .frame(width: 46, height: 46)
                        Text(userInitial(user))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(VeloceTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.displayName ?? "Veloce User")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textPrimary)
                        Text(user.email ?? user.uid)
                            .font(.system(size: 13))
                            .foregroundStyle(VeloceTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if subManager.isProUser {
                        Text("PRO")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(VeloceTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(VeloceTheme.accentBg, in: Capsule())
                    }
                }
                .padding(.vertical, 4)
            }

            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        Section {
            if subManager.isProUser {
                HStack {
                    Label("Pro — Active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(VeloceTheme.ok)
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text("Unlimited")
                        .font(.system(size: 13))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            } else {
                Button(action: { showPaywall = true }) {
                    HStack {
                        Label("Upgrade to Pro", systemImage: "sparkles")
                            .foregroundStyle(VeloceTheme.accent)
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text("$14.99 / yr")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textTertiary)
                    }
                }
            }

            Button(action: {
                Task { await subManager.restorePurchases() }
            }) {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .font(.system(size: 14))
            }
        } header: {
            Text("Subscription")
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        Section {
            Toggle(isOn: $aiSuggestionsEnabled) {
                Label("AI Suggestions", systemImage: "brain.head.profile")
                    .foregroundStyle(VeloceTheme.textPrimary)
            }
            .tint(VeloceTheme.accent)

            HStack {
                Label("Currency", systemImage: "dollarsign.circle")
                    .foregroundStyle(VeloceTheme.textPrimary)
                Spacer()
                Text("VND đ")
                    .font(.system(size: 14))
                    .foregroundStyle(VeloceTheme.textSecondary)
            }
        } header: {
            Text("Preferences")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(VeloceTheme.textPrimary)
                Spacer()
                Text(
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                )
                .foregroundStyle(VeloceTheme.textSecondary)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private func userInitial(_ user: User) -> String {
        if let name = user.displayName, let first = name.first { return String(first).uppercased() }
        if let email = user.email,     let first = email.first { return String(first).uppercased() }
        return "V"
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(ExpenseViewModel())
}
