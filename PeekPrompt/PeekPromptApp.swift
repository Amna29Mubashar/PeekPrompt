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
                let needed = (visible && (mode == .voiceActivated || glow)) || settingsOpen
                if needed { self.mic.start() } else { self.mic.stop() }
            }
            .store(in: &cancellables)

        settings.$voiceSensitivity
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.mic.threshold = self.settings.speakingThreshold
            }
            .store(in: &cancellables)

        settings.$globalShortcuts
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled { self?.registerShortcuts() } else { GlobalHotKeys.shared.unregisterAll() }
            }
            .store(in: &cancellables)
    }

    /// Control + Option + key, so we don't steal common Command shortcuts from other apps.
    private func registerShortcuts() {
        let hotKeys = GlobalHotKeys.shared
        hotKeys.unregisterAll()
        let mods = UInt32(controlKey | optionKey)
        hotKeys.register(keyCode: UInt32(kVK_ANSI_P), modifiers: mods) { ScrollEngine.shared.toggle() }
        hotKeys.register(keyCode: UInt32(kVK_ANSI_H), modifiers: mods) { PrompterSettings.shared.isPrompterVisible.toggle() }
        hotKeys.register(keyCode: UInt32(kVK_ANSI_R), modifiers: mods) { ScrollEngine.shared.restart() }
        hotKeys.register(keyCode: UInt32(kVK_ANSI_M), modifiers: mods) { MicrophoneMonitor.shared.isMuted.toggle() }
        hotKeys.register(keyCode: UInt32(kVK_UpArrow), modifiers: mods) { ScrollEngine.shared.changeSpeed(by: 5) }
        hotKeys.register(keyCode: UInt32(kVK_DownArrow), modifiers: mods) { ScrollEngine.shared.changeSpeed(by: -5) }
    }
}

// MARK: - Menu bar menu

struct MenuContent: View {
    @ObservedObject var settings: PrompterSettings
    @ObservedObject var engine: ScrollEngine
    @ObservedObject var mic: MicrophoneMonitor

    var body: some View {
        Button(settings.isPrompterVisible ? "Hide Prompter" : "Show Prompter") {
            settings.isPrompterVisible.toggle()
        }

        Divider()

        Button(engine.isRunning ? "Pause" : (settings.mode == .voiceActivated ? "Start Listening" : "Play")) {
            engine.toggle()
        }
        Button("Restart from Top") { engine.restart() }

        if settings.mode == .voiceActivated {
            Button(mic.isMuted ? "Unmute Microphone" : "Mute Microphone") { mic.isMuted.toggle() }
        }

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
