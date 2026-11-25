import SwiftUI
import Combine

/// How the script moves.
enum ScrollMode: String, CaseIterable, Identifiable {
    case classic
    case voiceActivated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .voiceActivated: return "Voice-Activated"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "Scrolls at a steady speed you choose."
        case .voiceActivated: return "Scrolls while you speak. Pauses when you go quiet or mute."
        }
    }

    var symbol: String {
        switch self {
        case .classic: return "play.circle"
        case .voiceActivated: return "waveform.circle"
        }
    }
}

/// Where the prompter lives on screen.
enum PrompterPlacement: String, CaseIterable, Identifiable {
    case notch
    case floating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: return "Under the notch"
        case .floating: return "Anywhere"
        }
    }
}

/// Color sets for the voice-reactive glow.
enum GlowPalette: String, CaseIterable, Identifiable {
    case aurora, sunset, ocean, mono

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colors: [Color] {
        switch self {
        case .aurora: return [.cyan, .purple, .pink, .cyan]
        case .sunset: return [.orange, .pink, .red, .orange]
        case .ocean:  return [.blue, .teal, .mint, .blue]
        case .mono:   return [.white, .gray, .white]
        }
    }
}

/// One saved script in the library.
struct Script: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var body: String
}

/// Every user setting, saved automatically to UserDefaults.
final class PrompterSettings: ObservableObject {
    static let shared = PrompterSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let script = "script"
        static let scripts = "scripts"
        static let currentScriptID = "currentScriptID"
        static let mode = "mode"
        static let speed = "speed"
        static let fontSize = "fontSize"
        static let lineSpacing = "lineSpacing"
        static let width = "width"
        static let height = "height"
        static let hideFromCapture = "hideFromCapture"
        static let glowEnabled = "glowEnabled"
        static let glowPalette = "glowPalette"
        static let glowStrength = "glowStrength"
        static let voiceSensitivity = "voiceSensitivity"
        static let pauseOnHover = "pauseOnHover"
        static let showProgress = "showProgress"
        static let globalShortcuts = "globalShortcuts"
        static let placement = "placement"
        static let countdownSeconds = "countdownSeconds"
        static let highlightReadingLine = "highlightReadingLine"
        static let fontFamily = "fontFamily"
        static let theme = "theme"
        static let floatingX = "floatingX"
        static let floatingY = "floatingY"
    }

    // MARK: Script library
    /// All saved scripts.
    @Published var scripts: [Script] { didSet { saveScripts() } }
    @Published var currentScriptID: UUID { didSet { defaults.set(currentScriptID.uuidString, forKey: Key.currentScriptID) } }
    /// Text of the script on screen. Editing it updates the matching library entry.
    @Published var script: String {
        didSet {
            defaults.set(script, forKey: Key.script)
            if let index = scripts.firstIndex(where: { $0.id == currentScriptID }), scripts[index].body != script {
                scripts[index].body = script
            }
        }
    }

    var currentTitle: String {
        scripts.first(where: { $0.id == currentScriptID })?.title ?? "Untitled"
    }

    func selectScript(_ id: UUID) {
        guard let chosen = scripts.first(where: { $0.id == id }) else { return }
        currentScriptID = id
        if script != chosen.body { script = chosen.body }
    }

    @discardableResult
    func addScript(title: String = "Untitled Script", body: String = "") -> UUID {
        let new = Script(title: title, body: body)
        scripts.append(new)
        selectScript(new.id)
        return new.id
    }

    func duplicateScript(_ id: UUID) {
        guard let original = scripts.first(where: { $0.id == id }) else { return }
        addScript(title: original.title + " copy", body: original.body)
    }

    func renameScript(_ id: UUID, to title: String) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts[index].title = title
    }

    /// Keeps at least one script so the prompter always has something to show.
    func deleteScript(_ id: UUID) {
        guard scripts.count > 1, let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts.remove(at: index)
        if id == currentScriptID {
            selectScript(scripts[min(index, scripts.count - 1)].id)
        }
    }

    private func saveScripts() {
        if let data = try? JSONEncoder().encode(scripts) {
            defaults.set(data, forKey: Key.scripts)
        }
    }

    // MARK: Scrolling
    @Published var mode: ScrollMode { didSet { defaults.set(mode.rawValue, forKey: Key.mode) } }
    /// Points per second.
    @Published var speed: Double { didSet { defaults.set(speed, forKey: Key.speed) } }
    /// 0 = needs a loud voice, 1 = reacts to a whisper.
    @Published var voiceSensitivity: Double { didSet { defaults.set(voiceSensitivity, forKey: Key.voiceSensitivity) } }
    @Published var pauseOnHover: Bool { didSet { defaults.set(pauseOnHover, forKey: Key.pauseOnHover) } }
    /// Seconds of 3-2-1 countdown before scrolling starts from the top. 0 = off.
    @Published var countdownSeconds: Int { didSet { defaults.set(countdownSeconds, forKey: Key.countdownSeconds) } }

    // MARK: Appearance
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Key.fontSize) } }
    @Published var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: Key.lineSpacing) } }
    @Published var width: Double { didSet { defaults.set(width, forKey: Key.width) } }
    /// Height of the text area below the notch.
    @Published var height: Double { didSet { defaults.set(height, forKey: Key.height) } }
    @Published var glowEnabled: Bool { didSet { defaults.set(glowEnabled, forKey: Key.glowEnabled) } }
    @Published var glowPalette: GlowPalette { didSet { defaults.set(glowPalette.rawValue, forKey: Key.glowPalette) } }
    /// 0.5 = subtle ... 2 = very bold.
    @Published var glowStrength: Double { didSet { defaults.set(glowStrength, forKey: Key.glowStrength) } }
    @Published var fontFamily: PrompterFont { didSet { defaults.set(fontFamily.rawValue, forKey: Key.fontFamily) } }
    @Published var theme: PrompterTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    /// Brighten the line you're reading and dim the rest.
    @Published var highlightReadingLine: Bool { didSet { defaults.set(highlightReadingLine, forKey: Key.highlightReadingLine) } }
    @Published var showProgress: Bool { didSet { defaults.set(showProgress, forKey: Key.showProgress) } }

    // MARK: Position
    @Published var placement: PrompterPlacement { didSet { defaults.set(placement.rawValue, forKey: Key.placement) } }
    /// Bottom-left corner of the prompter in Anywhere mode (screen coordinates). nil = not moved yet.
    @Published var floatingOrigin: CGPoint? {
        didSet {
            if let floatingOrigin {
                defaults.set(Double(floatingOrigin.x), forKey: Key.floatingX)
                defaults.set(Double(floatingOrigin.y), forKey: Key.floatingY)
            } else {
                defaults.removeObject(forKey: Key.floatingX)
                defaults.removeObject(forKey: Key.floatingY)
            }
        }
    }

    // MARK: Privacy & controls
    @Published var hideFromCapture: Bool { didSet { defaults.set(hideFromCapture, forKey: Key.hideFromCapture) } }
    @Published var globalShortcuts: Bool { didSet { defaults.set(globalShortcuts, forKey: Key.globalShortcuts) } }

    // MARK: Runtime state (not saved)
    @Published var isPrompterVisible = true
    @Published var isSettingsOpen = false

    /// The microphone level (0...1) that counts as "speaking".
    var speakingThreshold: CGFloat {
        CGFloat(0.45 - voiceSensitivity * 0.35)
    }

    var wordCount: Int {
        script.split { $0.isWhitespace || $0.isNewline }.count
    }

    private init() {
        let d = UserDefaults.standard
        // Load the library. First launch (or upgrading from a single script) creates one entry.
        var loaded: [Script] = []
        if let data = d.data(forKey: Key.scripts),
           let decoded = try? JSONDecoder().decode([Script].self, from: data) {
            loaded = decoded
        }
        if loaded.isEmpty {
            let existing = d.string(forKey: Key.script)
            loaded = [Script(title: existing == nil ? "Welcome" : "My Script",
                             body: existing ?? PrompterSettings.sampleScript)]
        }
        scripts = loaded
        let savedID = d.string(forKey: Key.currentScriptID).flatMap(UUID.init(uuidString:))
        let current = loaded.first(where: { $0.id == savedID }) ?? loaded[0]
        currentScriptID = current.id
        script = current.body
        mode = ScrollMode(rawValue: d.string(forKey: Key.mode) ?? "") ?? .classic
        speed = d.object(forKey: Key.speed) as? Double ?? 30
        voiceSensitivity = d.object(forKey: Key.voiceSensitivity) as? Double ?? 0.5
        pauseOnHover = d.object(forKey: Key.pauseOnHover) as? Bool ?? true
        countdownSeconds = d.object(forKey: Key.countdownSeconds) as? Int ?? 3
        fontSize = d.object(forKey: Key.fontSize) as? Double ?? 16
        lineSpacing = d.object(forKey: Key.lineSpacing) as? Double ?? 4
        width = d.object(forKey: Key.width) as? Double ?? 360
        height = d.object(forKey: Key.height) as? Double ?? 140
        glowEnabled = d.object(forKey: Key.glowEnabled) as? Bool ?? true
        glowPalette = GlowPalette(rawValue: d.string(forKey: Key.glowPalette) ?? "") ?? .aurora
        glowStrength = d.object(forKey: Key.glowStrength) as? Double ?? 1.4
        fontFamily = PrompterFont(rawValue: d.string(forKey: Key.fontFamily) ?? "") ?? .rounded
        theme = PrompterTheme(rawValue: d.string(forKey: Key.theme) ?? "") ?? .dark
        highlightReadingLine = d.object(forKey: Key.highlightReadingLine) as? Bool ?? true
        showProgress = d.object(forKey: Key.showProgress) as? Bool ?? true
        hideFromCapture = d.object(forKey: Key.hideFromCapture) as? Bool ?? true
        globalShortcuts = d.object(forKey: Key.globalShortcuts) as? Bool ?? true
        placement = PrompterPlacement(rawValue: d.string(forKey: Key.placement) ?? "") ?? .notch
        if let x = d.object(forKey: Key.floatingX) as? Double, let y = d.object(forKey: Key.floatingY) as? Double {
            floatingOrigin = CGPoint(x: x, y: y)
        } else {
            floatingOrigin = nil
        }
        saveScripts() // make sure a first-launch library is stored
    }

    static let sampleScript = """
    Welcome to PeekPrompt. [smile]
    This text sits right under your camera, so you look straight at your audience while you read.

    Hover over me to pause, and scroll with your trackpad to jump around.
    Open Settings from the menu bar to paste in your own script.

    Try Voice-Activated mode: I only move while you're talking. [pause]
    Go quiet, and I wait for you.

    Words in square brackets, like [breathe], are cues. They're dimmed so you don't read them out loud.

    Press Control-Option-P to play or pause from any app.
    Good luck with your recording!
    """
}
