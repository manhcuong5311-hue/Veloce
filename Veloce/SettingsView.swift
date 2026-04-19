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
    @State private var showBudgetResetDay      = false
    @State private var showReminderTimePicker  = false
    @State private var showRecurring           = false
    @State private var showPDFShareSheet      = false
    @State private var pdfReportURL:          URL?
    @AppStorage("veloce_icloud_sync")     private var iCloudSyncEnabled   = false
    @AppStorage("veloce_onboarding_done") private var onboardingDone      = true
    @State private var versionTapCount   = 0
    @State private var showOnboarding    = false
    @State private var showDevMenu       = false

    private var selectedCurrency: Binding<AppCurrency> {
        Binding(
            get: { AppCurrency(rawValue: currencyCode) ?? .vnd },
            set: { newCurrency in
                // Convert all stored amounts to the new currency before
                // writing the key, so values represent the same real-world
                // money rather than just swapping the symbol.
                CurrencyManager.shared.changeCurrency(to: newCurrency, vm: vm)
                // `changeCurrency` writes the UserDefaults key directly, but
                // @AppStorage needs a matching assignment to stay in sync.
                currencyCode = newCurrency.rawValue
            }
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
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized:"common.done")) { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
        }
        .adaptiveSheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subManager)
        }
        .adaptiveSheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL { ShareSheet(activityItems: [url]) }
        }
        .adaptiveSheet(isPresented: $showPDFShareSheet) {
            if let url = pdfReportURL { ShareSheet(activityItems: [url]) }
        }
        .adaptiveSheet(isPresented: $showImportPicker) {
            DocumentPicker(allowedTypes: [.json]) { url in handleImport(url: url) }
        }
        .adaptiveSheet(isPresented: $showEditSalary) {
            AmountEditSheet(
                title:   "settings_monthly_salary",
                icon:    "banknote",
                initial: vm.monthlyIncome,
                hint:    "settings_salary_hint"
            ) { vm.monthlyIncome = $0 }
        }
        .adaptiveSheet(isPresented: $showEditSaving) {
            AmountEditSheet(
                title:   "settings_saving_target",
                icon:    "target",
                initial: vm.savingGoal,
                hint:    "settings_saving_hint"
            ) { vm.savingGoal = $0 }
        }
        .adaptiveSheet(isPresented: $showBudgetResetDay) {
            BudgetResetDaySheet()
        }
        .adaptiveSheet(isPresented: $showRecurring) {
            RecurringTransactionsView()
                .environmentObject(vm)
                .environmentObject(subManager)
        }
        .adaptiveSheet(isPresented: $showReminderTimePicker) {
            ReminderTimePickerSheet(notifMgr: notifMgr)
        }
        .confirmationDialog(
            String(localized: "settings_signout_confirm"),
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings_sign_out"), role: .destructive) { authVM.signOut() }
        }
        .alert(String(localized: "settings_import_failed"), isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? String(localized: "settings_import_error_generic"))
        }
        .alert(String(localized: "settings_import_success"), isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("settings_import_success_msg")
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
                        Text("settings_monthly_salary")
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
                            Text("settings_not_set")
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
                        Text("settings_saving_target")
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
                            Text("settings_not_set")
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
                        Text(String(localized: isSaving ? "settings_projected_savings" : "settings_over_budget"))
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
            sectionHeader("settings_general", icon: "slider.horizontal.3")
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
                        Text(user.displayName ?? String(localized: "settings_veloce_user"))
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
                        Text(String(localized: "pro.badge"))
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
                Label("settings_sign_out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } header: {
            sectionHeader("settings_account", icon: "person.circle")
        }
    }

    // MARK: - PREMIUM ────────────────────────────────────────────────

    private var premiumSection: some View {
        Section {
            if subManager.isProUser {
                HStack {
                    Label {
                        Text("settings_premium_active")
                            .foregroundStyle(VeloceTheme.ok)
                            .font(.system(size: 15, weight: .medium))
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(VeloceTheme.ok)
                    }
                    Spacer()
                    Text("settings_pro_ai_limit")
                        .font(.system(size: 12))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            } else {
                Button { showPaywall = true } label: {
                    HStack {
                        Label {
                            Text("settings_upgrade_premium")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(VeloceTheme.accent)
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(VeloceTheme.accent)
                        }
                        Spacer()
                        Text("settings_free_ai_limit")
                            .font(.system(size: 12))
                            .foregroundStyle(VeloceTheme.textTertiary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textTertiary)
                    }
                }
            }

            Button { Task { await subManager.restorePurchases() } } label: {
                Label("settings_restore_purchases", systemImage: "arrow.clockwise")
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .font(.system(size: 14))
            }

            // Premium-locked features — always tappable, paywall shown for free users
            premiumLockedRow(
                icon: "calendar.badge.clock",
                iconColor: Color(hex: "5B8DB8"),
                title: "settings_budget_reset_day",
                subtitle: "settings_budget_reset_day_desc"
            ) {
                if subManager.isProUser { showBudgetResetDay = true }
                else { showPaywall = true }
            }
            premiumLockedRow(
                icon: "arrow.clockwise.circle.fill",
                iconColor: Color(hex: "7EC8A4"),
                title: "settings_recurring",
                subtitle: "settings_recurring_desc"
            ) {
                if subManager.isProUser { showRecurring = true }
                else { showPaywall = true }
            }

        } header: {
            sectionHeader("settings_premium", icon: "star.circle.fill")
        } footer: {
            if !subManager.isProUser {
                Text("settings_premium_footer")
                    .font(.system(size: 12))
                    .foregroundStyle(VeloceTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func premiumLockedRow(icon: String, iconColor: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
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
                        Text(String(localized: "pro.title"))
                            .font(.system(size: 11, weight: .bold))
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
                    Text("settings_ai_suggestions")
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
                    Text("settings_currency")
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
                    Text("settings_voice_language")
                        .foregroundStyle(VeloceTheme.textPrimary)
                } icon: {
                    Image(systemName: "mic.circle")
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
            .tint(VeloceTheme.accent)
        } header: {
            sectionHeader("settings_preferences", icon: "gearshape")
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
                            Text("settings_notif_disabled")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(VeloceTheme.textPrimary)
                            Text("settings_tap_system_settings")
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
                    Text("settings_daily_reminder")
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
                    Text("settings_budget_alerts")
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
                        Text("settings_reminder_time")
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
                        Text("settings_streak_hint")
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

            // Open System Settings link
            Button(action: { notifMgr.openSystemSettings() }) {
                Label {
                    Text("settings_open_system_settings")
                        .foregroundStyle(VeloceTheme.textPrimary)
                } icon: {
                    Image(systemName: "gear")
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }

        } header: {
            sectionHeader("settings_notifications", icon: "bell.badge")
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
            // iCloud Sync toggle
            HStack {
                Label {
                    Text("settings_icloud_sync")
                        .foregroundStyle(subManager.isProUser ? VeloceTheme.textPrimary : VeloceTheme.textTertiary)
                } icon: {
                    Image(systemName: "icloud")
                        .foregroundStyle(subManager.isProUser ? VeloceTheme.accent : VeloceTheme.textTertiary)
                }
                Spacer()
                if subManager.isProUser {
                    Toggle("", isOn: Binding(
                        get: { iCloudSyncEnabled },
                        set: { newValue in
                            iCloudSyncEnabled = newValue
                            PersistenceStore.shared.setICloudSync(enabled: newValue)
                        }
                    ))
                    .labelsHidden()
                    .disabled(!PersistenceStore.shared.isICloudAvailable)
                } else {
                    lockBadge
                }
            }
            .onTapGesture { if !subManager.isProUser { showPaywall = true } }

            // Month Report (PDF)
            Button(action: handlePDFExport) {
                HStack {
                    Label {
                        Text("settings_month_report")
                            .foregroundStyle(subManager.isProUser ? VeloceTheme.textPrimary : VeloceTheme.textTertiary)
                    } icon: {
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(subManager.isProUser ? VeloceTheme.accent : VeloceTheme.textTertiary)
                    }
                    Spacer()
                    if !subManager.isProUser { lockBadge }
                }
            }

            // Export / Import JSON
            Button(action: handleExport) {
                HStack {
                    Label {
                        Text("settings_export_data")
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
                        Text("settings_import_data")
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
            sectionHeader("settings_data", icon: "externaldrive")
        } footer: {
            Group {
                if subManager.isProUser && iCloudSyncEnabled && !PersistenceStore.shared.isICloudAvailable {
                    Text("settings_icloud_unavailable")
                } else {
                    Text(String(localized: subManager.isProUser ? "settings_data_pro_footer" : "settings_data_free_footer"))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(VeloceTheme.textTertiary)
        }
    }

    private var lockBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 9))
            Text("pro.title")
                .font(.system(size: 11, weight: .bold))
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
                        Text("settings_privacy_policy")
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
                        Text("settings_terms_eula")
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
            sectionHeader("settings_legal", icon: "checkmark.shield")
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
                        Text("settings_faq_title")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(VeloceTheme.textPrimary)
                        Text("settings_faq_subtitle")
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
            // Tap 5× to unlock the developer menu (hidden from normal users)
            Button {
                versionTapCount += 1
                if versionTapCount >= 5 {
                    versionTapCount = 0
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showDevMenu = true
                } else if versionTapCount >= 3 {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                HStack {
                    Text("settings_version")
                        .foregroundStyle(VeloceTheme.textSecondary)
                    Spacer()
                    if versionTapCount >= 3 {
                        Text("\(5 - versionTapCount) \(String(localized: "settings.taps_remaining"))")
                            .font(.system(size: 12))
                            .foregroundStyle(VeloceTheme.accent.opacity(0.7))
                            .transition(.opacity)
                    }
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
                .animation(.easeInOut(duration: 0.15), value: versionTapCount)
            }
            .buttonStyle(.plain)
        } footer: {
            if versionTapCount >= 3 {
                Text("settings_keep_tapping")
                    .font(.system(size: 11))
                    .foregroundStyle(VeloceTheme.accent.opacity(0.6))
                    .transition(.opacity)
            }
        }
        // Developer action sheet — 2 options
        .confirmationDialog(String(localized: "settings_dev_menu"), isPresented: $showDevMenu, titleVisibility: .visible) {
            Button(String(localized: "settings_open_onboarding")) {
                showOnboarding = true
            }
            Button(String(localized: "settings_test_notification")) {
                Task {
                    if notifMgr.authStatus != .authorized {
                        let granted = await notifMgr.requestPermission()
                        guard granted else { notifMgr.openSystemSettings(); return }
                    }
                    notifMgr.sendTestNotification()
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text("settings_dev_only")
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }

    // MARK: - Shared header style

    private func sectionHeader(_ title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(VeloceTheme.textSecondary)
            .textCase(nil)
    }

    // MARK: - Export / Import

    private func handlePDFExport() {
        guard subManager.isProUser else { showPaywall = true; return }
        guard let url = MonthReportGenerator.generate(vm: vm) else { return }
        pdfReportURL     = url
        showPDFShareSheet = true
    }

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
    let title:   LocalizedStringKey
    let icon:    String
    let initial: Double
    let hint:    LocalizedStringKey
    let onSave:  (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: Double? { Double(text.filter { $0.isNumber }) }
    private var isValid: Bool   { (parsed ?? 0) > 0 }

    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Hero
                        VStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.system(size: isIPad ? 40 : 28, weight: .medium))
                                .foregroundStyle(VeloceTheme.accent)
                                .frame(width: isIPad ? 88 : 64, height: isIPad ? 88 : 64)
                                .background(VeloceTheme.accentBg, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                            Text(title)
                                .font(.system(size: isIPad ? 22 : 17, weight: .semibold))
                                .foregroundStyle(VeloceTheme.textPrimary)

                            Text(hint)
                                .font(.system(size: isIPad ? 15 : 13))
                                .foregroundStyle(VeloceTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, isIPad ? 40 : 8)

                        // Amount input
                        VStack(spacing: 8) {
                            Text(String(localized: "expense.amount"))
                                .font(.system(size: isIPad ? 14 : 12, weight: .medium))
                                .foregroundStyle(VeloceTheme.textSecondary)
                                .tracking(0.3)

                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                if AppCurrency.current.symbolLeading {
                                    Text(AppCurrency.current.symbol)
                                        .font(.system(size: isIPad ? 36 : 24, weight: .semibold))
                                        .foregroundStyle(VeloceTheme.textTertiary)
                                        .offset(y: -3)
                                }
                                TextField("0", text: $text)
                                    .font(.system(size: isIPad ? 72 : 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(VeloceTheme.textPrimary)
                                    .tint(VeloceTheme.accent)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .focused($focused)
                                    .frame(maxWidth: isIPad ? 480 : 220)
                                    .onChange(of: text) { _, newVal in
                                        let digits = newVal.filter { $0.isNumber }
                                        let fmt    = Double.formatAmountInput(digits)
                                        if fmt != text { text = fmt }
                                    }
                                if !AppCurrency.current.symbolLeading {
                                    Text(AppCurrency.current.symbol)
                                        .font(.system(size: isIPad ? 36 : 24, weight: .semibold))
                                        .foregroundStyle(VeloceTheme.textTertiary)
                                        .offset(y: -3)
                                }
                            }

                            if let v = parsed, v > 0 {
                                Text(v.toCurrencyString())
                                    .font(.system(size: isIPad ? 16 : 13))
                                    .foregroundStyle(VeloceTheme.textTertiary)
                                    .transition(.opacity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isIPad ? 44 : 28)
                        .veloceCard(radius: 22)
                        .animation(.spring(response: 0.3), value: parsed != nil)

                        Button(action: save) {
                            Text(String(localized: "common.save"))
                                .font(.system(size: isIPad ? 19 : 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, isIPad ? 20 : 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isValid ? VeloceTheme.accent : VeloceTheme.divider)
                                )
                        }
                        .disabled(!isValid)
                        .animation(.easeInOut(duration: 0.2), value: isValid)

                        Spacer()
                    }
                    .padding(isIPad ? 40 : 20)
                    .frame(maxWidth: isIPad ? 560 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents(isIPad ? [.large] : [.medium])
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
struct FAQItem {
    let questionKey: String
    let answerKey: String
}

struct FAQView: View {
    @State private var expanded: Set<String> = []

    private let items: [FAQItem] = [
        FAQItem(questionKey: "faq.add_expense.q", answerKey: "faq.add_expense.a"),
        FAQItem(questionKey: "faq.edit_transaction.q", answerKey: "faq.edit_transaction.a"),
        FAQItem(questionKey: "faq.budget.q", answerKey: "faq.budget.a"),
        FAQItem(questionKey: "faq.salary.q", answerKey: "faq.salary.a"),
        FAQItem(questionKey: "faq.ai.q", answerKey: "faq.ai.a"),
        FAQItem(questionKey: "faq.category.q", answerKey: "faq.category.a"),
        FAQItem(questionKey: "faq.premium.q", answerKey: "faq.premium.a"),
        FAQItem(questionKey: "faq.currency.q", answerKey: "faq.currency.a"),
        FAQItem(questionKey: "faq.backup.q", answerKey: "faq.backup.a")
    ]

    var body: some View {
        ZStack {
            VeloceTheme.bg.ignoresSafeArea()
            List {
                Section {
                    ForEach(items, id: \.questionKey) { item in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expanded.contains(item.questionKey) },
                                set: { open in
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        if open {
                                            expanded.insert(item.questionKey)
                                        } else {
                                            expanded.remove(item.questionKey)
                                        }
                                    }
                                }
                            )
                        ) {
                            Text(LocalizedStringKey(item.answerKey))
                                .font(.system(size: 13))
                                .foregroundStyle(VeloceTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                        } label: {
                            Text(LocalizedStringKey(item.questionKey))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(VeloceTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: {
                    Text(String(localized: "faq.hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(VeloceTheme.textTertiary)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(String(localized: "faq.title"))
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
                        Text("settings_reminder_title")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textPrimary)
                        Text("settings_reminder_desc")
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
                        Text("settings_reminder_note")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(VeloceTheme.textTertiary)

                    // Save button
                    Button(action: save) {
                        Text(String(localized: "common.save"))
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
            .navigationTitle(String(localized: "reminder.time.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized:"common.cancel")) { dismiss() }
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
                                Text("settings_reset_prefix")
                                    .font(.system(size: 13))
                                    .foregroundStyle(VeloceTheme.textSecondary)
                                HStack(alignment: .lastTextBaseline, spacing: 4) {
                                    Text("\(selectedDay)\(ordinal(selectedDay))")
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                        .foregroundStyle(VeloceTheme.accent)
                                        .contentTransition(.numericText())
                                        .animation(.spring(response: 0.25), value: selectedDay)
                                    Text("settings_reset_suffix")
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
                            Text("settings_reset_select")
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

                            Text("settings_reset_note")
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
                            Text("settings_reset_save")
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
            .navigationTitle(String(localized: "budget.reset.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized:"common.cancel")) { dismiss() }
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
