import Foundation
import Speech
import AVFoundation
import Combine

/// Listens to what you say (using Apple's speech recognition, on your Mac when supported)
/// and works out how far through the script you are.
///
/// Also measures your speaking pace (words per minute) for Auto speed.
final class SpeechTracker: ObservableObject {
    static let shared = SpeechTracker()

    /// Number of script words you've read so far.
    @Published private(set) var spokenWordCount = 0
    /// Your recent speaking pace, or nil until there's enough to measure.
    @Published private(set) var wordsPerMinute: Double?
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    private let mic = MicrophoneMonitor.shared
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let requestLock = NSLock()

    /// The script, split into words, with each word's location in the original text.
    private(set) var words: [ScriptWord] = []
    private var shouldListen = false

    /// Recent (time, cumulative recognized words) samples for measuring pace.
    private var paceSamples: [(time: TimeInterval, words: Int)] = []
    /// Words recognized in earlier recognition sessions (each session restarts at 0).
    private var wordsInPreviousSessions = 0
    private var wordsInCurrentSession = 0

    private init() {}

    // MARK: Script

    func load(script: String) {
        words = ScriptWord.split(script)
        spokenWordCount = 0
    }

    func resetPosition() {
        spokenWordCount = 0
    }

    /// Fraction of the script (by characters) that has been read, 0...1.
    var spokenFraction: Double {
        guard let last = words.last, last.end > 0 else { return 0 }
        guard spokenWordCount > 0 else { return 0 }
        let index = min(spokenWordCount, words.count) - 1
        return Double(words[index].end) / Double(last.end)
    }

    /// UTF-16 offset in the script where the read part ends.
    var spokenUTF16Offset: Int {
        guard spokenWordCount > 0, !words.isEmpty else { return 0 }
        return words[min(spokenWordCount, words.count) - 1].end
    }

    // MARK: Listening

    func start() {
        shouldListen = true
        guard !isListening else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.shouldListen else { return }
                if status == .authorized {
                    self.errorMessage = nil
                    self.mic.start()
                    self.beginSession()
                } else {
                    self.errorMessage = String(localized: "Speech recognition is turned off for PeekPrompt in System Settings → Privacy & Security.")
                }
            }
        }
    }

    func stop() {
        shouldListen = false
        endSession()
        mic.onBuffer = nil
        isListening = false
        paceSamples.removeAll()
        wordsPerMinute = nil
    }

    private func beginSession() {
        endSession()
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = String(localized: "Speech recognition isn't available right now.")
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true // private and works offline
        }
        request.taskHint = .dictation
        // Give the recognizer the script's words so it favors them.
        request.contextualStrings = Array(Set(words.map(\.text))).prefix(100).map { $0 }

        requestLock.lock()
        self.request = request
        requestLock.unlock()

        mic.onBuffer = { [weak self] buffer in
            guard let self else { return }
            self.requestLock.lock()
            self.request?.append(buffer)
            self.requestLock.unlock()
        }

        wordsInCurrentSession = 0
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.handle(transcript: result.bestTranscription.formattedString)
                }
                // Apple ends a session after a pause or about a minute; start a new one.
                if error != nil || (result?.isFinal ?? false) {
                    self.wordsInPreviousSessions += self.wordsInCurrentSession
                    self.wordsInCurrentSession = 0
                    if self.shouldListen {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                            guard let self, self.shouldListen else { return }
                            self.beginSession()
                        }
                    }
                }
            }
        }
        isListening = true
    }

    private func endSession() {
        task?.cancel()
        task = nil
        requestLock.lock()
        request?.endAudio()
        request = nil
        requestLock.unlock()
    }

    // MARK: Matching what you said to the script

    private func handle(transcript: String) {
        let spoken = ScriptWord.normalizedWords(transcript)
        wordsInCurrentSession = spoken.count
        recordPace()

        guard !spoken.isEmpty, !words.isEmpty else { return }
        if let position = ScriptMatcher.position(of: spoken.suffix(6).map { $0 },
                                                 in: words.map(\.normalized),
                                                 after: spokenWordCount) {
            if position > spokenWordCount { spokenWordCount = position }
        }
    }

    private func recordPace() {
        let now = ProcessInfo.processInfo.systemUptime
        let total = wordsInPreviousSessions + wordsInCurrentSession
        paceSamples.append((now, total))
        paceSamples.removeAll { now - $0.time > 20 } // last 20 seconds
        guard let first = paceSamples.first, now - first.time > 4 else { return }
        let rate = Double(total - first.words) / (now - first.time) * 60
        if rate > 40 && rate < 300 { // ignore nonsense readings
            wordsPerMinute = wordsPerMinute.map { $0 * 0.7 + rate * 0.3 } ?? rate
        }
    }
}

/// A word of the script and where it sits in the text (UTF-16 offsets).
struct ScriptWord {
    let text: String
    let normalized: String
    let start: Int
    let end: Int

    /// Splits a script into words, skipping [cues].
    static func split(_ script: String) -> [ScriptWord] {
        let ns = script as NSString
        var result: [ScriptWord] = []
        let cueRanges = (try? NSRegularExpression(pattern: "\\[[^\\]]*\\]"))?
            .matches(in: script, range: NSRange(location: 0, length: ns.length))
            .map(\.range) ?? []

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { word, range, _, _ in
            guard let word else { return }
            if cueRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) { return }
            let normalized = normalize(word)
            guard !normalized.isEmpty else { return }
            result.append(ScriptWord(text: word, normalized: normalized,
                                     start: range.location, end: range.location + range.length))
        }
        return result
    }

    static func normalize(_ word: String) -> String {
        word.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    static func normalizedWords(_ text: String) -> [String] {
        var result: [String] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { word, _, _, _ in
            if let word {
                let n = normalize(word)
                if !n.isEmpty { result.append(n) }
            }
        }
        return result
    }
}

/// Finds where the last few spoken words line up with the script.
enum ScriptMatcher {
    /// Returns the number of script words read (index just past the match), or nil.
    static func position(of spoken: [String], in script: [String], after current: Int) -> Int? {
        guard !spoken.isEmpty, !script.isEmpty else { return nil }
        // Look a little behind (in case of a repeat) and a fair way ahead (skipped lines).
        let lower = max(0, current - 3)
        let upper = min(script.count - 1, current + 40)
        guard lower <= upper else { return nil }

        var best: (end: Int, score: Int)?
        for end in lower...upper {
            var score = 0
            for k in 0..<spoken.count {
                let scriptIndex = end - k
                if scriptIndex < 0 { break }
                if similar(script[scriptIndex], spoken[spoken.count - 1 - k]) { score += 1 }
            }
            // Prefer the closest match when scores tie.
            if score > (best?.score ?? 0) { best = (end, score) }
        }

        guard let best else { return nil }
        // Need a reasonable agreement, so a single common word ("the") can't jump us ahead.
        let needed = spoken.count >= 3 ? 2 : 1
        guard best.score >= needed else { return nil }
        // Big jumps need stronger evidence.
        if best.end + 1 - current > 12 && best.score < 3 { return nil }
        return best.end + 1
    }

    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 4, b.count >= 4 else { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        return editDistance(a, b) <= 1
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > 1 { return 2 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
