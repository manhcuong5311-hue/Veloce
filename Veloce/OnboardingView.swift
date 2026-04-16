import SwiftUI
internal import Speech

// MARK: - OnboardingView (3 pages)

struct OnboardingView: View {
    @EnvironmentObject private var vm: ExpenseViewModel

    @State private var page          = 0
    @State private var income        = ""
    @State private var savingsGoal   = ""
    @State private var tryInput      = ""
    @State private var parsedResult: String? = nil

    @AppStorage("veloce_onboarding_done") private var onboardingDone = false

    // 4 pages: 0 Welcome | 1 Setup | 2 Notifications | 3 Try It
    private let totalPages = 4

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
                    Page3(input: $tryInput, parsedResult: $parsedResult,
                          onFinish: finish).tag(3)
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
                        label:       "Monthly income",
                        placeholder: "e.g. 15,000,000",
                        icon:        "banknote",
                        text:        $income
                    )
                    setupField(
                        label:       "Monthly savings goal",
                        placeholder: "e.g. 3,000,000",
                        icon:        "target",
                        text:        $savingsGoal
                    )
                }
                .opacity(show ? 1 : 0)
                .offset(y: show ? 0 : 22)
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()

            VStack(spacing: 13) {
                primaryButton("Continue", action: onContinue)

                Button(action: onSkip) {
                    Text("Skip for now")
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
        }
    }

    @ViewBuilder
    private func setupField(
        label:       String,
        placeholder: String,
        icon:        String,
        text:        Binding<String>
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
            }

            TextField(placeholder, text: text)
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(VeloceTheme.textPrimary)
                .keyboardType(.numberPad)
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
                    Text("Stay on track\nwith your spending")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(VeloceTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .offset(y: show ? 0 : 18)
                        .opacity(show ? 1 : 0)

                    Text("Get gentle reminders to log expenses\nand track your budget.")
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
                            Text("Did you log your spending today?")
                                .font(.system(size: 12))
                                .foregroundStyle(VeloceTheme.textSecondary)
                        }
                        Spacer()
                        Text("now")
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
                primaryButton("Enable Notifications", action: onEnable)

                Button(action: onSkip) {
                    Text("Maybe Later")
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
                    Text("Give it a try")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(VeloceTheme.textPrimary)

                    Text(speech.isListening
                         ? "Listening… tap the mic to stop"
                         : "Tap the mic to speak, or type an expense below")
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

                        TextField("coffee 40k", text: $input)
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
                parsedResult != nil ? "Start Tracking" : "Skip to App",
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
                    parsedResult = "Added: \(parsed.title.capitalized) — \(amt)"
                } else {
                    parsedResult = "Added: \(text.capitalized)"
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
