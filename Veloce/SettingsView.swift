import SwiftUI
import FirebaseAuth
import UniformTypeIdentifiers

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var authVM:      AuthViewModel
    @EnvironmentObject private var subManager:  SubscriptionManager
    @EnvironmentObject private var vm:          ExpenseViewModel
    @EnvironmentObject private var notifMgr:    NotificationManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("veloce_ai_suggestions")  private var aiSuggestionsEnabled = true
    @AppStorage("veloce_currency")        private var currencyCode          = "VND"
    @AppStorage("veloce_speech_language") private var speechLangCode        = "vi-VN"

    @State private var showPaywall          = false
    @State private var showSignOutConfirm   = false
    @State private var showShareSheet       = false
    @State private var exportedFileURL:     URL?
    @State private var showImportPicker     = false
    @State private var importError:         String?
    @State private var showImportError      = false
    @State private var showImportSuccess    = false
    @State private var showEditSalary         = false
    @State private var showEditSaving         = false
    @State private var showAccentColorPicker  = false
    @State private var showBudgetResetDay     = false
    @State private var showReminderTimePicker = false

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

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                List {
                    generalSection
                    accountSection
                    premiumSection
                    preferencesSection
                    notificationsSection
                    dataSection
                    legalSection
                    faqRow
                    versionSection
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
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL { ShareSheet(activityItems: [url]) }
        }
        .sheet(isPresented: $showImportPicker) {
            DocumentPicker(allowedTypes: [.json]) { url in handleImport(url: url) }
        }
        .sheet(isPresented: $showEditSalary) {
            AmountEditSheet(
                title:   "Monthly Salary",
                icon:    "banknote",
                initial: vm.monthlyIncome,
                hint:    "Your total income each month"
            ) { vm.monthlyIncome = $0 }
        }
        .sheet(isPresented: $showEditSaving) {
            AmountEditSheet(
                title:   "Saving Target",
                icon:    "target",
                initial: vm.savingGoal,
                hint:    "How much you aim to save monthly"
            ) { vm.savingGoal = $0 }
        }
        .sheet(isPresented: $showAccentColorPicker) {
            AccentColorPickerSheet()
        }
        .sheet(isPresented: $showBudgetResetDay) {
            BudgetResetDaySheet()
        }
        .sheet(isPresented: $showReminderTimePicker) {
            ReminderTimePickerSheet(notifMgr: notifMgr)
        }
        .confirmationDialog(
            "Sign out of Veloce?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) { authVM.signOut() }
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "The file could not be read.")
        }
        .alert("Import Successful", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data has been restored successfully.")
        }
        .preferredColorScheme(.light)
    }

    // MARK: - GENERAL ────────────────────────────────────────────────

    private var generalSection: some View {
        Section {
            // Monthly Salary row
            Button { showEditSalary = true } label: {
                HStack {
                    Label {
                        Text("Monthly Salary")
                            .foregroundStyle(VeloceTheme.textPrimary)
                    } icon: {
                        Image(systemName: "banknote")
                            .foregroundStyle(VeloceTheme.accent)
                    }
                    Spacer()
                    Group {
                        if vm.monthlyIncome > 0 {
                            Text(vm.monthlyIncome.toCompactCurrency())
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(VeloceTheme.accent)
                        } else {
                            Text("Not set")
                                .font(.system(size: 14))
                                .foregroundStyle(VeloceTheme.textTertiary)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }

            // Saving Target row
            Button { showEditSaving = true } label: {
                HStack {
                    Label {
                        Text("Saving Target")
                            .foregroundStyle(VeloceTheme.textPrimary)
                    } icon: {
                        Image(systemName: "target")
                            .foregroundStyle(VeloceTheme.ok)
                    }
                    Spacer()
                    Group {
                        if vm.savingGoal > 0 {
                            Text(vm.savingGoal.toCompactCurrency())
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(VeloceTheme.ok)
                        } else {
                            Text("Not set")
                                .font(.system(size: 14))
                                .foregroundStyle(VeloceTheme.textTertiary)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }

            // Savings summary chip (when both are set)
            if vm.monthlyIncome > 0 {
                let savings    = vm.monthlyIncome - vm.totalBudget
                let isSaving   = savings >= 0
                let savingsPct = vm.monthlyIncome > 0 ? abs(savings) / vm.monthlyIncome * 100 : 0
                HStack(spacing: 10) {
                    Image(systemName: isSaving ? "leaf.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(isSaving ? VeloceTheme.ok : VeloceTheme.over)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isSaving ? "Projected savings" : "Over budget by")
                            .font(.system(size: 12))
                            .foregroundStyle(VeloceTheme.textSecondary)
                        Text("\(isSaving ? "" : "-")\(abs(savings).toCompactCurrency())  (\(String(format: "%.0f", savingsPct))%)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSaving ? VeloceTheme.ok : VeloceTheme.over)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3), value: savings)
                    }
                    Spacer()
                    // Mini savings bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(VeloceTheme.divider).frame(height: 5)
                            Capsule()
                                .fill(isSaving ? VeloceTheme.ok : VeloceTheme.over)
                                .frame(
                                    width: geo.size.width * CGFloat(
                                        min(vm.totalBudget / vm.monthlyIncome, 1)
                                    ),
                                    height: 5
                                )
                                .animation(.spring(response: 0.4), value: vm.totalBudget)
                        }
                    }
                    .frame(width: 70, height: 5)
                }
                .padding(.vertical, 4)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSaving ? VeloceTheme.ok.opacity(0.07) : VeloceTheme.over.opacity(0.07))
                        .padding(.horizontal, -4)
                )
            }
        } header: {
            sectionHeader("General", icon: "slider.horizontal.3")
        } footer: {
            Text("settings_general_footer")
                .font(.system(size: 12))
                .foregroundStyle(VeloceTheme.textTertiary)
        }
    }

    // MARK: - ACCOUNT ────────────────────────────────────────────────

    private var accountSection: some View {
        Section {
            if let user = authVM.currentUser {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(VeloceTheme.accentBg).frame(width: 46, height: 46)
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
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(VeloceTheme.accent, in: Capsule())
                    }
                }
                .padding(.vertical, 4)
            }
            Button(role: .destructive) { showSignOutConfirm = true } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } header: {
            sectionHeader("Account", icon: "person.circle")
        }
    }

    // MARK: - PREMIUM ────────────────────────────────────────────────

    private var premiumSection: some View {
        Section {
            if subManager.isProUser {
                HStack {
                    Label {
                        Text("Premium — Active")
                            .foregroundStyle(VeloceTheme.ok)
                            .font(.system(size: 15, weight: .medium))
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(VeloceTheme.ok)
                    }
                    Spacer()
                    Text("50 AI / day")
                        .font(.system(size: 12))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            } else {
                Button { showPaywall = true } label: {
                    HStack {
                        Label {
                            Text("Upgrade to Premium")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(VeloceTheme.accent)
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(VeloceTheme.accent)
                        }
                        Spacer()
                        Text("3 AI / day  ·  Free")
                            .font(.system(size: 12))
                            .foregroundStyle(VeloceTheme.textTertiary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textTertiary)
                    }
                }
            }

            Button { Task { await subManager.restorePurchases() } } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .font(.system(size: 14))
            }

            // Premium-locked features — always tappable, paywall shown for free users
            premiumLockedRow(
                icon: "paintpalette.fill",
                iconColor: Color(hex: "C97BA8"),
                title: "Custom Accent Color",
                subtitle: "Personalize your app theme"
            ) {
                if subManager.isProUser { showAccentColorPicker = true }
                else { showPaywall = true }
            }
            premiumLockedRow(
                icon: "calendar.badge.clock",
                iconColor: Color(hex: "5B8DB8"),
                title: "Budget Reset Day",
                subtitle: "Choose your monthly cycle start"
            ) {
                if subManager.isProUser { showBudgetResetDay = true }
                else { showPaywall = true }
            }

        } header: {
            sectionHeader("Premium", icon: "star.circle.fill")
        } footer: {
            if !subManager.isProUser {
                Text("settings_premium_footer")
                    .font(.system(size: 12))
                    .foregroundStyle(VeloceTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func premiumLockedRow(icon: String, iconColor: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(subManager.isProUser ? iconColor : VeloceTheme.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(subManager.isProUser ? VeloceTheme.textPrimary : VeloceTheme.textSecondary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
                Spacer()
                if subManager.isProUser {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textTertiary)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill").font(.system(size: 9))
                        Text("Pro").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(VeloceTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(VeloceTheme.accentBg, in: Capsule())
                }
            }
        }
    }

    // MARK: - PREFERENCES ────────────────────────────────────────────

    private var preferencesSection: some View {
        Section {
            Toggle(isOn: $aiSuggestionsEnabled) {
                Label {
                    Text("AI Suggestions")
                        .foregroundStyle(VeloceTheme.textPrimary)
                } icon: {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
            .tint(VeloceTheme.accent)

            Picker(selection: selectedCurrency) {
                ForEach(AppCurrency.allCases) { c in
                    Text(c.displayName).tag(c)
                }
            } label: {
                Label {
                    Text("Currency")
                        .foregroundStyle(VeloceTheme.textPrimary)
                } icon: {
                    Image(systemName: "dollarsign.circle")
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
            .tint(VeloceTheme.accent)

            Picker(selection: selectedSpeechLang) {
                ForEach(SpeechLanguage.all) { lang in
                    Text("\(lang.flag)  \(lang.name)").tag(lang)
                }
            } label: {
                Label {
                    Text("Voice Language")
                        .foregroundStyle(VeloceTheme.textPrimary)
                } icon: {
                    Image(systemName: "mic.circle")
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
            .tint(VeloceTheme.accent)
        } header: {
            sectionHeader("Preferences", icon: "gearshape")
        }
    }

    // MARK: - NOTIFICATIONS ───────────────────────────────────────────

    private var notificationsSection: some View {
        Section {
            // Permission status banner
            if notifMgr.authStatus == .denied {
                Button(action: { notifMgr.openSystemSettings() }) {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(VeloceTheme.over)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications disabled")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(VeloceTheme.textPrimary)
                            Text("Tap to open System Settings")
                                .font(.system(size: 12))
                                .foregroundStyle(VeloceTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                            .foregroundStyle(VeloceTheme.textTertiary)
                    }
                }
                .listRowBackground(VeloceTheme.over.opacity(0.06))
            }

            // Daily Reminder toggle
            HStack {
                Label {
                    Text("Daily Reminder")
                        .foregroundStyle(VeloceTheme.textPrimary)
                } icon: {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(VeloceTheme.accent)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { notifMgr.dailyEnabled },
                    set: { notifMgr.dailyEnabled = $0 }
                ))
                .tint(VeloceTheme.accent)
                .labelsHidden()
            }

            // Budget Alerts toggle
            HStack {
                Label {
                    Text("Budget Alerts")
                        .foregroundStyle(VeloceTheme.textPrimary)
                } icon: {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(VeloceTheme.caution)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { notifMgr.budgetEnabled },
                    set: { notifMgr.budgetEnabled = $0 }
                ))
                .tint(VeloceTheme.accent)
                .labelsHidden()
            }

            // Reminder Time
            Button { showReminderTimePicker = true } label: {
                HStack {
                    Label {
                        Text("Reminder Time")
                            .foregroundStyle(VeloceTheme.textPrimary)
                    } icon: {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(VeloceTheme.accent)
                    }
                    Spacer()
                    Text(String(format: "%02d:%02d", notifMgr.reminderHour, notifMgr.reminderMinute))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(VeloceTheme.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }

            // Streak indicator (if active)
            if notifMgr.dailyStreak >= 2 {
                HStack(spacing: 10) {
                    Text("🔥")
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: String(localized: "streak_label_fmt"), notifMgr.dailyStreak))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textPrimary)
                        Text("Keep logging expenses daily to maintain it")
                            .font(.system(size: 12))
                            .foregroundStyle(VeloceTheme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "FF6B35").opacity(0.07))
                        .padding(.horizontal, -4)
                )
            }

            // Test notification (only when authorized)
            if notifMgr.authStatus == .authorized {
                Button(action: { notifMgr.sendTestNotification() }) {
                    HStack {
                        Label {
                            Text("Send Test Notification")
                                .foregroundStyle(VeloceTheme.textPrimary)
                        } icon: {
                            Image(systemName: "bell.badge")
                                .foregroundStyle(VeloceTheme.accent)
                        }
                        Spacer()
                        Text("~2 sec")
                            .font(.system(size: 12))
                            .foregroundStyle(VeloceTheme.textTertiary)
                    }
                }
            }

            // Open System Settings link
            Button(action: { notifMgr.openSystemSettings() }) {
                Label {
                    Text("Open System Settings")
                        .foregroundStyle(VeloceTheme.textPrimary)
                } icon: {
                    Image(systemName: "gear")
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }

        } header: {
            sectionHeader("Notifications", icon: "bell.badge")
        } footer: {
            switch notifMgr.authStatus {
            case .authorized:
                Text("settings_notif_authorized_footer")
                    .font(.system(size: 12)).foregroundStyle(VeloceTheme.textTertiary)
            case .denied:
                Text("settings_notif_denied_footer")
                    .font(.system(size: 12)).foregroundStyle(VeloceTheme.textTertiary)
            default:
                Text("settings_notif_default_footer")
                    .font(.system(size: 12)).foregroundStyle(VeloceTheme.textTertiary)
            }
        }
        .task { await notifMgr.refreshStatus() }
    }

    // MARK: - DATA ────────────────────────────────────────────────────

    private var dataSection: some View {
        Section {
            Button(action: handleExport) {
                HStack {
                    Label {
                        Text("Export Data (JSON)")
                            .foregroundStyle(subManager.isProUser ? VeloceTheme.textPrimary : VeloceTheme.textTertiary)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(subManager.isProUser ? VeloceTheme.accent : VeloceTheme.textTertiary)
                    }
                    Spacer()
                    if !subManager.isProUser { lockBadge }
                }
            }
            Button(action: handleImportTap) {
                HStack {
                    Label {
                        Text("Import Data (JSON)")
                            .foregroundStyle(subManager.isProUser ? VeloceTheme.textPrimary : VeloceTheme.textTertiary)
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(subManager.isProUser ? VeloceTheme.accent : VeloceTheme.textTertiary)
                    }
                    Spacer()
                    if !subManager.isProUser { lockBadge }
                }
            }
        } header: {
            sectionHeader("Data", icon: "externaldrive")
        } footer: {
            Text(subManager.isProUser ? "settings_data_pro_footer" : "settings_data_free_footer")
                .font(.system(size: 12))
                .foregroundStyle(VeloceTheme.textTertiary)
        }
    }

    private var lockBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 9))
            Text("Pro").font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(VeloceTheme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(VeloceTheme.accentBg, in: Capsule())
    }

    // MARK: - LEGAL ───────────────────────────────────────────────────

    private var legalSection: some View {
        Section {
            Link(destination: URL(string: "https://manhcuong5311-hue.github.io/Veloce/")!) {
                HStack {
                    Label {
                        Text("Privacy Policy")
                            .foregroundStyle(VeloceTheme.textPrimary)
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(VeloceTheme.accent)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }
            Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                HStack {
                    Label {
                        Text("Terms of Use (EULA)")
                            .foregroundStyle(VeloceTheme.textPrimary)
                    } icon: {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(VeloceTheme.accent)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }
        } header: {
            sectionHeader("Legal", icon: "checkmark.shield")
        }
    }

    // MARK: - FAQ (single NavigationLink row → FAQView) ───────────────

    private var faqRow: some View {
        Section {
            NavigationLink {
                FAQView()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(VeloceTheme.accent.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(VeloceTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FAQ & Help")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(VeloceTheme.textPrimary)
                        Text("Common questions answered")
                            .font(.system(size: 12))
                            .foregroundStyle(VeloceTheme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - VERSION ─────────────────────────────────────────────────

    private var versionSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(VeloceTheme.textSecondary)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(VeloceTheme.textTertiary)
            }
        }
    }

    // MARK: - Shared header style

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(VeloceTheme.textSecondary)
            .textCase(nil)
    }

    // MARK: - Export / Import

    private func handleExport() {
        guard subManager.isProUser else { showPaywall = true; return }
        do {
            let data = try vm.exportJSON()
            let url  = FileManager.default.temporaryDirectory
                .appendingPathComponent("veloce_export_\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url)
            exportedFileURL = url
            showShareSheet  = true
        } catch {
            importError     = error.localizedDescription
            showImportError = true
        }
    }

    private func handleImportTap() {
        guard subManager.isProUser else { showPaywall = true; return }
        showImportPicker = true
    }

    private func handleImport(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            try vm.importJSON(data)
            showImportSuccess = true
        } catch {
            importError     = error.localizedDescription
            showImportError = true
        }
    }

    private func userInitial(_ user: User) -> String {
        if let name = user.displayName, let first = name.first { return String(first).uppercased() }
        if let email = user.email,     let first = email.first { return String(first).uppercased() }
        return "V"
    }
}

// MARK: - Amount Edit Sheet (salary / saving target)

private struct AmountEditSheet: View {
    let title:   String
    let icon:    String
    let initial: Double
    let hint:    String
    let onSave:  (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: Double? { Double(text.filter { $0.isNumber }) }
    private var isValid: Bool   { (parsed ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()
                VStack(spacing: 20) {
                    // Hero
                    VStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(VeloceTheme.accent)
                            .frame(width: 64, height: 64)
                            .background(VeloceTheme.accentBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textPrimary)

                        Text(hint)
                            .font(.system(size: 13))
                            .foregroundStyle(VeloceTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Amount input
                    VStack(spacing: 6) {
                        Text("Amount")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VeloceTheme.textSecondary)
                            .tracking(0.3)

                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            if AppCurrency.current.symbolLeading {
                                Text(AppCurrency.current.symbol)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(VeloceTheme.textTertiary)
                                    .offset(y: -3)
                            }
                            TextField("0", text: $text)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(VeloceTheme.textPrimary)
                                .tint(VeloceTheme.accent)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .focused($focused)
                                .frame(maxWidth: 220)
                                .onChange(of: text) { _, newVal in
                                    let digits = newVal.filter { $0.isNumber }
                                    let fmt    = Double.formatAmountInput(digits)
                                    if fmt != text { text = fmt }
                                }
                            if !AppCurrency.current.symbolLeading {
                                Text(AppCurrency.current.symbol)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(VeloceTheme.textTertiary)
                                    .offset(y: -3)
                            }
                        }

                        if let v = parsed, v > 0 {
                            Text(v.toCurrencyString())
                                .font(.system(size: 13))
                                .foregroundStyle(VeloceTheme.textTertiary)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .veloceCard(radius: 22)
                    .animation(.spring(response: 0.3), value: parsed != nil)

                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isValid ? VeloceTheme.accent : VeloceTheme.divider)
                            )
                    }
                    .disabled(!isValid)
                    .animation(.easeInOut(duration: 0.2), value: isValid)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .onAppear {
            if initial > 0 {
                text = Double.formatAmountInput("\(Int(initial))")
            }
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                focused = true
            }
        }
    }

    private func save() {
        guard isValid, let v = parsed else { return }
        onSave(v)
        dismiss()
    }
}

// MARK: - FAQ View

struct FAQView: View {
    @State private var expanded: Set<String> = []

    private let items: [(q: String, a: String)] = [
        (
            "How do I add an expense?",
            "Tap the mic or text bar at the bottom and type (or say) something like \"coffee 45k\" or \"lunch 120k\". Veloce parses the amount and assigns a category automatically."
        ),
        (
            "How do I edit or delete a transaction?",
            "Tap any row in the list to open the edit screen. Long-press (hold) a row to reveal a quick-action menu with Edit and Delete options."
        ),
        (
            "How do I set or change a budget?",
            "On the Spending card, tap \"Edit Budget\" to drag the bars and redistribute your allocation in real time. For precise values, tap \"Groups\" → pencil icon."
        ),
        (
            "How do I change my salary or saving target?",
            "Go to Settings → General. Tap Monthly Salary or Saving Target to edit the value in a full-screen input."
        ),
        (
            "What does the AI Assistant do?",
            "The AI reads your spending and budget to give personalised advice. Ask it anything — \"Where am I overspending?\", \"How can I save 2M this month?\", or \"Analyse my portfolio\"."
        ),
        (
            "How do I customise a category?",
            "Tap \"Groups\" on the Spending card, then the pencil icon next to any category. Premium members can change its icon and color."
        ),
        (
            "What's included in Premium?",
            "Premium gives you 50 AI messages/day, custom icon & color, custom accent color, budget reset day, and JSON export/import. Free plan includes 3 AI messages/day."
        ),
        (
            "How do I change the currency?",
            "Go to Settings → Preferences → Currency and pick your currency. All amounts update immediately."
        ),
        (
            "Is my data backed up?",
            "Data is stored locally and synced to Firebase when signed in. Use Export Data (Premium) for an additional backup."
        ),
    ]

    var body: some View {
        ZStack {
            VeloceTheme.bg.ignoresSafeArea()
            List {
                Section {
                    ForEach(items, id: \.q) { item in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expanded.contains(item.q) },
                                set: { open in
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        if open { expanded.insert(item.q) } else { expanded.remove(item.q) }
                                    }
                                }
                            )
                        ) {
                            Text(item.a)
                                .font(.system(size: 13))
                                .foregroundStyle(VeloceTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                        } label: {
                            Text(item.q)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(VeloceTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(VeloceTheme.accent)
                        .listRowBackground(VeloceTheme.surface)
                    }
                } header: {
                    Text("Tap a question to expand the answer.")
                        .font(.system(size: 12))
                        .foregroundStyle(VeloceTheme.textTertiary)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("FAQ & Help")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.light)
    }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - DocumentPicker

private struct DocumentPicker: UIViewControllerRepresentable {
    let allowedTypes: [UTType]
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            onPick(url)
        }
    }
}

// MARK: - Preview

// MARK: - Reminder Time Picker Sheet

struct ReminderTimePickerSheet: View {
    @ObservedObject var notifMgr: NotificationManager
    @Environment(\.dismiss) private var dismiss

    // Build a Date from current hour/minute for the DatePicker
    @State private var pickerDate: Date = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()
                VStack(spacing: 28) {
                    // Icon + description
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(VeloceTheme.accentBg)
                                .frame(width: 68, height: 68)
                            Image(systemName: "clock.fill")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(VeloceTheme.accent)
                        }
                        Text("Daily Reminder Time")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textPrimary)
                        Text("Choose when Veloce should remind you\nto log today's expenses.")
                            .font(.system(size: 13))
                            .foregroundStyle(VeloceTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    // Time picker
                    DatePicker("", selection: $pickerDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .tint(VeloceTheme.accent)
                        .frame(maxWidth: .infinity)
                        .veloceCard()

                    // Info note
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("A ±15 minute variation is applied to feel more natural.")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(VeloceTheme.textTertiary)

                    // Save button
                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(VeloceTheme.accent)
                            )
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Reminder Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .onAppear {
            var comps        = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour       = notifMgr.reminderHour
            comps.minute     = notifMgr.reminderMinute
            pickerDate       = Calendar.current.date(from: comps) ?? Date()
        }
    }

    private func save() {
        let comps              = Calendar.current.dateComponents([.hour, .minute], from: pickerDate)
        notifMgr.reminderHour  = comps.hour   ?? 20
        notifMgr.reminderMinute = comps.minute ?? 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }
}

// MARK: - Accent Color Picker Sheet

struct AccentColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("veloce_accent_hex") private var savedHex: String = "7B6CF0"
    @State private var selected: String = "7B6CF0"

    private let palette: [(hex: String, name: String)] = [
        ("7B6CF0", "Indigo"),     ("5B8DB8", "Blue"),
        ("5BA88C", "Teal"),       ("6BBF8E", "Sage"),
        ("D4A853", "Amber"),      ("E07A5F", "Coral"),
        ("E86B8B", "Rose"),       ("C97BA8", "Mauve"),
        ("9B84D0", "Lavender"),   ("4B9FA8", "Cyan"),
        ("8A95A8", "Slate"),      ("1C1B1A", "Graphite"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Preview card
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(hex: selected).opacity(0.12))
                                    .frame(height: 90)
                                HStack(spacing: 12) {
                                    Circle().fill(Color(hex: selected)).frame(width: 36, height: 36)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Capsule().fill(Color(hex: selected)).frame(width: 100, height: 10)
                                        Capsule().fill(Color(hex: selected).opacity(0.3)).frame(width: 70, height: 8)
                                    }
                                    Spacer()
                                    Capsule()
                                        .fill(Color(hex: selected))
                                        .frame(width: 60, height: 32)
                                        .overlay(
                                            Text("Save")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white)
                                        )
                                }
                                .padding(.horizontal, 20)
                            }
                            Text("Preview")
                                .font(.system(size: 12))
                                .foregroundStyle(VeloceTheme.textTertiary)
                        }
                        .padding(.horizontal, 20)
                        .animation(.spring(response: 0.3), value: selected)

                        // Color grid
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Choose a color")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(VeloceTheme.textSecondary)

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                                spacing: 12
                            ) {
                                ForEach(palette, id: \.hex) { item in
                                    let isSelected = selected.uppercased() == item.hex.uppercased()
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.spring(response: 0.25)) { selected = item.hex }
                                    } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(hex: item.hex))
                                                    .frame(width: 52, height: 52)
                                                    .overlay(
                                                        Circle()
                                                            .strokeBorder(.white, lineWidth: isSelected ? 3 : 0)
                                                    )
                                                    .shadow(color: Color(hex: item.hex).opacity(0.4),
                                                            radius: isSelected ? 8 : 0, y: 3)
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                            Text(item.name)
                                                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                                .foregroundStyle(isSelected ? Color(hex: item.hex) : VeloceTheme.textTertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .animation(.spring(response: 0.2), value: isSelected)
                                }
                            }
                        }
                        .veloceCard()
                        .padding(.horizontal, 20)

                        // Save button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            savedHex = selected
                            dismiss()
                        } label: {
                            Text("Apply Color")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(hex: selected))
                                )
                        }
                        .padding(.horizontal, 20)
                        .animation(.spring(response: 0.25), value: selected)

                        Text("Color applies on next app launch.")
                            .font(.system(size: 12))
                            .foregroundStyle(VeloceTheme.textTertiary)
                            .padding(.bottom, 8)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Accent Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .onAppear { selected = savedHex }
    }
}

// MARK: - Budget Reset Day Sheet

struct BudgetResetDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("veloce_budget_reset_day") private var resetDay: Int = 1
    @State private var selectedDay: Int = 1

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Info card
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(VeloceTheme.accent.opacity(0.12))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 22))
                                    .foregroundStyle(VeloceTheme.accent)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Budget resets on the")
                                    .font(.system(size: 13))
                                    .foregroundStyle(VeloceTheme.textSecondary)
                                HStack(alignment: .lastTextBaseline, spacing: 4) {
                                    Text("\(selectedDay)\(ordinal(selectedDay))")
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                        .foregroundStyle(VeloceTheme.accent)
                                        .contentTransition(.numericText())
                                        .animation(.spring(response: 0.25), value: selectedDay)
                                    Text("of each month")
                                        .font(.system(size: 13))
                                        .foregroundStyle(VeloceTheme.textSecondary)
                                }
                            }
                            Spacer()
                        }
                        .veloceCard()
                        .padding(.horizontal, 20)

                        // Day grid 1–28
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Select reset day")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(VeloceTheme.textSecondary)

                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(1...28, id: \.self) { day in
                                    let isSelected = selectedDay == day
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.spring(response: 0.22)) { selectedDay = day }
                                    } label: {
                                        Text("\(day)")
                                            .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                                            .foregroundStyle(isSelected ? .white : VeloceTheme.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fit)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(isSelected ? VeloceTheme.accent : VeloceTheme.surfaceRaised)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .animation(.spring(response: 0.2), value: isSelected)
                                }
                            }

                            Text("Days 29–31 are skipped for shorter months.")
                                .font(.system(size: 11))
                                .foregroundStyle(VeloceTheme.textTertiary)
                        }
                        .veloceCard()
                        .padding(.horizontal, 20)

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            resetDay = selectedDay
                            dismiss()
                        } label: {
                            Text("Save Reset Day")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(VeloceTheme.accent)
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Budget Reset Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .onAppear { selectedDay = resetDay }
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1, 21: return "st"
        case 2, 22: return "nd"
        case 3, 23: return "rd"
        default:    return "th"
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(ExpenseViewModel())
        .environmentObject(NotificationManager.shared)
}
