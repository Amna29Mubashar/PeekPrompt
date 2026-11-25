import Foundation

/// Splits a script into the pieces shown one at a time in
/// Presentation mode (slides) and Memorize mode (chunks).
enum ScriptSegments {
    /// Slides are separated by a line like "[Slide 3]" (added when you import a
    /// PowerPoint) or a line containing just "---".
    static func slides(_ script: String) -> [String] {
        var slides: [String] = []
        var current: [String] = []

        func flush() {
            let text = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { slides.append(text) }
            current = []
        }

        for line in script.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isSlideMarker = trimmed.range(of: #"^\[slide\b[^\]]*\]$"#, options: [.regularExpression, .caseInsensitive]) != nil
            if trimmed == "---" || isSlideMarker {
                flush()
                if isSlideMarker { current.append(trimmed) } // keep the [Slide N] cue visible
            } else {
                current.append(line)
            }
        }
        flush()
        return slides
    }

    /// Chunks for memorizing: one paragraph each, with long paragraphs split
    /// into groups of about two sentences.
    static func chunks(_ script: String, maxWords: Int = 40) -> [String] {
        let paragraphs = script
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result: [String] = []
        for paragraph in paragraphs {
            if wordCount(paragraph) <= maxWords {
                result.append(paragraph)
                continue
            }
            var group = ""
            for sentence in sentences(paragraph) {
                if !group.isEmpty, wordCount(group + " " + sentence) > maxWords {
                    result.append(group)
                    group = sentence
                } else {
                    group = group.isEmpty ? sentence : group + " " + sentence
                }
            }
            if !group.isEmpty { result.append(group) }
        }
        return result
    }

    private static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                result.append(sentence)
            }
        }
        return result.isEmpty ? [text] : result
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

/// How much of the script Memorize mode hides.
enum MemorizeLevel: Int, CaseIterable, Identifiable {
    case showAll = 0, hideSome, hideMost, firstLetters

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .showAll: return String(localized: "Show everything")
        case .hideSome: return String(localized: "Hide some words")
        case .hideMost: return String(localized: "Hide most words")
        case .firstLetters: return String(localized: "First letters only")
        }
    }

    /// Replaces hidden words with their first letter plus underscores. Keeps the text
    /// the same length, so positions (e.g. for Word Tracking) still line up.
    /// Words before `revealUpTo` (UTF-16 offset) are always shown.
    func apply(to text: String, revealUpTo: Int = 0) -> String {
        guard self != .showAll else { return text }
        let ns = NSMutableString(string: text)
        let fullRange = NSRange(location: 0, length: ns.length)
        // Leave [cues] alone.
        let cueRanges = (try? NSRegularExpression(pattern: "\\[[^\\]]*\\]"))?
            .matches(in: text, range: fullRange).map(\.range) ?? []

        var wordIndex = 0
        var replacements: [(NSRange, String)] = []
        ns.enumerateSubstrings(in: fullRange, options: .byWords) { word, range, _, _ in
            guard let word else { return }
            if cueRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) { return }
            defer { wordIndex += 1 }
            if range.location + range.length <= revealUpTo { return }

            let hide: Bool
            switch self {
            case .showAll: hide = false
            case .hideSome: hide = wordIndex % 3 == 2
            case .hideMost: hide = wordIndex % 3 != 0
            case .firstLetters: hide = true
            }
            guard hide, word.utf16.count > 1, let first = word.first else { return }
            let rest = String(repeating: "_", count: word.utf16.count - String(first).utf16.count)
            replacements.append((range, String(first) + rest))
        }
        for (range, replacement) in replacements.reversed() {
            ns.replaceCharacters(in: range, with: replacement)
        }
        return ns as String
    }
}
