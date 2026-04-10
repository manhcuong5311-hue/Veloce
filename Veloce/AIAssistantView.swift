import SwiftUI

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable {
    let id        = UUID()
    let role:      Role
    let content:   String
    let timestamp: Date = Date()

    enum Role { case user, assistant, error }
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

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                    if isThinking {
                        ThinkingBubble()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
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

        if !subManager.isProUser && !subManager.canUseAI {
            messages.append(ChatMessage(
                role: .error,
                content: "You've used all \(SubscriptionManager.freeAILimit) free messages today. Upgrade to Pro for unlimited access."
            ))
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
                messages.append(ChatMessage(role: .error, content: error.localizedDescription))
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
        let conversationMessages = messages.filter { $0.role == .user || $0.role == .assistant }
        var apiMessages: [OpenAIMessage] = conversationMessages.suffix(10).map {
            OpenAIMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content)
        }
        apiMessages.append(OpenAIMessage(role: "user", content: userText))
        return apiMessages
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
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

    private var bubbleForeground: Color {
        switch message.role {
        case .user:      return .white
        case .assistant: return VeloceTheme.textPrimary
        case .error:     return VeloceTheme.over
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:      return VeloceTheme.accent
        case .assistant: return VeloceTheme.surface
        case .error:     return VeloceTheme.over.opacity(0.08)
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
