import SwiftUI
internal import Speech

struct InputBarView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @StateObject private var speech = SpeechService()

    @State private var text = ""
    @FocusState private var textFocused: Bool
    @State private var showPermissionAlert = false
    @State private var parseFailed = false

    var onManualAdd: () -> Void = {}

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
        .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow microphone and speech recognition access to use voice input.")
        }
        .task { await speech.requestPermissions() }
        .onChange(of: speech.recognizedText) { _, newVal in
            if !newVal.isEmpty { text = newVal }
        }
    }

    // MARK: - Listening banner

    private var listeningBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(VeloceTheme.over)
                .frame(width: 7, height: 7)

            Text(speech.recognizedText.isEmpty ? "Listening…" : speech.recognizedText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VeloceTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            Button("Done") { finishListening() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VeloceTheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(VeloceTheme.surface.opacity(0.9))
    }

    // MARK: - Main input row

    private var inputRow: some View {
        HStack(spacing: 10) {
            // Text field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(VeloceTheme.textTertiary)

                TextField("Ăn phở 50k, Grab 30k…", text: $text)
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

            // Action buttons
            if !text.isEmpty {
                sendButton.transition(.scale.combined(with: .opacity))
            } else if !textFocused {
                micButton.transition(.scale.combined(with: .opacity))
                addButton.transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sendButton: some View {
        Button(action: submit) {
            ZStack {
                Circle()
                    .fill(VeloceTheme.accent)
                    .frame(width: 44, height: 44)
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
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
        Button(action: onManualAdd) {
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
        guard !trimmed.isEmpty else { return }
        speech.stopListening()
        let ok = vm.parseAndAddExpense(from: trimmed)
        if ok {
            text = ""
            textFocused = false
        } else {
            withAnimation { parseFailed = true }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation { parseFailed = false }
            }
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
