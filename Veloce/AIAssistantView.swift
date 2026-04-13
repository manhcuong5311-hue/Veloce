import SwiftUI

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable {
    let id        = UUID()
    let role:      Role
    let content:   String
    let timestamp: Date = Date()

    enum Role { case user, assistant, error, debug }
}

// MARK: - AI Assistant Chat View

struct AIAssistantView: View {
    @EnvironmentObject var vm:         ExpenseViewModel
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var messages:  [ChatMessage] = []
    @State private var inputText  = ""
    @State private var isThinking = false
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
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.large])
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .onAppear { sendWelcome() }
    }

    // MARK: - Usage Banner

    private var usageBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(VeloceTheme.accent)
            Text("\(subManager.freeAIRemaining) free message\(subManager.freeAIRemaining == 1 ? "" : "s") left today")
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

    private let suggestions = [
        "How can I save more this month?",
        "Why did I overspend?",
        "Give me budget tips",
        "Which category costs me the most?",
        "Am I on track with my saving goal?",
    ]

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { msg in
                        MessageBubble(message: msg)
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
            Text("Suggested questions")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VeloceTheme.textTertiary)
                .padding(.horizontal, 2)

            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { prompt in
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
            Divider().overlay(VeloceTheme.divider)
            HStack(spacing: 10) {
                TextField("Ask about your finances…", text: $inputText, axis: .vertical)
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
                sendButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
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

        if !subManager.canUseAI {
            if subManager.isProUser {
                // Silent soft-cap — never mention the number
                messages.append(ChatMessage(
                    role: .error,
                    content: "You've reached today's optimal usage limit. Try again tomorrow."
                ))
            } else {
                messages.append(ChatMessage(
                    role: .error,
                    content: "You've used all \(SubscriptionManager.freeAILimit) free messages today. Upgrade to Premium for unlimited AI insights."
                ))
            }
            return
        }

        inputText = ""
        inputFocused = false
        messages.append(ChatMessage(role: .user, content: text))
        subManager.recordAIUsage()

        isThinking = true
        Task {
            do {
                let response = try await OpenAIService.chat(
                    messages: buildAPIMessages(userText: text),
                    context:  buildContext()
                )
                messages.append(ChatMessage(role: .assistant, content: response))
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

    // MARK: - Context Builders

    private func buildWelcomeMessage() -> String {
        let totalSpent  = vm.totalSpent
        let totalBudget = vm.totalBudget
        let remaining   = totalBudget - totalSpent
        let pct         = totalBudget > 0 ? Int((totalSpent / totalBudget) * 100) : 0

        let statusLine: String
        if remaining < 0 {
            statusLine = "You're **\((-remaining).toCompactCurrency()) over budget** this month."
        } else if pct >= 85 {
            statusLine = "You've used **\(pct)%** of your monthly budget — almost at the limit."
        } else {
            statusLine = "You've spent **\(totalSpent.toCompactCurrency())** of your **\(totalBudget.toCompactCurrency())** budget (\(pct)% used)."
        }

        return "\(statusLine)\n\nHow can I help you today? I can analyze your spending, suggest savings, or help you plan toward your financial goals."
    }

    private func buildContext() -> AppContext {
        AppContext(
            monthlyIncome: vm.monthlyIncome,
            savingGoal:    vm.savingGoal,
            totalSpent:    vm.totalSpent,
            totalBudget:   vm.totalBudget,
            categories:    vm.categories.map {
                CategoryContext(
                    name:       $0.name,
                    spent:      $0.spent,
                    budget:     $0.budget,
                    spentRatio: $0.spentRatio
                )
            }
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
                return "You're within budget on every category. Keep it up!"
            }
            let list = overCats.map { "**\($0.name)** (over by \(($0.spent - $0.budget).toCompactCurrency()))" }.joined(separator: ", ")
            return "You're over budget on: \(list)."
        }

        // Top spending / most expensive
        if t.contains("top") || t.contains("most") || t.contains("highest") || t.contains("biggest") {
            if let top = cats.first {
                return "Your highest spend this month is **\(top.name)** at **\(top.spent.toCompactCurrency())** (budget: \(top.budget.toCompactCurrency()))."
            }
        }

        // Savings question
        if t.contains("save") || t.contains("saving") || t.contains("tiết kiệm") {
            let goal = vm.savingGoal
            let income = vm.monthlyIncome
            let projected = income - spent
            if projected >= goal {
                return "You're on track to save **\(projected.toCompactCurrency())** this month — your goal is \(goal.toCompactCurrency()). Great!"
            } else {
                return "At current spending you'd save **\(max(0, projected).toCompactCurrency())**. To hit your goal of \(goal.toCompactCurrency()) you'd need to cut **\((goal - projected).toCompactCurrency())** more."
            }
        }

        // Category breakdown
        if t.contains("categor") || t.contains("breakdown") || t.contains("detail") {
            guard !cats.isEmpty else { return "No spending recorded yet. Add your first expense!" }
            let lines = cats.prefix(5).map { "• **\($0.name)**: \($0.spent.toCompactCurrency()) / \($0.budget.toCompactCurrency())" }
            return "Here's your spending breakdown:\n" + lines.joined(separator: "\n")
        }

        // General budget status
        if t.contains("budget") || t.contains("spend") || t.contains("how much") || t.contains("bao nhiêu") {
            let pct = budget > 0 ? Int((spent / budget) * 100) : 0
            if remain < 0 {
                return "You're **\((-remain).toCompactCurrency()) over budget** this month (\(pct)% used)."
            }
            return "You've spent **\(spent.toCompactCurrency())** of your **\(budget.toCompactCurrency())** budget — \(pct)% used, **\(remain.toCompactCurrency())** remaining."
        }

        // Default helpful response
        let pct = budget > 0 ? Int((spent / budget) * 100) : 0
        return "You've spent **\(spent.toCompactCurrency())** this month (\(pct)% of budget). Ask me about your categories, savings, or budget tips!"
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

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

                Text(LocalizedStringKey(message.content))
                    .font(.system(size: 14))
                    .foregroundStyle(bubbleForeground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground, in: bubbleShape)
                    .fixedSize(horizontal: false, vertical: true)

                if message.role != .user { Spacer(minLength: 48) }
            }
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
