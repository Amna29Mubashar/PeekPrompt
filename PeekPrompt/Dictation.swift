import Foundation
import Speech
import AVFoundation
import Combine

/// Speak to write your script. Uses Apple's speech recognition (on-device when supported)
/// and hands finished text to `onText`.
final class Dictation: ObservableObject {
    static let shared = Dictation()

    @Published private(set) var isDictating = false
    /// What's been heard so far in the current phrase (not yet added to the script).
    @Published private(set) var liveText = ""
    @Published private(set) var errorMessage: String?

    /// Receives each finished piece of text.
    var onText: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()

    private init() {}

    func toggle() {
        isDictating ? stop() : start()
    }

    func start() {
        guard !isDictating else { return }
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else {
                    self.errorMessage = "Speech recognition is turned off for PeekPrompt in System Settings → Privacy & Security."
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        if granted { self.beginAudio() } else {
                            self.errorMessage = "PeekPrompt doesn't have microphone access."
                        }
                    }
                }
            }
        }
    }

    func stop() {
        guard isDictating else { return }
        isDictating = false
        commitLiveText()
        task?.cancel()
        task = nil
        lock.lock(); request?.endAudio(); request = nil; lock.unlock()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func beginAudio() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            errorMessage = "No microphone found."
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock(); self.request?.append(buffer); self.lock.unlock()
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = "Couldn't start the microphone."
            return
        }
        isDictating = true
        beginSession()
    }

    private func beginSession() {
        guard isDictating else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            stop()
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        lock.lock(); self.request = request; lock.unlock()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.liveText = result.bestTranscription.formattedString
                }
                // Each session ends after a pause or about a minute: save the text and keep going.
                if error != nil || (result?.isFinal ?? false) {
                    self.commitLiveText()
                    if self.isDictating {
                        self.lock.lock(); self.request?.endAudio(); self.lock.unlock()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                            self?.beginSession()
                        }
                    }
                }
            }
        }
    }

    private func commitLiveText() {
        let text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        liveText = ""
        if !text.isEmpty { onText?(text) }
    }
}
