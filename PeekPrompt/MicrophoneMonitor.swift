import AVFoundation
import Accelerate
import Combine
import CoreGraphics

/// Listens to the microphone and answers two questions, many times a second:
///  - `level`: how loud is it right now (0...1)? Drives the glowing border.
///  - `isSpeaking`: is the user talking? Drives Voice-Activated scrolling.
///
/// No audio is recorded, transcribed, or sent anywhere. We only measure loudness.
final class MicrophoneMonitor: ObservableObject {
    static let shared = MicrophoneMonitor()

    /// Smoothed loudness, 0 (silence) ... 1 (very loud).
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var isSpeaking = false
    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    @Published var isMuted = false {
        didSet {
            if isMuted {
                activeUntil = 0
                isSpeaking = false
            }
        }
    }

    /// Extra listener for raw audio (used by word tracking). Called on the audio thread.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// Level that counts as speech. Set from the sensitivity slider.
    var threshold: CGFloat = 0.275

    private let engine = AVAudioEngine()
    private var configObserver: NSObjectProtocol?

    // Voice activity detection state
    private var activeUntil: TimeInterval = 0
    private var framesAboveThreshold = 0
    /// Keep "speaking" true for a moment after the voice drops,
    /// so the text doesn't stutter between words.
    private let hangover: TimeInterval = 0.7

    private init() {
        // If the user plugs in headphones or switches mic, restart cleanly.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.stop()
            self.start()
        }
    }

    func start() {
        guard !isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.startEngine() } else { self?.permissionDenied = true }
                }
            }
        default:
            permissionDenied = true
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
        isSpeaking = false
        activeUntil = 0
        framesAboveThreshold = 0
    }

    private func startEngine() {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("PeekPrompt: no microphone available")
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            permissionDenied = false
        } catch {
            input.removeTap(onBus: 0)
            print("PeekPrompt: could not start microphone: \(error)")
        }
    }

    /// Runs on the audio thread.
    private func process(_ buffer: AVAudioPCMBuffer) {
        onBuffer?(buffer)
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = vDSP_Length(buffer.frameLength)
        guard count > 0 else { return }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, count)

        // Convert to decibels and map -60 dB...0 dB onto 0...1.
        let decibels = 20 * log10(max(rms, 0.000_000_1))
        let normalized = CGFloat(min(max((decibels + 60) / 60, 0), 1))
        let timestamp = ProcessInfo.processInfo.systemUptime

        DispatchQueue.main.async { [weak self] in
            self?.update(rawLevel: normalized, at: timestamp)
        }
    }

    private func update(rawLevel: CGFloat, at timestamp: TimeInterval) {
        let input = isMuted ? 0 : rawLevel

        // Rise quickly, fall slowly: feels natural for the glow.
        let smoothing: CGFloat = input > level ? 0.5 : 0.12
        level += (input - level) * smoothing

        guard !isMuted else { return }

        // Count as speech after 2 loud-ish frames in a row, or 1 clearly loud frame.
        if input >= threshold {
            framesAboveThreshold += 1
            if framesAboveThreshold >= 2 || input >= threshold + 0.15 {
                activeUntil = timestamp + hangover
            }
        } else {
            framesAboveThreshold = 0
        }

        let speaking = timestamp < activeUntil
        if speaking != isSpeaking { isSpeaking = speaking }
    }
}
