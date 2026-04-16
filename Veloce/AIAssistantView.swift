import SwiftUI
internal import Speech   // needed for SFSpeechRecognizerAuthorizationStatus in micTapped()

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable {
    let id        = UUID()
    let role:      Role
    let content:   String
    let timestamp: Date      = Date()
    var actions:   [AIAction] = []

    enum Role { case user, assistant, error, debug }
}

// MARK: - AI Assistant Chat View

struct AIAssistantView: View {
    @EnvironmentObject var vm:         ExpenseViewModel
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    var autoSendPrompt: String? = nil
    /// When true the first auto-sent message (from an insight card) is free —
    /// it does not consume a slot from the free user's 3-message daily allowance.
    var isInsightPrompt: Bool = false

    @State private var messages:             [ChatMessage] = []
    @State private var inputText             = ""
    @State private var isThinking            = false
    @State private var insightFreeUsed       = false
    /// Populated on appear from InsightEngine — replaces the hardcoded chip list.
    @State private var suggestionPrompts:    [String]     = []
    @State private var showMicPermissionAlert = false
    /// Owns the microphone + speech-recognition pipeline for voice input.
    @StateObject private var speech = SpeechService()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !subManager.isProUser {
                        usageBanner
                    }
                    messageList
                    inputBar
                }
            }
            .navigationTitle(String(localized: "ai_assistant_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.large])
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .onAppear {
            // Restore previous session if one exists; otherwise show fresh welcome.
            // Avoids the jarring "blank slate" every time the sheet re-opens.
            let restored = loadPersistedConversation()
            if restored.isEmpty {
                sendWelcome()
            } else {
                messages = restored
            }
            // Build context-aware suggestion chips from live InsightEngine output.
            suggestionPrompts = buildDynamicSuggestions()
            if let prompt = autoSendPrompt, !prompt.isEmpty {
                inputText = prompt
                sendMessage()
            }
        }
        .onDisappear {
            // Save on every dismiss so the next open restores seamlessly.
            saveConversation()
        }
        .task {
            // Request mic + speech-recognition permissions up front so the
            // first tap on the mic button doesn't block on a permission dialog.
            await speech.requestPermissions()
        }
        .onChange(of: speech.recognizedText) { _, newText in
            // Mirror live transcription into the text field so the user can
            // review/edit before sending.
            if !newText.isEmpty { inputText = newText }
        }
        .alert(String(localized: "microphone_permission_title"), isPresented: $showMicPermissionAlert) {
            Button(String(localized: "open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "microphone_permission_message"))
        }
    }

    // MARK: - Usage Banner

    private var usageBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(VeloceTheme.accent)
            Text(String(format: String(localized: "ai_free_messages_left_fmt"), subManager.freeAIRemaining))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VeloceTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(VeloceTheme.accentBg)
    }

    /// True while there are no user messages yet — show pre-filled suggestion chips.
    private var showSuggestions: Bool {
        !messages.isEmpty && !messages.contains(where: { $0.role == .user })
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { msg in
                        MessageBubble(message: msg, onAction: handleAction)
                            .id(msg.id)
                    }
                    // Suggestion chips — shown before the first user message
                    if showSuggestions {
                        suggestionChips
                            .id("suggestions")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if isThinking {
                        ThinkingBubble()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .animation(.easeInOut(duration: 0.2), value: showSuggestions)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    if let lastId = messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isThinking) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("thinking", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Suggestion Chips

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "ai_suggested_questions"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VeloceTheme.textTertiary)
                .padding(.horizontal, 2)

            FlowLayout(spacing: 8) {
                ForEach(suggestionPrompts, id: \.self) { prompt in
                    Button(action: { sendSuggestion(prompt) }) {
                        Text(prompt)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(VeloceTheme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(VeloceTheme.accentBg, in: Capsule())
                            .overlay(Capsule().strokeBorder(VeloceTheme.accent.opacity(0.25), lineWidth: 1))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sendSuggestion(_ text: String) {
        inputText = text
        sendMessage()
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Live transcription banner — slides in while the mic is recording.
            if speech.isListening {
                aiListeningBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider().overlay(VeloceTheme.divider)
            HStack(spacing: 10) {
                TextField(String(localized: "ai_input_placeholder"), text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .tint(VeloceTheme.accent)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(VeloceTheme.surfaceRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(VeloceTheme.divider, lineWidth: 1)
                            )
                    )
                // Mic when idle, send arrow when text has been entered.
                // This mirrors InputBarView's pattern so the UX is consistent.
                if inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    aiMicButton
                        .transition(.scale.combined(with: .opacity))
                } else {
                    sendButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: speech.isListening)
        .animation(.spring(response: 0.22), value: inputText.isEmpty)
    }

    private var sendButton: some View {
        Button(action: sendMessage) {
            ZStack {
                Circle()
                    .fill(canSend ? VeloceTheme.accent : VeloceTheme.divider)
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? .white : VeloceTheme.textTertiary)
            }
        }
        .disabled(!canSend)
        .animation(.spring(response: 0.2), value: canSend)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isThinking
    }

    // MARK: - Voice input UI

    private var aiListeningBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(VeloceTheme.over)
                .frame(width: 7, height: 7)
            Text(speech.recognizedText.isEmpty ? String(localized: "listening") : speech.recognizedText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VeloceTheme.textPrimary)
                .lineLimit(1)
            Spacer()
            Button(String(localized: "common.done")) {
                speech.stopListening()
                // Commit whatever was transcribed so far
                if !speech.recognizedText.isEmpty { inputText = speech.recognizedText }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(VeloceTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(VeloceTheme.surface.opacity(0.95))
    }

    private var aiMicButton: some View {
        Button(action: micTapped) {
            ZStack {
                Circle()
                    .fill(speech.isListening ? VeloceTheme.over : VeloceTheme.surfaceRaised)
                    .overlay(Circle().strokeBorder(
                        speech.isListening ? Color.clear : VeloceTheme.divider,
                        lineWidth: 1
                    ))
                    .frame(width: 40, height: 40)
                Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(speech.isListening ? .white : VeloceTheme.textSecondary)
            }
        }
        .animation(.spring(response: 0.2), value: speech.isListening)
    }

    private func micTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard speech.authStatus == .authorized else {
            if speech.authStatus == .denied { showMicPermissionAlert = true }
            return
        }
        if speech.isListening {
            speech.stopListening()
            if !speech.recognizedText.isEmpty { inputText = speech.recognizedText }
        } else {
            inputText = ""
            speech.startListening()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(String(localized: "common.done")) { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VeloceTheme.accent)
        }
    }

    // MARK: - Actions

    private func sendWelcome() {
        messages.append(ChatMessage(role: .assistant, content: buildWelcomeMessage()))
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        // Determine if this send should be counted against the AI limit.
        // The FIRST message in an insight-card session (the auto-prompt) is free
        // so free users get a taste of AI insights before hitting the wall.
        let isFreeInsightSend = isInsightPrompt && !insightFreeUsed && !subManager.isProUser

        if !isFreeInsightSend && !subManager.canUseAI {
            if subManager.isProUser {
                // Silent soft-cap — never mention the number
                messages.append(ChatMessage(
                    role: .error,
                    content: String(localized: "ai_daily_limit_pro")
                ))
            } else {
                messages.append(ChatMessage(
                    role: .error,
                    content: String(format: String(localized: "ai_daily_limit_free_fmt"), SubscriptionManager.freeAILimit)
                ))
            }
            return
        }

        inputText = ""
        inputFocused = false
        messages.append(ChatMessage(role: .user, content: text))

        if isFreeInsightSend {
            insightFreeUsed = true   // only the first insight message is free
        } else {
            subManager.recordAIUsage()
        }

        isThinking = true
        Task {
            do {
                let response = try await OpenAIService.chat(
                    messages: buildAPIMessages(userText: text),
                    context:  buildContext()
                )
                var msg = ChatMessage(role: .assistant, content: response.content)
                msg.actions = response.actions
                messages.append(msg)
            } catch {
                // Show what went wrong so the user/developer can diagnose it,
                // then fall back to a rule-based local answer.
                let debugLine = cloudErrorNote(error)
                let local     = localResponse(for: text)
                messages.append(ChatMessage(role: .debug,     content: debugLine))
                messages.append(ChatMessage(role: .assistant, content: local))
            }
            isThinking = false
        }
    }

    // MARK: - Action handler

    /// Called when the user taps an action button inside an AI bubble.
    private func handleAction(_ action: AIAction) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch action.type {
        case "adjust_budget":
            guard
                let catName   = action.categoryName,
                let newBudget = action.suggestedAmount, newBudget > 0,
                let cat       = vm.categories.first(where: {
                    $0.name.lowercased() == catName.lowercased()
                })
            else { return }
            vm.updateBudget(categoryId: cat.id, newBudget: newBudget)
            messages.append(ChatMessage(
                role: .assistant,
                content: String(format: String(localized: "ai_budget_updated_fmt"), catName, newBudget.toCompactCurrency())
            ))
        case "open_category":
            // Dismiss the AI sheet so the user lands on the main screen.
            dismiss()
        default:
            break
        }
    }

    // MARK: - Context Builders

    private func buildWelcomeMessage() -> String {
        let totalSpent  = vm.totalSpent
        let totalBudget = vm.totalBudget
        let remaining   = totalBudget - totalSpent
        let pct         = totalBudget > 0 ? Int((totalSpent / totalBudget) * 100) : 0

        let statusLine: String
        if remaining < 0 {
            statusLine = String(format: String(localized: "ai_welcome_over_budget_fmt"), (-remaining).toCompactCurrency())
        } else if pct >= 85 {
            statusLine = String(format: String(localized: "ai_welcome_near_limit_fmt"), pct)
        } else {
            statusLine = String(format: String(localized: "ai_welcome_normal_fmt"), totalSpent.toCompactCurrency(), totalBudget.toCompactCurrency(), pct)
        }

        return statusLine + "\n\n" + String(localized: "ai_welcome_help_prompt")
    }

    private func buildContext() -> AppContext {
        // Build a fast id→name lookup so the expense loop is O(n) not O(n²).
        let catMap: [UUID: String] = Dictionary(
            uniqueKeysWithValues: vm.categories.map { ($0.id, $0.name) }
        )
        let fmt = ISO8601DateFormatter()
        // Send the 60 most recent transactions so the LLM can answer specific
        // questions ("what did I spend on food this week?", "my biggest expense
        // yesterday") instead of only seeing monthly totals.
        let recent: [RecentExpense] = vm.sortedExpenses.prefix(60).map { exp in
            RecentExpense(
                title:        exp.title,
                amount:       exp.amount,
                categoryName: catMap[exp.categoryId] ?? "Other",
                date:         fmt.string(from: exp.date)
            )
        }

        return AppContext(
            monthlyIncome:  vm.monthlyIncome,
            savingGoal:     vm.savingGoal,
            totalSpent:     vm.totalSpent,
            totalBudget:    vm.totalBudget,
            categories:     vm.categories.map {
                CategoryContext(
                    name:       $0.name,
                    spent:      $0.spent,
                    budget:     $0.budget,
                    spentRatio: $0.spentRatio
                )
            },
            recentExpenses: recent
        )
    }

    private func buildAPIMessages(userText: String) -> [OpenAIMessage] {
        // Only send user/assistant turns — exclude error and debug notes
        let conversationMessages = messages.filter { $0.role == .user || $0.role == .assistant }
        var apiMessages: [OpenAIMessage] = conversationMessages.suffix(10).map {
            OpenAIMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content)
        }
        apiMessages.append(OpenAIMessage(role: "user", content: userText))
        return apiMessages
    }

    // MARK: - Cloud error diagnostics

    /// Converts a Firebase Functions / network error into a human-readable debug note.
    private func cloudErrorNote(_ error: Error) -> String {
        let ns  = error as NSError
        let raw = error.localizedDescription

        // Firebase Functions errors carry a numeric code in the NSError.
        // Domain: com.firebase.functions  (FIRFunctionsErrorDomain)
        // Codes mirror gRPC status codes:
        //   1  = CANCELLED        7  = PERMISSION_DENIED   13 = INTERNAL
        //   2  = UNKNOWN          8  = RESOURCE_EXHAUSTED  14 = UNAVAILABLE
        //   3  = INVALID_ARGUMENT 9  = FAILED_PRECONDITION 16 = UNAUTHENTICATED
        //   5  = NOT_FOUND        11 = OUT_OF_RANGE
        let label: String
        if ns.domain == "com.firebase.functions" {
            switch ns.code {
            case 16: label = "UNAUTHENTICATED — Firebase token invalid or expired. Try signing out and back in."
            case 7:  label = "PERMISSION_DENIED — your account doesn't have access to this function."
            case 5:  label = "NOT_FOUND — the Cloud Function isn't deployed yet. Run: firebase deploy --only functions"
            case 14: label = "UNAVAILABLE — network error or function crashed. Check Firebase logs."
            case 13: label = "INTERNAL — OpenAI returned an error. Check your API key in Secret Manager."
            case 8:  label = "RESOURCE_EXHAUSTED — OpenAI rate limit hit. Try again in a moment."
            default: label = "Firebase error \(ns.code): \(raw)"
            }
        } else if raw.lowercased().contains("network") || raw.lowercased().contains("internet") {
            label = "No internet connection — answered locally."
        } else {
            label = "\(ns.domain) \(ns.code): \(raw)"
        }

        return "☁️ Cloud AI offline · \(label)"
    }

    // MARK: - Local fallback (used when Cloud Function is unavailable)

    private func localResponse(for text: String) -> String {
        let t       = text.lowercased()
        let spent   = vm.totalSpent
        let budget  = vm.totalBudget
        let remain  = budget - spent
        let cats    = vm.categories.filter { $0.spent > 0 }.sorted { $0.spent > $1.spent }

        // Over-budget question
        if t.contains("over") || t.contains("exceed") || t.contains("vượt") {
            let overCats = vm.categories.filter { $0.isOverBudget }
            if overCats.isEmpty {
                return String(localized: "ai_fallback_on_track")
            }
            let list = overCats.map {
                String(format: String(localized: "ai_fallback_over_by_fmt"), $0.name, ($0.spent - $0.budget).toCompactCurrency())
            }.joined(separator: ", ")
            return String(format: String(localized: "ai_fallback_over_budget_fmt"), list)
        }

        // Top spending / most expensive
        if t.contains("top") || t.contains("most") || t.contains("highest") || t.contains("biggest") {
            if let top = cats.first {
                return String(format: String(localized: "ai_fallback_top_category_fmt"),
                              top.name, top.spent.toCompactCurrency(), top.budget.toCompactCurrency())
            }
        }

        // Savings question
        if t.contains("save") || t.contains("saving") || t.contains("tiết kiệm") {
            let goal = vm.savingGoal
            let income = vm.monthlyIncome
            let projected = income - spent
            if projected >= goal {
                return String(format: String(localized: "ai_fallback_saving_on_track_fmt"),
                              projected.toCompactCurrency(), goal.toCompactCurrency())
            } else {
                return String(format: String(localized: "ai_fallback_saving_behind_fmt"),
                              max(0, projected).toCompactCurrency(), goal.toCompactCurrency(), (goal - projected).toCompactCurrency())
            }
        }

        // Category breakdown
        if t.contains("categor") || t.contains("breakdown") || t.contains("detail") {
            guard !cats.isEmpty else { return String(localized: "ai_fallback_no_spending") }
            let lines = cats.prefix(5).map {
                String(format: String(localized: "ai_fallback_category_line_fmt"),
                       $0.name, $0.spent.toCompactCurrency(), $0.budget.toCompactCurrency())
            }
            return String(localized: "ai_fallback_breakdown_header") + "\n" + lines.joined(separator: "\n")
        }

        // General budget status
        if t.contains("budget") || t.contains("spend") || t.contains("how much") || t.contains("bao nhiêu") {
            let pct = budget > 0 ? Int((spent / budget) * 100) : 0
            if remain < 0 {
                return String(format: String(localized: "ai_fallback_budget_over_fmt"),
                              (-remain).toCompactCurrency(), pct)
            }
            return String(format: String(localized: "ai_fallback_budget_fmt"),
                          spent.toCompactCurrency(), budget.toCompactCurrency(), pct, remain.toCompactCurrency())
        }

        // Default helpful response
        let pct = budget > 0 ? Int((spent / budget) * 100) : 0
        return String(format: String(localized: "ai_fallback_default_fmt"), spent.toCompactCurrency(), pct)
    }

    // MARK: - Dynamic suggestion chips

    /// Pulls AI prompts from the highest-priority InsightCards, then fills any
    /// remaining slots with static fallbacks. Result is always 3–5 chips.
    /// Called once on appear so InsightEngine doesn't run on every render.
    private func buildDynamicSuggestions() -> [String] {
        let insightPrompts = InsightEngine.generate(
            expenses:      vm.expenses,
            categories:    vm.categories,
            monthlyIncome: vm.monthlyIncome,
            savingGoal:    vm.savingGoal
        )
        .compactMap(\.aiPrompt)   // only cards that have a pre-filled AI prompt
        .prefix(3)

        // Static fallbacks ensure chips are always present even with zero data.
        let fallbacks = [
            String(localized: "ai_suggestion_budget_tips"),
            String(localized: "ai_suggestion_top_category"),
            String(localized: "ai_suggestion_saving_goal"),
            String(localized: "ai_suggestion_save_more"),
            String(localized: "ai_suggestion_breakdown"),
        ]

        var result = Array(insightPrompts)
        for fb in fallbacks where result.count < 5 {
            if !result.contains(fb) { result.append(fb) }
        }
        return result
    }

    // MARK: - Conversation persistence

    private static let conversationKey   = "veloce_ai_chat_history"
    private static let maxPersistedTurns = 20

    /// Lightweight Codable mirror of ChatMessage used only for UserDefaults storage.
    /// Excludes .error and .debug roles — those are transient UI state, not history.
    private struct PersistedChatMessage: Codable {
        let role:    String   // "user" | "assistant"
        let content: String
    }

    /// Saves the last `maxPersistedTurns` user/assistant messages to UserDefaults.
    private func saveConversation() {
        let saveable = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(Self.maxPersistedTurns)
            .map { PersistedChatMessage(role: $0.role == .user ? "user" : "assistant",
                                        content: $0.content) }
        guard let data = try? JSONEncoder().encode(saveable) else { return }
        UserDefaults.standard.set(data, forKey: Self.conversationKey)
    }

    /// Loads the previous conversation. Returns [] on any failure so the caller
    /// shows a fresh welcome message instead of crashing or showing stale data.
    private func loadPersistedConversation() -> [ChatMessage] {
        guard
            let data     = UserDefaults.standard.data(forKey: Self.conversationKey),
            let restored = try? JSONDecoder().decode([PersistedChatMessage].self, from: data)
        else { return [] }
        return restored.map {
            ChatMessage(role: $0.role == "user" ? .user : .assistant, content: $0.content)
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message:  ChatMessage
    var onAction: ((AIAction) -> Void)? = nil

    var body: some View {
        // Debug notes render as a slim inline banner (not a full bubble)
        if message.role == .debug {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VeloceTheme.caution)
                Text(message.content)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(VeloceTheme.caution.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 8) {
                    if message.role == .user { Spacer(minLength: 48) }

                    if message.role != .user {
                        ZStack {
                            Circle()
                                .fill(VeloceTheme.accentBg)
                                .frame(width: 30, height: 30)
                            Image(systemName: message.role == .error ? "exclamationmark.triangle.fill" : "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(message.role == .error ? VeloceTheme.over : VeloceTheme.accent)
                        }
                        .alignmentGuide(.bottom) { d in d[.bottom] }
                    }

                    // Text bubble — must constrain width so long content wraps
                    // instead of growing off screen. `.fixedSize(vertical: true)`
                    // lets the bubble grow as tall as needed while respecting the
                    // horizontal space left by the Spacer on the opposite side.
                    Text(LocalizedStringKey(message.content))
                        .font(.system(size: 14))
                        .foregroundStyle(bubbleForeground)
                        .multilineTextAlignment(message.role == .user ? .trailing : .leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(bubbleBackground, in: bubbleShape)
                        // Cap width so a single very long word / URL can't push
                        // the bubble edge off screen on narrow devices.
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.72,
                               alignment: message.role == .user ? .trailing : .leading)

                    if message.role != .user { Spacer(minLength: 48) }
                }

                // Action buttons — shown below assistant bubbles when AI suggests an action
                if message.role == .assistant, !message.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.actions, id: \.self) { action in
                            Button {
                                onAction?(action)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: actionIcon(action))
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(actionLabel(action))
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(VeloceTheme.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 38) // align under bubble (past avatar)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity,
                   alignment: message.role == .user ? .trailing : .leading)
        }
    }

    private func actionLabel(_ action: AIAction) -> String {
        switch action.type {
        case "adjust_budget":
            let cat    = action.categoryName ?? ""
            let amount = action.suggestedAmount.map { " → \($0.toCompactCurrency())" } ?? ""
            return String(format: String(localized: "ai_action_adjust_budget_fmt"), cat, amount)
        case "open_category":
            return String(format: String(localized: "ai_action_view_category_fmt"), action.categoryName ?? "")
        default:
            return action.reason ?? String(localized: "ai_action_take_action")
        }
    }

    private func actionIcon(_ action: AIAction) -> String {
        switch action.type {
        case "adjust_budget":  return "slider.horizontal.3"
        case "open_category":  return "arrow.right.circle"
        default:               return "bolt.fill"
        }
    }

    private var bubbleForeground: Color {
        switch message.role {
        case .user:      return .white
        case .assistant: return VeloceTheme.textPrimary
        case .error:     return VeloceTheme.over
        default:         return VeloceTheme.textPrimary
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:      return VeloceTheme.accent
        case .assistant: return VeloceTheme.surface
        case .error:     return VeloceTheme.over.opacity(0.08)
        default:         return VeloceTheme.surface
        }
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }
}

// MARK: - Thinking Indicator

private struct ThinkingBubble: View {
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(VeloceTheme.accentBg)
                    .frame(width: 30, height: 30)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VeloceTheme.accent)
            }
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(VeloceTheme.textTertiary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == i ? 1.3 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15),
                            value: phase
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(VeloceTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 48)
        }
        .onAppear { phase = 1 }
    }
}

// MARK: - Preview

#Preview {
    AIAssistantView()
        .environmentObject(ExpenseViewModel())
        .environmentObject(SubscriptionManager.shared)
}
