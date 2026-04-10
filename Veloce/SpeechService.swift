import Foundation
internal import Speech
import AVFoundation
import Combine
// MARK: - Speech Recognition Service
// Requires Info.plist keys (already set in build settings):
//   NSMicrophoneUsageDescription
//   NSSpeechRecognitionUsageDescription

final class SpeechService: ObservableObject {
    @Published var recognizedText = ""
    @Published var isListening = false
    @Published var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    /// Computed so it always picks up the latest language setting without restarting the service.
    private var recognizer: SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: Locale(identifier:
            UserDefaults.standard.string(forKey: "veloce_speech_language") ?? "vi-VN"))
    }

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    // MARK: - Permissions

    func requestPermissions() async {
        authStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
    }

    // MARK: - Control

    func startListening() {
        guard !isListening else {
            stopListening()
            return
        }
        recognizedText = ""
        do {
            try beginRecognition()
            isListening = true
        } catch {
            print("SpeechService: \(error.localizedDescription)")
        }
    }

    func stopListening() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        isListening = false
    }

    // MARK: - Private

    private func beginRecognition() throws {
        task?.cancel()
        task = nil

        // 1. Activate session first — this initialises the hardware sample rate.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // 2. Build a valid format from the *session* sample rate.
        //    Querying inputNode.outputFormat(forBus:) before engine.prepare()
        //    can return an uninitialised format (sampleRate = 0), which triggers
        //    the "IsFormatSampleRateAndChannelCountValid" assertion in installTap.
        let hwRate = session.sampleRate > 0 ? session.sampleRate : 44_100
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: hwRate, channels: 1) else {
            throw NSError(domain: "SpeechService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create audio format"])
        }

        // 3. Wire up the recognition request.
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        self.request = req

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            Task { @MainActor [weak self] in
                if let text { self?.recognizedText = text }
                if done { self?.stopListening() }
            }
        }

        // 4. Install tap with the validated format, then start the engine.
        //    The tap closure runs on the real-time audio thread; capture req
        //    directly (not self) to avoid an actor-boundary crossing.
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
            req.append(buf)
        }

        engine.prepare()
        try engine.start()
    }
}
