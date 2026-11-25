import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox

@main
struct PeekPromptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(settings: .shared, engine: .shared, mic: .shared)
        } label: {
            Image(systemName: "text.viewfinder")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: .shared, engine: .shared, mic: .shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PrompterWindowController?
    private var cancellables = Set<AnyCancellable>()

    private let settings = PrompterSettings.shared
    private let engine = ScrollEngine.shared
    private let mic = MicrophoneMonitor.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar app, no Dock icon
        FontRegistrar.registerBundledFonts()
        windowController = PrompterWindowController(settings: settings, engine: engine, mic: mic, layout: .shared)

        // Keep the microphone on only while something actually needs it.
        Publishers.CombineLatest4(settings.$mode, settings.$glowEnabled, settings.$isPrompterVisible, settings.$isSettingsOpen)
            .receive(on: RunLoop.main)
            .sink { [weak self] mode, glow, visible, settingsOpen in
                guard let self else { return }
                let needed = (visible && (mode.usesMicrophone || glow)) || settingsOpen
                if needed { self.mic.start() } else { self.mic.stop() }
            }
            .store(in: &cancellables)

        // Leaving word-tracking mode stops speech recognition.
        settings.$mode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { mode in
                if mode != .wordTracking { SpeechTracker.shared.stop() }
                if ScrollEngine.shared.isRunning { ScrollEngine.shared.pause() }
            }
            .store(in: &cancellables)

        settings.$voiceSensitivity
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.mic.threshold = self.settings.speakingThreshold
            }
            .store(in: &cancellables)

        // Re-register whenever shortcuts change; pause them while one is being recorded.
        Publishers.CombineLatest3(settings.$globalShortcuts, settings.$shortcuts, settings.$recordingShortcut)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, _, recording in
                if enabled && recording == nil { self?.registerShortcuts() } else { GlobalHotKeys.shared.unregisterAll() }
            }
            .store(in: &cancellables)
    }

    /// Registers each action's shortcut (custom or default). Turned-off ones are skipped.
    private func registerShortcuts() {
        let hotKeys = GlobalHotKeys.shared
        hotKeys.unregisterAll()
        for action in ShortcutAction.allCases {
            let combo = settings.combo(for: action)
            guard !combo.isNone else { continue }
            hotKeys.register(keyCode: combo.keyCode, modifiers: combo.modifiers) { action.perform() }
        }
    }
}

// MARK: - Menu bar menu

struct MenuContent: View {
    @ObservedObject var settings: PrompterSettings
    @ObservedObject var engine: ScrollEngine
    @ObservedObject var mic: MicrophoneMonitor

    var body: some View {
        Button(settings.isPrompterVisible ? String(localized: "Hide Prompter") : String(localized: "Show Prompter")) {
            settings.isPrompterVisible.toggle()
        }

        Divider()

        Button(engine.isRunning ? String(localized: "Pause") : (settings.mode.usesMicrophone ? String(localized: "Start Listening") : String(localized: "Play"))) {
            engine.toggle()
        }
        Button("Restart from Top") { engine.restart() }

        if settings.mode.usesMicrophone {
            Button(mic.isMuted ? String(localized: "Unmute Microphone") : String(localized: "Mute Microphone")) { mic.isMuted.toggle() }
        }

        Picker("Script", selection: Binding(
            get: { settings.currentScriptID },
            set: { settings.selectScript($0) }
        )) {
            ForEach(settings.orderedScripts) { script in
                Text(script.title).tag(script.id)
            }
        }

        Toggle("Presentation Mode (one slide at a time)", isOn: $settings.presentationMode)
        Toggle("Memorize Mode", isOn: $settings.memorizeMode)

        Picker("Scrolling Mode", selection: $settings.mode) {
            ForEach(ScrollMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }

        Divider()

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit PeekPrompt") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
