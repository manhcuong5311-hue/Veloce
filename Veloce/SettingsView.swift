import SwiftUI
import FirebaseAuth
import UniformTypeIdentifiers

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var authVM:      AuthViewModel
    @EnvironmentObject private var subManager:  SubscriptionManager
    @EnvironmentObject private var vm:          ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("veloce_ai_suggestions")  private var aiSuggestionsEnabled = true
    @AppStorage("veloce_currency")        private var currencyCode          = "VND"
    @AppStorage("veloce_speech_language") private var speechLangCode        = "vi-VN"

    @State private var showPaywall         = false
    @State private var showSignOutConfirm  = false
    @State private var expandedFAQ: Set<String> = []

    // Export / Import
    @State private var showShareSheet      = false
    @State private var exportedFileURL:    URL?
    @State private var showImportPicker    = false
    @State private var importError:        String?
    @State private var showImportError     = false
    @State private var showImportSuccess   = false

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
                    dataSection          // Export / Import
                    preferencesSection
                    faqSection
                    aboutSection         // Privacy, ToS, version
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
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showImportPicker) {
            DocumentPicker(allowedTypes: [.json]) { url in
                handleImport(url: url)
            }
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
            Text(importError ?? "The file could not be read. Make sure it's a valid Veloce export.")
        }
        .alert("Import Successful", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data has been restored successfully.")
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Account

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
                        Text("PREMIUM")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(VeloceTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(VeloceTheme.accentBg, in: Capsule())
                    }
                }
                .padding(.vertical, 4)
            }
            Button(role: .destructive) { showSignOutConfirm = true } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } header: { Text("Account") }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        Section {
            if subManager.isProUser {
                HStack {
                    Label("Premium — Active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(VeloceTheme.ok)
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text("Unlimited AI")
                        .font(.system(size: 13))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            } else {
                Button(action: { showPaywall = true }) {
                    HStack {
                        Label("Upgrade to Premium", systemImage: "sparkles")
                            .foregroundStyle(VeloceTheme.accent)
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textTertiary)
                    }
                }
            }
            Button(action: { Task { await subManager.restorePurchases() } }) {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .font(.system(size: 14))
            }
        } header: { Text("Subscription") }
    }

    // MARK: - Data (Export / Import)

    private var dataSection: some View {
        Section {
            // Export
            Button(action: handleExport) {
                HStack {
                    Label("Export Data (JSON)", systemImage: "square.and.arrow.up")
                        .foregroundStyle(subManager.isProUser
                                         ? VeloceTheme.textPrimary
                                         : VeloceTheme.textTertiary)
                        .font(.system(size: 15))
                    Spacer()
                    if !subManager.isProUser {
                        premiumBadge
                    }
                }
            }

            // Import
            Button(action: handleImportTap) {
                HStack {
                    Label("Import Data (JSON)", systemImage: "square.and.arrow.down")
                        .foregroundStyle(subManager.isProUser
                                         ? VeloceTheme.textPrimary
                                         : VeloceTheme.textTertiary)
                        .font(.system(size: 15))
                    Spacer()
                    if !subManager.isProUser {
                        premiumBadge
                    }
                }
            }
        } header: {
            Label("Data", systemImage: "externaldrive")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VeloceTheme.textSecondary)
                .textCase(nil)
        } footer: {
            if subManager.isProUser {
                Text("Export a full JSON backup of your expenses, budgets, and categories.")
                    .font(.system(size: 12))
                    .foregroundStyle(VeloceTheme.textTertiary)
            } else {
                Text("Export and import are available with Premium.")
                    .font(.system(size: 12))
                    .foregroundStyle(VeloceTheme.textTertiary)
            }
        }
    }

    private var premiumBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 9))
            Text("Premium").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(VeloceTheme.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(VeloceTheme.accentBg, in: Capsule())
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
                ForEach(AppCurrency.allCases) { c in
                    Text(c.displayName).tag(c)
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
        } header: { Text("Preferences") }
    }

    // MARK: - FAQ

    private let faqs: [(q: String, a: String)] = [
        (
            "How do I add an expense?",
            "Tap the mic or text bar at the bottom and type (or say) something like \"coffee 45k\" or \"lunch 120k\". Veloce parses the amount and assigns a category automatically."
        ),
        (
            "How do I set or change a budget?",
            "On the Spending card, tap \"Edit Budget\" to drag the bars and redistribute your allocation in real time. For precise values, tap \"Groups\" → pencil icon to enter a custom amount."
        ),
        (
            "What does the AI Assistant do?",
            "The AI reads your spending and budget to give personalised advice. Ask it anything — \"Where am I overspending?\", \"How can I save 2M this month?\", or \"Analyse my portfolio\"."
        ),
        (
            "How do I customise a category?",
            "Tap \"Groups\" on the Spending card, then the pencil icon next to any category. Premium members can change its icon and color; all users can update the budget."
        ),
        (
            "How do I hide a category?",
            "In Edit Groups, tap the eye icon next to any category to hide it from the main chart. Hidden categories still record expenses and count toward your totals."
        ),
        (
            "What's included in Premium?",
            "Premium members get unlimited AI messages per day, icon & color customization for categories, and JSON export/import. Free users receive 3 AI messages per day."
        ),
        (
            "Is my data backed up?",
            "Data is stored on-device and synced to Firebase when you're signed in. Use Export Data (Premium) to keep an additional local backup."
        ),
        (
            "How do I change the currency?",
            "Go to Settings → Preferences → Currency and pick from VND, USD, EUR, JPY, and more. All amounts update immediately."
        ),
    ]

    private var faqSection: some View {
        Section {
            ForEach(faqs, id: \.q) { item in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedFAQ.contains(item.q) },
                        set: { open in
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                if open { expandedFAQ.insert(item.q) } else { expandedFAQ.remove(item.q) }
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
            Label("FAQ", systemImage: "questionmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VeloceTheme.textSecondary)
                .textCase(nil)
        }
    }

    // MARK: - About (Privacy, ToS, version)

    private var aboutSection: some View {
        Section {
            // Privacy Policy
            Link(destination: URL(string: "https://manhcuong5311-hue.github.io/Veloce/")!) {
                HStack {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                        .foregroundStyle(VeloceTheme.textPrimary)
                        .font(.system(size: 15))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }

            // Terms of Use
            Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                HStack {
                    Label("Terms of Use", systemImage: "doc.text.fill")
                        .foregroundStyle(VeloceTheme.textPrimary)
                        .font(.system(size: 15))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }

            // Version
            HStack {
                Text("Version")
                    .foregroundStyle(VeloceTheme.textPrimary)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(VeloceTheme.textSecondary)
            }
        } header: { Text("About") }
    }

    // MARK: - Export / Import handlers

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
            importError    = error.localizedDescription
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

    // MARK: - Helpers

    private func userInitial(_ user: User) -> String {
        if let name = user.displayName, let first = name.first { return String(first).uppercased() }
        if let email = user.email,     let first = email.first { return String(first).uppercased() }
        return "V"
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - DocumentPicker (UIDocumentPickerViewController wrapper)

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
            // Security-scoped access required for files outside the sandbox
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            onPick(url)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(ExpenseViewModel())
}
