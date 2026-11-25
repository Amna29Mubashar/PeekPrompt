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

/// Every user setting, saved automatically to UserDefaults.
final class PrompterSettings: ObservableObject {
    static let shared = PrompterSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let script = "script"
        static let mode = "mode"
        static let speed = "speed"
        static let fontSize = "fontSize"
        static let lineSpacing = "lineSpacing"
        static let width = "width"
        static let height = "height"
        static let hideFromCapture = "hideFromCapture"
        static let glowEnabled = "glowEnabled"
        static let glowPalette = "glowPalette"
        static let voiceSensitivity = "voiceSensitivity"
        static let pauseOnHover = "pauseOnHover"
        static let showProgress = "showProgress"
        static let globalShortcuts = "globalShortcuts"
    }

    // MARK: Script
    @Published var script: String { didSet { defaults.set(script, forKey: Key.script) } }

    // MARK: Scrolling
    @Published var mode: ScrollMode { didSet { defaults.set(mode.rawValue, forKey: Key.mode) } }
    /// Points per second.
    @Published var speed: Double { didSet { defaults.set(speed, forKey: Key.speed) } }
    /// 0 = needs a loud voice, 1 = reacts to a whisper.
    @Published var voiceSensitivity: Double { didSet { defaults.set(voiceSensitivity, forKey: Key.voiceSensitivity) } }
    @Published var pauseOnHover: Bool { didSet { defaults.set(pauseOnHover, forKey: Key.pauseOnHover) } }

    // MARK: Appearance
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Key.fontSize) } }
    @Published var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: Key.lineSpacing) } }
    @Published var width: Double { didSet { defaults.set(width, forKey: Key.width) } }
    /// Height of the text area below the notch.
    @Published var height: Double { didSet { defaults.set(height, forKey: Key.height) } }
    @Published var glowEnabled: Bool { didSet { defaults.set(glowEnabled, forKey: Key.glowEnabled) } }
    @Published var glowPalette: GlowPalette { didSet { defaults.set(glowPalette.rawValue, forKey: Key.glowPalette) } }
    @Published var showProgress: Bool { didSet { defaults.set(showProgress, forKey: Key.showProgress) } }

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
        script = d.string(forKey: Key.script) ?? PrompterSettings.sampleScript
        mode = ScrollMode(rawValue: d.string(forKey: Key.mode) ?? "") ?? .classic
        speed = d.object(forKey: Key.speed) as? Double ?? 30
        voiceSensitivity = d.object(forKey: Key.voiceSensitivity) as? Double ?? 0.5
        pauseOnHover = d.object(forKey: Key.pauseOnHover) as? Bool ?? true
        fontSize = d.object(forKey: Key.fontSize) as? Double ?? 16
        lineSpacing = d.object(forKey: Key.lineSpacing) as? Double ?? 4
        width = d.object(forKey: Key.width) as? Double ?? 360
        height = d.object(forKey: Key.height) as? Double ?? 140
        glowEnabled = d.object(forKey: Key.glowEnabled) as? Bool ?? true
        glowPalette = GlowPalette(rawValue: d.string(forKey: Key.glowPalette) ?? "") ?? .aurora
        showProgress = d.object(forKey: Key.showProgress) as? Bool ?? true
        hideFromCapture = d.object(forKey: Key.hideFromCapture) as? Bool ?? true
        globalShortcuts = d.object(forKey: Key.globalShortcuts) as? Bool ?? true
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
