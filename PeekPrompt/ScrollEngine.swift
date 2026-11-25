import Foundation
import Combine
import QuartzCore

/// Moves the script. Runs a 60 fps timer while playing and decides,
/// each frame, whether the text should advance.
final class ScrollEngine: ObservableObject {
    static let shared = ScrollEngine()

    /// How far the script has scrolled, in points.
    @Published var offset: CGFloat = 0
    /// True after the user presses Play (or Start Listening in voice mode).
    @Published private(set) var isRunning = false
    /// True on frames where the text is actually moving.
    @Published private(set) var isAdvancing = false
    @Published var isHovering = false
    /// Seconds left in the 3-2-1 countdown, or nil when not counting down.
    @Published private(set) var countdown: Int?

    /// Set by the view once it has measured the text.
    var contentHeight: CGFloat = 0

    private let settings: PrompterSettings
    private let mic: MicrophoneMonitor
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var lastFrameTime: CFTimeInterval = 0

    var maxOffset: CGFloat { max(0, contentHeight) }

    var progress: Double {
        guard maxOffset > 0 else { return 0 }
        return Double(min(max(offset / maxOffset, 0), 1))
    }

    var isFinished: Bool { contentHeight > 0 && offset >= maxOffset }

    private init(settings: PrompterSettings = .shared, mic: MicrophoneMonitor = .shared) {
        self.settings = settings
        self.mic = mic
    }

    // MARK: Controls

    func play() {
        if isFinished { offset = 0 }
        isRunning = true
        if settings.mode == .voiceActivated { mic.start() }

        // Count down only when starting from the top, so resuming mid-script is instant.
        if offset == 0 && settings.countdownSeconds > 0 {
            startCountdown(from: settings.countdownSeconds)
        } else {
            startTimer()
        }
    }

    func pause() {
        isRunning = false
        isAdvancing = false
        cancelCountdown()
        stopTimer()
    }

    // MARK: Countdown

    private func startCountdown(from seconds: Int) {
        cancelCountdown()
        countdown = seconds
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let remaining = self.countdown else { return }
            if remaining <= 1 {
                self.cancelCountdown()
                self.startTimer()
            } else {
                self.countdown = remaining - 1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = nil
    }

    func toggle() {
        isRunning ? pause() : play()
    }

    func restart() {
        offset = 0
        if isRunning { lastFrameTime = CACurrentMediaTime() }
    }

    /// Manual scrolling (trackpad / mouse wheel). Positive moves forward.
    func nudge(by delta: CGFloat) {
        offset = min(max(0, offset + delta), maxOffset)
    }

    func changeSpeed(by delta: Double) {
        settings.speed = min(max(settings.speed + delta, 5), 150)
    }

    // MARK: Frame loop

    private func startTimer() {
        stopTimer()
        lastFrameTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        // Cap the step so a hiccup (e.g. the Mac waking up) can't jump the text.
        let deltaTime = min(now - lastFrameTime, 0.1)
        lastFrameTime = now

        let hoverPaused = isHovering && settings.pauseOnHover
        let shouldMove: Bool
        switch settings.mode {
        case .classic:
            shouldMove = !hoverPaused
        case .voiceActivated:
            shouldMove = !hoverPaused && !mic.isMuted && mic.isSpeaking
        }

        if isAdvancing != shouldMove { isAdvancing = shouldMove }
        guard shouldMove, contentHeight > 0 else { return }

        offset = min(offset + CGFloat(settings.speed * deltaTime), maxOffset)
        if offset >= maxOffset { pause() }
    }
}
