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
    /// Time spent presenting since the last restart (excludes the countdown).
    @Published private(set) var elapsed: TimeInterval = 0
    /// Seconds left in the 3-2-1 countdown, or nil when not counting down.
    @Published private(set) var countdown: Int?

    /// Set by the view once it has measured the text.
    var contentHeight: CGFloat = 0

    private let settings: PrompterSettings
    private let mic: MicrophoneMonitor
    private let tracker = SpeechTracker.shared
    private var timer: Timer?
    private var countdownTimer: Timer?
    /// True during the short pause at the end before looping / moving on.
    private var isHandlingEnd = false
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
        if isFinished { offset = 0; elapsed = 0 }
        isRunning = true
        if settings.mode == .voiceActivated {
            mic.start()
            if settings.autoSpeed { tracker.start() } // only to measure your pace
        }
        if settings.mode == .wordTracking {
            if tracker.words.isEmpty { tracker.load(script: settings.script) }
            tracker.start()
        }

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
        tracker.stop()
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
        elapsed = 0
        tracker.resetPosition()
        if isRunning { lastFrameTime = CACurrentMediaTime() }
    }

    /// Manual scrolling (trackpad / mouse wheel). Positive moves forward.
    func nudge(by delta: CGFloat) {
        offset = min(max(0, offset + delta), maxOffset)
    }

    func changeSpeed(by delta: Double) {
        settings.speed = min(max(settings.speed + delta, 5), 150)
    }

    // MARK: End of script

    /// Stop, start over, or move on to the next script, depending on the setting.
    private func reachedEnd() {
        guard !isHandlingEnd else { return }
        switch settings.endAction {
        case .stop:
            pause()
        case .loop, .next:
            let nextID = settings.endAction == .next ? settings.nextScriptID : nil
            if settings.endAction == .next && nextID == nil {
                pause() // last script in the list
                return
            }
            // Leave the last line on screen for a moment before continuing.
            isHandlingEnd = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.isHandlingEnd = false
                guard self.isRunning else { return }
                if let nextID {
                    self.settings.selectScript(nextID) // the view restarts from the top
                    self.tracker.load(script: self.settings.script)
                }
                self.restart()
            }
        }
    }

    // MARK: Auto speed

    /// Points per second to scroll right now. With Auto speed on in Voice-Activated mode,
    /// this follows your measured words-per-minute; otherwise it's the slider value.
    var effectiveSpeed: CGFloat {
        if settings.mode == .voiceActivated, settings.autoSpeed,
           let wpm = tracker.wordsPerMinute, !tracker.words.isEmpty, contentHeight > 0 {
            let pointsPerWord = contentHeight / CGFloat(tracker.words.count)
            return min(max(CGFloat(wpm / 60) * pointsPerWord, 5), 150)
        }
        return CGFloat(settings.speed)
    }

    // MARK: Pacing

    /// How far ahead (+) or behind (−) schedule you are, in seconds. nil without a target.
    var paceDelta: TimeInterval? {
        let target = settings.targetMinutes * 60
        guard target > 0, elapsed > 2 else { return nil }
        // Where you'd be if you were exactly on time vs. where you are.
        return (progress * target) - elapsed
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
        elapsed += deltaTime

        let hoverPaused = isHovering && settings.pauseOnHover

        // Word tracking: glide toward wherever your voice is in the script.
        if settings.mode == .wordTracking {
            guard !hoverPaused, contentHeight > 0 else {
                if isAdvancing { isAdvancing = false }
                return
            }
            let target = CGFloat(tracker.spokenFraction) * maxOffset
            let gap = target - offset
            let moving = abs(gap) > 0.5
            if isAdvancing != moving { isAdvancing = moving }
            if moving { offset += gap * CGFloat(min(1, deltaTime * 5)) }
            if !tracker.words.isEmpty, tracker.spokenWordCount >= tracker.words.count {
                reachedEnd()
            }
            return
        }

        let shouldMove: Bool
        switch settings.mode {
        case .classic:
            shouldMove = !hoverPaused
        case .voiceActivated:
            shouldMove = !hoverPaused && !mic.isMuted && mic.isSpeaking
        case .wordTracking:
            shouldMove = false // handled above
        }

        if isAdvancing != shouldMove { isAdvancing = shouldMove }
        guard shouldMove, contentHeight > 0 else { return }

        offset = min(offset + effectiveSpeed * CGFloat(deltaTime), maxOffset)
        if offset >= maxOffset { reachedEnd() }
    }
}
