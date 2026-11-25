import AppKit
import SwiftUI
import Carbon.HIToolbox

/// A key plus modifier keys, e.g. ⌃⌥P. Modifiers are stored as Carbon flags,
/// which is what the global hot-key system uses.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// What to show for the key itself, e.g. "P", "Space", "→".
    var key: String

    /// A shortcut that's been turned off.
    static let none = KeyCombo(keyCode: UInt32.max, modifiers: 0, key: "")
    var isNone: Bool { keyCode == UInt32.max }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init(_ keyCode: Int, _ modifiers: Int, _ key: String) {
        self.init(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers), key: key)
    }

    var displayString: String {
        guard !isNone else { return String(localized: "Off") }
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    /// Builds a combo from a key press. Returns nil unless ⌃, ⌥ or ⌘ is held,
    /// so a shortcut can't swallow normal typing in other apps.
    static func from(event: NSEvent) -> KeyCombo? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        let hasRequired = modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
        guard hasRequired else { return nil }
        return KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: keyLabel(for: event))
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    private static func keyLabel(for event: NSEvent) -> String {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return characters.isEmpty ? "#\(event.keyCode)" : characters
    }
}

/// Everything that can have a global keyboard shortcut.
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case handsFreeStart, playPause, showHide, restart, mute, faster, slower, nextSegment, previousSegment

    var id: String { rawValue }

    /// Slide shortcuts only matter with Presentation/Memorize mode (Pro).
    static var available: [ShortcutAction] {
        Edition.isProBuild ? allCases : allCases.filter { $0 != .nextSegment && $0 != .previousSegment }
    }

    var title: String {
        switch self {
        case .handsFreeStart: return String(localized: "Start / pause (hands-free start)")
        case .playPause: return String(localized: "Play / pause")
        case .showHide: return String(localized: "Show / hide prompter")
        case .restart: return String(localized: "Restart from top")
        case .mute: return String(localized: "Mute / unmute microphone")
        case .faster: return String(localized: "Faster")
        case .slower: return String(localized: "Slower")
        case .nextSegment: return String(localized: "Next Slide")
        case .previousSegment: return String(localized: "Previous Slide")
        }
    }

    var defaultCombo: KeyCombo {
        let controlOption = controlKey | optionKey
        switch self {
        case .handsFreeStart: return KeyCombo(kVK_Space, cmdKey | shiftKey, "Space")
        case .playPause: return KeyCombo(kVK_ANSI_P, controlOption, "P")
        case .showHide: return KeyCombo(kVK_ANSI_H, controlOption, "H")
        case .restart: return KeyCombo(kVK_ANSI_R, controlOption, "R")
        case .mute: return KeyCombo(kVK_ANSI_M, controlOption, "M")
        case .faster: return KeyCombo(kVK_UpArrow, controlOption, "↑")
        case .slower: return KeyCombo(kVK_DownArrow, controlOption, "↓")
        case .nextSegment: return KeyCombo(kVK_RightArrow, controlOption, "→")
        case .previousSegment: return KeyCombo(kVK_LeftArrow, controlOption, "←")
        }
    }

    func perform() {
        let engine = ScrollEngine.shared
        let settings = PrompterSettings.shared
        switch self {
        case .handsFreeStart:
            settings.isPrompterVisible = true
            engine.toggle()
        case .playPause: engine.toggle()
        case .showHide: settings.isPrompterVisible.toggle()
        case .restart: engine.restart()
        case .mute: MicrophoneMonitor.shared.isMuted.toggle()
        case .faster: engine.changeSpeed(by: 5)
        case .slower: engine.changeSpeed(by: -5)
        case .nextSegment: engine.nextSegment()
        case .previousSegment: engine.previousSegment()
        }
    }
}

// MARK: - Recorder

/// A row with the action's name and a button showing its shortcut.
/// Click the button, then press the new keys.
struct ShortcutRecorderRow: View {
    let action: ShortcutAction
    @ObservedObject var settings: PrompterSettings

    @State private var monitor: Any?
    @State private var message: String?

    private var isRecording: Bool { settings.recordingShortcut == action }
    private var combo: KeyCombo { settings.combo(for: action) }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()

            if combo != action.defaultCombo && !isRecording {
                Button {
                    settings.setCombo(nil, for: action)
                    message = nil
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Reset to default")
            }

            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? String(localized: "Press keys…") : combo.displayString)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(combo.isNone && !isRecording ? .secondary : .primary)
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            .help("Click, then press the new shortcut. Delete turns it off, Esc cancels.")
        }
        .onChange(of: settings.recordingShortcut) { _, current in
            // Another row started recording: stop listening here.
            if current != action { removeMonitor() }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        message = nil
        settings.recordingShortcut = action // also pauses global shortcuts while typing
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard settings.recordingShortcut == action else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:
                stopRecording()
            case kVK_Delete, kVK_ForwardDelete:
                settings.setCombo(.none, for: action)
                stopRecording()
            default:
                guard let newCombo = KeyCombo.from(event: event) else {
                    message = String(localized: "Include ⌃, ⌥ or ⌘ in the shortcut.")
                    return nil
                }
                if let other = settings.action(using: newCombo, except: action) {
                    settings.setCombo(.none, for: other)
                    message = String(localized: "Moved from \u{201C}\(other.title)\u{201D}.")
                }
                settings.setCombo(newCombo, for: action)
                stopRecording()
            }
            return nil // don't type the keys anywhere else
        }
    }

    private func stopRecording() {
        removeMonitor()
        if settings.recordingShortcut == action { settings.recordingShortcut = nil }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
