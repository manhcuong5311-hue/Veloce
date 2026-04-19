import SwiftUI
internal import Speech
import FinanceKit

// MARK: - OnboardingView (3 pages)

struct OnboardingView: View {
    @EnvironmentObject private var vm: ExpenseViewModel

    @State private var page          = 0
    @State private var income        = ""
    @State private var savingsGoal   = ""
    @State private var tryInput      = ""
    @State private var parsedResult: String? = nil

    @AppStorage("veloce_onboarding_done") private var onboardingDone = false

    // 5 pages: 0 Welcome | 1 Setup | 2 Notifications | 3 Apple Pay | 4 Try It
    private let totalPages = 5

    var body: some View {
        ZStack {
            VeloceTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page dots
                pageIndicator
                    .padding(.top, 20)

                // Pages — using TabView for native swipe feel
                TabView(selection: $page) {
                    Page1(onNext: advance).tag(0)
                    Page2(income: $income, savingsGoal: $savingsGoal,
                          onContinue: { applySetup(); advance() },
                          onSkip: advance).tag(1)
                    PageNotification(onEnable: {
                        Task {
                            await NotificationManager.shared.requestPermission()
                            advance()
                        }
                    }, onSkip: advance).tag(2)
                    PageApplePay(onNext: advance).tag(3)
                    Page3(input: $tryInput, parsedResult: $parsedResult,
                          onFinish: finish).tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: page)
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Dots

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(Array(0..<totalPages), id: \.self) { i in
                Capsule()
                    .fill(i == page ? VeloceTheme.accent : VeloceTheme.divider)
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: page)
            }
        }
    }

    // MARK: - Actions

    private func advance() {
        withAnimation(.easeInOut(duration: 0.35)) { page += 1 }
    }

    private func applySetup() {
        let cleaned = { (s: String) in s.replacingOccurrences(of: ",", with: "") }
        if let val = Double(cleaned(income)),       val > 0 { vm.monthlyIncome = val }
        if let val = Double(cleaned(savingsGoal)),  val > 0 { vm.savingGoal    = val }
    }

    private func finish() {
        onboardingDone = true
    }
}

// MARK: - Page 1: Value Prop

private struct Page1: View {
    let onNext: () -> Void

    @State private var show = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 36) {
                // Hero icon
                ZStack {
                    Circle()
                        .fill(VeloceTheme.accentBg)
                        .frame(width: 148, height: 148)

                    Circle()
                        .fill(VeloceTheme.accent.opacity(0.12))
                        .frame(width: 200)
                        .blur(radius: 30)

                    Image(systemName: "bolt.fill")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(VeloceTheme.accent)
                }
                .scaleEffect(show ? 1 : 0.6)
                .opacity(show ? 1 : 0)

                VStack(spacing: 16) {
                    Text(String(localized: "onboarding_tagline"))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(VeloceTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .offset(y: show ? 0 : 18)
                        .opacity(show ? 1 : 0)

                    Text(String(localized: "onboarding_voice_hint"))
                        .font(.system(size: 17))
                        .foregroundStyle(VeloceTheme.textSecondary)
                        .offset(y: show ? 0 : 14)
                        .opacity(show ? 1 : 0)

                    // Demo pill
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(VeloceTheme.accent)
                        Text(String(localized: "onboarding_voice_example"))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(VeloceTheme.textPrimary)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(VeloceTheme.surface)
                            .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
                    )
                    .offset(y: show ? 0 : 12)
                    .opacity(show ? 1 : 0)
                }
            }

            Spacer()
            Spacer()

            primaryButton(String(localized: "get_started"), action: onNext)
                .padding(.horizontal, 28)
                .padding(.bottom, 56)
                .offset(y: show ? 0 : 28)
                .opacity(show ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.78).delay(0.08)) { show = true }
        }
    }
}

// MARK: - Page 2: Setup

private struct Page2: View {
    @Binding var income:      String
    @Binding var savingsGoal: String
    let onContinue: () -> Void
    let onSkip:     () -> Void

    @State private var show = false
    @FocusState private var focusedField: Field?

    private enum Field { case income, savings }

    private var currency: AppCurrency { AppCurrency.current }

    private var incomePlaceholder: String {
        switch currency {
        case .vnd: return "vd: 15.000.000"
        case .jpy: return "例: 300,000"
        case .krw: return "예: 3,000,000"
        case .thb: return "เช่น: 30,000"
        case .eur: return "e.g. 2,500"
        case .gbp: return "e.g. 2,000"
        case .sgd: return "e.g. 4,000"
        default:   return "e.g. 3,000"
        }
    }

    private var savingsPlaceholder: String {
        switch currency {
        case .vnd: return "vd: 3.000.000"
        case .jpy: return "例: 60,000"
        case .krw: return "예: 600,000"
        case .thb: return "เช่น: 6,000"
        case .eur: return "e.g. 500"
        case .gbp: return "e.g. 400"
        case .sgd: return "e.g. 800"
        default:   return "e.g. 600"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Text(String(localized: "onboarding_setup_title"))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(VeloceTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(String(localized: "onboarding_optional_note"))
                        .font(.system(size: 15))
                        .foregroundStyle(VeloceTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(show ? 1 : 0)
                .offset(y: show ? 0 : 16)

                VStack(spacing: 14) {
                    setupField(
                        label: String(localized: "monthly_income"),
                        placeholder: incomePlaceholder,
                        icon: "banknote",
                        text: $income,
                        field: .income
                    )

                    setupField(
                        label: String(localized: "monthly_savings_goal"),
                        placeholder: savingsPlaceholder,
                        icon: "target",
                        text: $savingsGoal,
                        field: .savings
                    )
                }
                .opacity(show ? 1 : 0)
                .offset(y: show ? 0 : 22)
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()

            VStack(spacing: 13) {
                primaryButton(
                    String(localized: "continue"),
                    action: onContinue
                )


                Button(action: onSkip) {
                    Text(String(localized: "skip_for_now"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 56)
            .opacity(show ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.78).delay(0.08)) { show = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                focusedField = .income
            }
        }
    }

    @ViewBuilder
    private func setupField(
        label:       String,
        placeholder: String,
        icon:        String,
        text:        Binding<String>,
        field:       Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VeloceTheme.accent)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer()
                Text(currency.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VeloceTheme.accent)
            }

            TextField(placeholder, text: text)
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(VeloceTheme.textPrimary)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: field)
                .padding(15)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(VeloceTheme.surface)
                        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
                )
        }
    }
}

// MARK: - Page Notification: Permission

private struct PageNotification: View {
    let onEnable: () -> Void
    let onSkip:   () -> Void

    @State private var show = false
    @State private var bellBounce = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 36) {
                // Hero
                ZStack {
                    Circle()
                        .fill(VeloceTheme.accentBg)
                        .frame(width: 148, height: 148)
                    Circle()
                        .fill(VeloceTheme.accent.opacity(0.10))
                        .frame(width: 200)
                        .blur(radius: 30)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(VeloceTheme.accent)
                        .symbolEffect(.bounce, value: bellBounce)
                }
                .scaleEffect(show ? 1 : 0.6)
                .opacity(show ? 1 : 0)

                VStack(spacing: 16) {
                    Text(String(localized: "stay_on_track_title"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(VeloceTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .offset(y: show ? 0 : 18)
                        .opacity(show ? 1 : 0)

                    Text(String(localized: "stay_on_track_description"))
                        .font(.system(size: 16))
                        .foregroundStyle(VeloceTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .offset(y: show ? 0 : 14)
                        .opacity(show ? 1 : 0)

                    // Sample notification pill
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(VeloceTheme.accentBg)
                                .frame(width: 36, height: 36)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(VeloceTheme.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Veloce")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(VeloceTheme.textPrimary)
                            Text(String(localized: "log_spending_today"))
                                .font(.system(size: 12))
                                .foregroundStyle(VeloceTheme.textSecondary)
                        }
                        Spacer()
                        Text(String(localized: "now"))
                            .font(.system(size: 11))
                            .foregroundStyle(VeloceTheme.textTertiary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(VeloceTheme.surface)
                            .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
                    )
                    .offset(y: show ? 0 : 12)
                    .opacity(show ? 1 : 0)
                }
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()

            VStack(spacing: 13) {
                primaryButton(
                    String(localized: "enable_notifications"),
                    action: onEnable
                )

                Button(action: onSkip) {
                    Text(String(localized: "maybe_later"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 56)
            .offset(y: show ? 0 : 28)
            .opacity(show ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.78).delay(0.08)) { show = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { bellBounce.toggle() }
        }
    }
}

// MARK: - Page Apple Pay: Import Connect

private struct PageApplePay: View {
    let onNext: () -> Void

    private enum ConnectState { case idle, loading, connected, denied, unavailable }

    @State private var state: ConnectState = .idle
    @State private var show = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 36) {
                // Hero
                ZStack {
                    Circle()
                        .fill(heroBackground)
                        .frame(width: 148, height: 148)
                    Circle()
                        .fill(heroColor.opacity(0.10))
                        .frame(width: 200)
                        .blur(radius: 30)
                    Image(systemName: heroIcon)
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(heroColor)
                        .symbolEffect(.bounce, value: state == .connected)
                }
                .scaleEffect(show ? 1 : 0.6)
                .opacity(show ? 1 : 0)
                .animation(.spring(response: 0.4), value: state)

                VStack(spacing: 14) {
                    Text(String(localized: titleKey))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(VeloceTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .offset(y: show ? 0 : 16)
                        .opacity(show ? 1 : 0)

                    Text(String(localized: subtitleKey))
                        .font(.system(size: 15))
                        .foregroundStyle(VeloceTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .offset(y: show ? 0 : 12)
                        .opacity(show ? 1 : 0)
                }
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()

            VStack(spacing: 13) {
                if state == .idle {
                    primaryButton(String(localized: "onboarding_applepay_connect_btn"), action: connect)
                } else if state == .loading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(VeloceTheme.accent)
                        .frame(height: 56)
                }

                Button(action: onNext) {
                    Text(state == .connected
                         ? String(localized: "continue")
                         : String(localized: "onboarding_applepay_skip"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 56)
            .opacity(show ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.78).delay(0.08)) { show = true }
            if !FinanceStore.isDataAvailable(.financialData) {
                state = .unavailable
            }
        }
    }

    // MARK: Dynamic content per state

    private var heroIcon: String {
        switch state {
        case .connected:   return "checkmark.circle.fill"
        case .denied:      return "xmark.circle.fill"
        case .unavailable: return "creditcard.trianglebadge.exclamationmark"
        default:           return "creditcard.fill"
        }
    }

    private var heroColor: Color {
        switch state {
        case .connected: return VeloceTheme.ok
        case .denied:    return VeloceTheme.over
        default:         return VeloceTheme.accent
        }
    }

    private var heroBackground: Color {
        switch state {
        case .connected: return VeloceTheme.ok.opacity(0.12)
        case .denied:    return VeloceTheme.over.opacity(0.12)
        default:         return VeloceTheme.accentBg
        }
    }

    private var titleKey: String.LocalizationValue {
        switch state {
        case .connected:   return "onboarding_applepay_connected"
        case .denied:      return "onboarding_applepay_denied"
        case .unavailable: return "apple_pay_not_available"
        default:           return "onboarding_applepay_title"
        }
    }

    private var subtitleKey: String.LocalizationValue {
        switch state {
        case .connected:   return "onboarding_applepay_connected_desc"
        case .denied:      return "onboarding_applepay_denied_desc"
        case .unavailable: return "apple_pay_not_available_desc"
        default:           return "onboarding_applepay_subtitle"
        }
    }

    // MARK: Action

    private func connect() {
        state = .loading
        Task { @MainActor in
            do {
                let status = try await FinanceStore.shared.requestAuthorization()
                withAnimation(.spring(response: 0.4)) {
                    state = (status == .authorized) ? .connected : .denied
                }
                if status == .authorized {
                    try? await Task.sleep(for: .milliseconds(1400))
                    onNext()
                }
            } catch {
                withAnimation { state = .denied }
            }
        }
    }
}

// MARK: - Page 3: Try It

private struct Page3: View {
    @Binding var input:        String
    @Binding var parsedResult: String?
    let onFinish: () -> Void

    @StateObject private var speech = SpeechService()
    @State private var show    = false
    @State private var loading = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Tappable mic hero button
                Button(action: micTapped) {
                    ZStack {
                        Circle()
                            .fill(speech.isListening
                                  ? VeloceTheme.over.opacity(0.12)
                                  : VeloceTheme.accentBg)
                            .frame(width: 110, height: 110)
                        Circle()
                            .fill((speech.isListening ? VeloceTheme.over : VeloceTheme.accent).opacity(0.10))
                            .frame(width: 160)
                            .blur(radius: 24)
                        Image(systemName: speech.isListening
                              ? "stop.circle.fill"
                              : "mic.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(speech.isListening
                                            ? VeloceTheme.over
                                            : VeloceTheme.accent)
                            .symbolEffect(.pulse, isActive: speech.isListening)
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(show ? 1 : 0.7)
                .opacity(show ? 1 : 0)
                .animation(.spring(response: 0.3), value: speech.isListening)

                VStack(spacing: 12) {
                    Text(String(localized: "give_it_a_try"))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(VeloceTheme.textPrimary)

                    Text(
                        speech.isListening
                        ? String(localized: "speech_listening")
                        : String(localized: "speech_idle")
                    )

                        .font(.system(size: 15))
                        .foregroundStyle(VeloceTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.2), value: speech.isListening)
                }
                .opacity(show ? 1 : 0)
                .offset(y: show ? 0 : 14)

                // Input + result
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: loading
                              ? "ellipsis"
                              : speech.isListening ? "waveform" : "mic.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(speech.isListening
                                            ? VeloceTheme.over
                                            : focused ? VeloceTheme.accent
                                            : VeloceTheme.textTertiary)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.variableColor, isActive: speech.isListening)
                            .animation(.default, value: loading)

                        TextField(
                            String(localized: "expense_input_placeholder"),
                            text: $input
                        )
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(VeloceTheme.textPrimary)
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit { tryParse() }

                        if !input.isEmpty {
                            Button(action: tryParse) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(VeloceTheme.accent)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(VeloceTheme.surface)
                            .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        speech.isListening
                                            ? VeloceTheme.over.opacity(0.5)
                                            : focused ? VeloceTheme.accent.opacity(0.45) : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    )
                    .animation(.easeOut(duration: 0.2), value: input.isEmpty)

                    if let result = parsedResult {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(VeloceTheme.ok)
                            Text(result)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(VeloceTheme.textPrimary)
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(VeloceTheme.ok.opacity(0.1))
                        )
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4), value: parsedResult != nil)
                .opacity(show ? 1 : 0)
                .offset(y: show ? 0 : 20)
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()

            primaryButton(
                parsedResult != nil
                ? String(localized: "start_tracking")
                : String(localized: "skip_to_app"),
                action: onFinish
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 56)
            .opacity(show ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.78).delay(0.08)) { show = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { focused = true }
        }
        .task { await speech.requestPermissions() }
        .onChange(of: speech.recognizedText) { _, text in
            if !text.isEmpty { input = text }
        }
        .onChange(of: speech.isListening) { _, listening in
            // Auto-submit when mic recognition finishes
            if !listening && !speech.recognizedText.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { tryParse() }
            }
        }
    }

    // MARK: - Actions

    private func micTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard speech.authStatus == .authorized else { return }
        focused = false
        if speech.isListening {
            speech.stopListening()
        } else {
            input = ""
            parsedResult = nil
            speech.startListening()
        }
    }

    private func tryParse() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        speech.stopListening()
        focused  = false
        loading  = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.4)) {
                if let parsed = AIService.parseExpense(text) {
                    let amt = parsed.amount >= 1_000
                        ? parsed.amount.toCompactCurrency()
                        : parsed.amount.toCurrencyString()

                    parsedResult = String(
                        localized: "expense_added_with_amount",
                        defaultValue: "Added: \(parsed.title.capitalized) — \(amt)",
                        table: nil,
                        comment: "Expense added with amount"
                    )

                } else {
                    parsedResult = String(
                        localized: "expense_added_simple",
                        defaultValue: "Added: \(text.capitalized)",
                        comment: "Expense added without parsed amount"
                    )
                }
            }
            loading = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Shared primary button

private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "A092F8"), Color(hex: "6B5CE7")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: Color(hex: "7B6CF0").opacity(0.4), radius: 14, y: 6)
            )
    }
}

// MARK: - Preview

#Preview {
    OnboardingView().environmentObject(ExpenseViewModel())
}
