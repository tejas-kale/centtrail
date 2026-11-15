import AVFoundation
import Combine
import Foundation
@preconcurrency import Speech

/// Captures one utterance locally; the form decides how to apply the resulting text.
@MainActor
final class VoiceCapture: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published private(set) var transcript = ""
    @Published private(set) var completedTranscript: String?
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var sessionID: UUID?
    private var hasInputTap = false
    private var silenceTask: Task<Void, Never>?

    func start(contextualStrings: [String]) async {
        guard !isRecording, !isPreparing else { return }
        let id = UUID()
        sessionID = id
        isPreparing = true
        transcript = ""
        completedTranscript = nil
        errorMessage = nil
        defer { if sessionID == id { isPreparing = false } }

        let speechPermission = await Self.requestSpeechAuthorization()
        guard sessionID == id else { return }
        guard speechPermission == .authorized else {
            errorMessage = "Allow Speech Recognition for Centtrail in Settings → Privacy & Security, then try the mic again. You can also enter the transaction by hand."
            return
        }
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard sessionID == id else { return }
        guard microphoneAllowed else {
            errorMessage = "Allow Microphone access for Centtrail in Settings → Privacy & Security, then try the mic again. You can also enter the transaction by hand."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device speech recognition is not available for your current language. Enable a supported dictation language in Settings, or enter the transaction by hand."
            return
        }

        do {
            self.recognizer = recognizer
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true)
            #endif

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.contextualStrings = contextualStrings
            self.request = request
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceCaptureError("No microphone input is available. Connect a microphone or enter the transaction by hand.")
            }
            Self.installTap(on: input, format: format, feeding: request)
            hasInputTap = true
            recognitionTask = recognizer.recognitionTask(
                with: request,
                resultHandler: Self.resultHandler(owner: self, sessionID: id)
            )
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            cancel()
            errorMessage = "The microphone could not start: \(error.localizedDescription). Try again or enter the transaction by hand."
        }
    }

    private func handle(text: String?, isFinal: Bool, failure: String?, sessionID id: UUID) {
        guard sessionID == id else { return }
        if let text {
            transcript = text
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFinal {
                scheduleSilenceFinish(sessionID: id)
            }
        }
        if isFinal {
            finish()
        } else if let failure {
            cancel()
            errorMessage = "Speech recognition stopped: \(failure). Try the mic again or enter the transaction by hand."
        }
    }

    private func scheduleSilenceFinish(sessionID id: UUID) {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled, let self, self.sessionID == id, self.isRecording else { return }
            self.finish()
        }
    }

    // Speech and AVAudioEngine invoke these callbacks on background queues. A closure written
    // inside this @MainActor class inherits main-actor isolation, and Swift 6 traps when it runs
    // off the main thread — so the closures are built in nonisolated helpers instead.

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private nonisolated static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        feeding request: SFSpeechAudioBufferRecognitionRequest
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func resultHandler(
        owner: VoiceCapture,
        sessionID id: UUID
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor [weak owner] in
                owner?.handle(text: text, isFinal: isFinal, failure: failure, sessionID: id)
            }
        }
    }

    func finish() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        cancel()
        if text.isEmpty {
            errorMessage = "No speech was heard. Try the mic again or enter the transaction by hand."
        } else {
            completedTranscript = text
        }
    }

    func cancel() {
        silenceTask?.cancel()
        silenceTask = nil
        sessionID = nil
        isPreparing = false
        isRecording = false
        audioEngine.stop()
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
        request = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

private struct VoiceCaptureError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
