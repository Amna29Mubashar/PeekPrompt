import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What kind of rewrite to do.
enum PolishStyle: String, CaseIterable, Identifiable {
    case natural, shorter, fromNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: return "Make it sound natural"
        case .shorter: return "Make it shorter"
        case .fromNotes: return "Turn notes into a script"
        }
    }

    fileprivate var instruction: String {
        switch self {
        case .natural:
            return "Rewrite the text so it sounds natural when spoken aloud: short sentences, everyday words, contractions, and a warm, confident tone. Keep the meaning, facts, names and numbers exactly. Keep roughly the same length."
        case .shorter:
            return "Rewrite the text to be about 30% shorter while keeping every key point, name and number. Use short sentences that are easy to say aloud."
        case .fromNotes:
            return "The text is rough notes or bullet points. Turn it into a flowing script that someone can read aloud: full sentences, natural transitions, a friendly confident tone. Do not invent facts that aren't in the notes."
        }
    }
}

/// Rewrites a script into a spoken style. Uses Apple Intelligence on Macs that have it
/// (runs on-device, nothing is uploaded). Otherwise does a simple rule-based tidy-up.
enum MagicPolish {
    static var usesAppleIntelligence: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Why Apple Intelligence can't be used, if it can't.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings to get AI rewriting. Using basic cleanup for now."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still getting ready (downloading). Using basic cleanup for now."
            case .unavailable(.deviceNotEligible):
                return "This Mac doesn't support Apple Intelligence. Using basic cleanup instead."
            case .unavailable:
                return "Apple Intelligence isn't available right now. Using basic cleanup instead."
            }
        }
        #endif
        return "AI rewriting needs macOS 26 with Apple Intelligence. Using basic cleanup instead."
    }

    static func polish(_ text: String, style: PolishStyle, addPauses: Bool,
                       progress: @escaping (Double) -> Void) async throws -> String {
        var result: String
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), usesAppleIntelligence {
            result = try await polishWithModel(text, style: style, progress: progress)
        } else {
            result = basicCleanup(text)
        }
        #else
        result = basicCleanup(text)
        #endif
        if addPauses { result = addPauseCues(result) }
        progress(1)
        return result
    }

    #if canImport(FoundationModels)
    /// The on-device model has a limited context, so long scripts go in pieces.
    @available(macOS 26.0, *)
    private static func polishWithModel(_ text: String, style: PolishStyle,
                                        progress: @escaping (Double) -> Void) async throws -> String {
        let pieces = pieces(of: text, maxWords: 350)
        var output: [String] = []
        for (index, piece) in pieces.enumerated() {
            progress(Double(index) / Double(pieces.count))
            let session = LanguageModelSession(instructions: """
            You edit teleprompter scripts. \(style.instruction)
            Keep anything in square brackets, like [pause] or [Slide 2], exactly as it is.
            Reply with only the rewritten text. No introduction, no quotes, no markdown.
            """)
            let response = try await session.respond(to: piece)
            output.append(response.content.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output.joined(separator: "\n\n")
    }
    #endif

    /// Groups paragraphs into pieces of about `maxWords` words.
    private static func pieces(of text: String, maxWords: Int) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var pieces: [String] = []
        var current = ""
        for paragraph in paragraphs {
            let words = (current + " " + paragraph).split { $0.isWhitespace }.count
            if !current.isEmpty && words > maxWords {
                pieces.append(current)
                current = paragraph
            } else {
                current = current.isEmpty ? paragraph : current + "\n\n" + paragraph
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.isEmpty ? [text] : pieces
    }

    // MARK: Basic cleanup (works on every Mac)

    /// Removes formatting marks and spells out shorthand that's awkward to read aloud.
    static func basicCleanup(_ text: String) -> String {
        let replacements: [(String, String)] = [
            (#"\be\.g\.,?"#, "for example,"),
            (#"\bi\.e\.,?"#, "that is,"),
            (#"\betc\."#, "and so on."),
            (#"\bvs\.?\b"#, "versus"),
            (#"\bapprox\.?"#, "approximately"),
            (#"\bw/"#, "with"),
            (#"\s&\s"#, " and "),
            (#"(\d)\s?%"#, "$1 percent"),
            (#"\*\*|__|`"#, "")
        ]
        var lines: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            // Markdown headings and bullets/numbering become plain sentences.
            line = line.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            let wasBullet = line.range(of: #"^([-*•▪–]|\d+[.)])\s+"#, options: .regularExpression) != nil
            line = line.replacingOccurrences(of: #"^([-*•▪–]|\d+[.)])\s+"#, with: "", options: .regularExpression)
            for (pattern, replacement) in replacements {
                line = line.replacingOccurrences(of: pattern, with: replacement,
                                                 options: [.regularExpression, .caseInsensitive])
            }
            line = line.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            if wasBullet, let last = line.last, !".!?:;]".contains(last) {
                line += "."
            }
            if let first = line.first, first.isLowercase, wasBullet {
                line = first.uppercased() + line.dropFirst()
            }
            lines.append(line)
        }
        return ScriptImporter.tidy(lines.joined(separator: "\n"))
    }

    /// Adds a [pause] cue between paragraphs.
    static func addPauseCues(_ text: String) -> String {
        text.components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph.hasSuffix("[pause]") || paragraph.hasPrefix("[Slide") ? paragraph : paragraph + " [pause]"
            }
            .joined(separator: "\n\n")
    }
}

// MARK: - Sheet

struct MagicPolishSheet: View {
    @ObservedObject var settings: PrompterSettings
    @Environment(\.dismiss) private var dismiss

    @State private var style: PolishStyle = .natural
    @State private var addPauses = false
    @State private var result: String?
    @State private var isWorking = false
    @State private var progress = 0.0
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Magic Polish", systemImage: "wand.and.stars")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(MagicPolish.usesAppleIntelligence ? "Apple Intelligence · on this Mac" : "Basic cleanup")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            if let reason = MagicPolish.unavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }

            Picker("Style", selection: $style) {
                ForEach(PolishStyle.allCases) { Text($0.title).tag($0) }
            }
            .disabled(!MagicPolish.usesAppleIntelligence)
            Toggle("Add a [pause] cue between paragraphs", isOn: $addPauses)

            Group {
                if let result {
                    TextEditor(text: Binding(get: { result }, set: { self.result = $0 }))
                        .font(.system(size: 13, design: .rounded))
                } else if isWorking {
                    VStack(spacing: 10) {
                        ProgressView(value: progress)
                        Text("Polishing \u{201C}\(settings.currentTitle)\u{201D}…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Rewrites \u{201C}\(settings.currentTitle)\u{201D} so it's easier to say out loud. You'll see the result here before anything changes.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 240)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if let result {
                    Button("Save as New Script") {
                        settings.addScript(title: settings.currentTitle + " (polished)", body: result,
                                           folder: settings.scripts.first { $0.id == settings.currentScriptID }?.folder)
                        dismiss()
                    }
                    Button("Replace Script") {
                        settings.script = result
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Polish") { run() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking || settings.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }

    private func run() {
        isWorking = true
        errorMessage = nil
        progress = 0
        let text = settings.script
        Task {
            do {
                let polished = try await MagicPolish.polish(text, style: style, addPauses: addPauses) { value in
                    Task { @MainActor in progress = value }
                }
                await MainActor.run {
                    result = polished
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Couldn't polish this script: \(error.localizedDescription)"
                    isWorking = false
                }
            }
        }
    }
}
