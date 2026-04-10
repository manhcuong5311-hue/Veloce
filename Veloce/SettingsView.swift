import SwiftUI
import FirebaseAuth
import Combine
// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var authVM:     AuthViewModel
    @EnvironmentObject private var subManager: SubscriptionManager
    @EnvironmentObject private var vm:         ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("veloce_ai_suggestions")   private var aiSuggestionsEnabled = true
    @AppStorage("veloce_currency")         private var currencyCode         = "VND"
    @AppStorage("veloce_speech_language")  private var speechLangCode       = "vi-VN"
    @State private var showPaywall        = false
    @State private var showSignOutConfirm = false

    private var selectedCurrency: Binding<AppCurrency> {
        Binding(
            get: { AppCurrency(rawValue: currencyCode) ?? .vnd },
            set: { currencyCode = $0.rawValue }
        )
    }

    private var selectedSpeechLang: Binding<SpeechLanguage> {
        Binding(
            get: { SpeechLanguage.all.first { $0.code == speechLangCode } ?? SpeechLanguage.all[0] },
            set: { speechLangCode = $0.code }
        )
    }

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

            Picker(selection: selectedCurrency) {
                ForEach(AppCurrency.allCases) { currency in
                    Text(currency.displayName).tag(currency)
                }
            } label: {
                Label("Currency", systemImage: "dollarsign.circle")
                    .foregroundStyle(VeloceTheme.textPrimary)
            }
            .tint(VeloceTheme.accent)

            Picker(selection: selectedSpeechLang) {
                ForEach(SpeechLanguage.all) { lang in
                    Text("\(lang.flag)  \(lang.name)").tag(lang)
                }
            } label: {
                Label("Voice Language", systemImage: "mic.circle")
                    .foregroundStyle(VeloceTheme.textPrimary)
            }
            .tint(VeloceTheme.accent)
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
