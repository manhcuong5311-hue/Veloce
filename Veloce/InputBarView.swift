import SwiftUI
internal import Speech

struct InputBarView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @StateObject private var speech = SpeechService()

    @State private var text = ""
    @FocusState private var textFocused: Bool
    @State private var showPermissionAlert = false
    @State private var parseFailed         = false
    @State private var isParsing           = false
    @State private var pendingParsed: ParsedExpense? = nil

    var onAITap:       () -> Void = {}
    var onManualAdd:   () -> Void = {}
    var onRecurringAdd: () -> Void = {}

    @State private var showAddMenu = false

    var body: some View {
        VStack(spacing: 0) {
            if speech.isListening {
                listeningBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            inputRow
        }
        .background(.ultraThinMaterial)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: speech.isListening)
        .animation(.spring(response: 0.22), value: text.isEmpty)
        .animation(.spring(response: 0.22), value: textFocused)
        
        .alert(
            String(localized: "microphone_permission_title"),
            isPresented: $showPermissionAlert
        ) {
            Button(String(localized: "open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "microphone_permission_message"))
        }

        
        .task { await speech.requestPermissions() }
        .onChange(of: speech.recognizedText) { _, newVal in
            if !newVal.isEmpty { text = newVal }
        }
        
        .confirmationDialog(
            String(localized: "add_transaction_title"),
            isPresented: $showAddMenu,
            titleVisibility: .visible
        ) {
            Button(String(localized: "add_expense")) { onManualAdd() }
            Button(String(localized: "recurring_transaction")) { onRecurringAdd() }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "add_transaction_message"))
        }
        
        .sheet(item: $pendingParsed) { parsed in
            CategoryPickerSheet(parsed: parsed) {
                text        = ""
                textFocused = false
            }
            .environmentObject(vm)
        }
    }

    // MARK: - Listening banner

    private var listeningBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(VeloceTheme.over)
                .frame(width: 7, height: 7)

            Text(
                speech.recognizedText.isEmpty
                ? String(localized: "listening")
                : speech.recognizedText
            )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VeloceTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            Button(String(localized:"common.done")) { finishListening() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VeloceTheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(VeloceTheme.surface.opacity(0.9))
    }

    // MARK: - Main input row

    private var inputRow: some View {
        HStack(spacing: 8) {

            // ── Text field ───────────────────────────────────────
            HStack(spacing: 8) {
                TextField(String(localized: "quick_input_placeholder"), text: $text)

                    .font(.system(size: 15))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .tint(VeloceTheme.accent)
                    .focused($textFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit { submit() }

                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(VeloceTheme.textTertiary)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(VeloceTheme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                parseFailed ? VeloceTheme.over.opacity(0.7) : VeloceTheme.divider,
                                lineWidth: parseFailed ? 1.5 : 1
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: parseFailed)

            // ── Right-side action buttons ────────────────────────
            if !text.isEmpty {
                sendButton.transition(.scale.combined(with: .opacity))
            } else {
                micButton.transition(.scale.combined(with: .opacity))
                addButton.transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var sendButton: some View {
        Button(action: submit) {
            ZStack {
                Circle()
                    .fill(isParsing ? VeloceTheme.accent.opacity(0.6) : VeloceTheme.accent)
                    .frame(width: 44, height: 44)
                if isParsing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(isParsing)
    }

    private var micButton: some View {
        Button(action: micTapped) {
            ZStack {
                Circle()
                    .fill(speech.isListening ? VeloceTheme.over : VeloceTheme.accent)
                    .frame(width: 44, height: 44)
                Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var addButton: some View {
        Button(action: { showAddMenu = true }) {
            ZStack {
                Circle()
                    .fill(VeloceTheme.surfaceRaised)
                    .overlay(Circle().strokeBorder(VeloceTheme.divider, lineWidth: 1))
                    .frame(width: 44, height: 44)
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VeloceTheme.accent)
            }
        }
    }

    // MARK: - Actions

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isParsing else { return }
        speech.stopListening()

        isParsing = true
        Task { await doParseAndApply(trimmed) }
    }

    @MainActor
    private func doParseAndApply(_ trimmed: String) async {
        defer { isParsing = false }

        // Cloud-first: attempt the LLM parser; fall through to local on any error.
        let catNames = vm.categories.map { $0.name }
        if let parsed = try? await OpenAIService.parseExpense(
            text:          trimmed,
            categoryNames: catNames,
            categories:    vm.categories
        ) {
            applyParsed(parsed)
            return
        }

        // Local fallback — rule-based NLP already in the app.
        switch vm.parseExpenseResult(from: trimmed) {
        case .added:
            text        = ""
            textFocused = false
        case .needsCategory(let parsed):
            pendingParsed = parsed
        case .failed:
            withAnimation { parseFailed = true }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation { parseFailed = false }
            }
        }
    }

    /// Applies a `ParsedExpense` that already has a resolved (or nil) category name.
    private func applyParsed(_ parsed: ParsedExpense) {
        // Map the category name returned by the cloud to an actual UUID.
        let catId: UUID? = parsed.categoryName.flatMap { name in
            vm.categories.first(where: {
                $0.name.lowercased() == name.lowercased()
            })?.id
        }

        if let id = catId {
            vm.addExpense(Expense(
                title:      parsed.title,
                amount:     parsed.amount,
                categoryId: id,
                date:       parsed.date
            ))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            text        = ""
            textFocused = false
        } else {
            // Category unclear — let user pick.
            pendingParsed = parsed
        }
    }

    private func finishListening() {
        speech.stopListening()
        if !speech.recognizedText.isEmpty {
            text = speech.recognizedText
            submit()
        }
    }

    private func micTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard speech.authStatus == .authorized else {
            if speech.authStatus == .denied { showPermissionAlert = true }
            return
        }
        if speech.isListening { finishListening() }
        else { text = ""; speech.startListening() }
    }
}

// MARK: - Category Picker Sheet

struct CategoryPickerSheet: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    let parsed: ParsedExpense
    var onComplete: () -> Void = {}

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // ── Parsed expense preview ───────────────
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(VeloceTheme.accentBg)
                                    .frame(width: 46, height: 46)
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(VeloceTheme.accent)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(parsed.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(VeloceTheme.textPrimary)
                                    .lineLimit(1)
                                Text(String(localized: "choose_group_question"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(VeloceTheme.textSecondary)
                            }
                            Spacer()
                            Text(parsed.amount.toCompactCurrency())
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(VeloceTheme.textPrimary)
                        }
                        .veloceCard()

                        // ── Category grid ────────────────────────
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                            spacing: 12
                        ) {
                            ForEach(vm.categories.filter { !$0.isHidden }) { cat in
                                Button(action: { pick(cat) }) {
                                    VStack(spacing: 10) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color(hex: cat.colorHex).opacity(0.14))
                                                .frame(width: 54, height: 54)
                                            Image(systemName: cat.icon)
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundStyle(Color(hex: cat.colorHex))
                                        }
                                        Text(cat.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(VeloceTheme.textPrimary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(VeloceTheme.surface)
                                            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(String(localized: "choose_group_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized:"common.cancel")) { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
    }

    private func pick(_ category: Category) {
        vm.addExpense(Expense(
            title:      parsed.title,
            amount:     parsed.amount,
            categoryId: category.id,
            date:       parsed.date
        ))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete()
        dismiss()
    }
}
