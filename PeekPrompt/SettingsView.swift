import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: PrompterSettings
    @ObservedObject var engine: ScrollEngine
    @ObservedObject var mic: MicrophoneMonitor

    var body: some View {
        VStack(spacing: 0) {
        TabView {
            ScriptTab(settings: settings)
                .tabItem { Label("Script", systemImage: "doc.text") }

            ScrollingTab(settings: settings, mic: mic)
                .tabItem { Label("Scrolling", systemImage: "arrow.down.circle") }

            AppearanceTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            PrivacyTab(settings: settings)
                .tabItem { Label("Privacy & Keys", systemImage: "eye.slash") }
        }

            Divider()
            HStack {
                Button(settings.isPrompterVisible ? String(localized: "Hide Prompter") : String(localized: "Show Prompter")) {
                    settings.isPrompterVisible.toggle()
                }
                Spacer()
                Text("Tip: right-click the prompter for quick actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit PeekPrompt", role: .destructive) { NSApp.terminate(nil) }
            }
            .padding(12)
        }
        .frame(width: 640, height: 540)
        .onAppear {
            settings.isSettingsOpen = true
            // Menu bar apps open Settings behind other windows unless we step forward.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            settings.isSettingsOpen = false
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Script

private struct ScriptTab: View {
    @ObservedObject var settings: PrompterSettings
    @ObservedObject var dictation: Dictation = .shared

    var body: some View {
        HStack(spacing: 12) {
            // Library (the Pro edition swaps in a version with folders)
            Group {
                if let proLibrary = Edition.pro?.view(for: .scriptLibrary) {
                    proLibrary
                } else {
                    ScriptLibraryList(settings: settings)
                }
            }
            .frame(width: 190)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            // Editor
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField("Title", text: Binding(
                        get: { settings.currentTitle },
                        set: { settings.renameScript(settings.currentScriptID, to: $0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))

                    if let accessory = Edition.pro?.view(for: .scriptTitleAccessory) { accessory }
                }

                TextEditor(text: $settings.script)
                    .font(.system(size: 13, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

                if dictation.isDictating || dictation.errorMessage != nil {
                    HStack(spacing: 6) {
                        if dictation.isDictating {
                            Image(systemName: "waveform").foregroundStyle(.red)
                            Text(dictation.liveText.isEmpty ? "Listening… start talking." : dictation.liveText)
                                .lineLimit(2)
                        } else if let error = dictation.errorMessage {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                    .font(.caption)
                }

                // Row 1: actions
                HStack(spacing: 8) {
                    Button {
                        dictation.toggle()
                    } label: {
                        Label(dictation.isDictating ? String(localized: "Stop Dictating") : String(localized: "Dictate"),
                              systemImage: dictation.isDictating ? "stop.circle.fill" : "mic")
                    }
                    .tint(dictation.isDictating ? .red : nil)
                    .fixedSize()
                    .help("Speak and your words are added to the end of the script")

                    if let tools = Edition.pro?.view(for: .scriptEditorTools) { tools }

                    Spacer(minLength: 0)
                }

                // Row 2: info
                HStack(spacing: 8) {
                    Text("\(settings.wordCount) words · about \(readingTime) to read")
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("[cues] in brackets are dimmed")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear {
            // Dictated text goes at the end of the open script.
            dictation.onText = { [weak settings] text in
                guard let settings else { return }
                let current = settings.script
                let separator = current.isEmpty || current.hasSuffix("\n") || current.hasSuffix(" ") ? "" : " "
                settings.script = current + separator + text
            }
        }
        .onDisappear { dictation.stop() }
    }

    /// Average speaking pace is roughly 150 words per minute.
    private var readingTime: String {
        let seconds = Int((Double(settings.wordCount) / 150.0 * 60).rounded())
        return seconds < 60
            ? String(localized: "\(seconds) sec")
            : String(localized: "\(seconds / 60) min \(seconds % 60) sec")
    }
}

/// The free edition's script list: drag to reorder, right-click for more.
struct ScriptLibraryList: View {
    @ObservedObject var settings: PrompterSettings

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding<UUID?>(
                get: { settings.currentScriptID },
                set: { if let id = $0 { settings.selectScript(id) } }
            )) {
                ForEach(settings.scripts) { script in
                    Text(script.title.isEmpty ? String(localized: "Untitled") : script.title)
                        .lineLimit(1)
                        .tag(script.id)
                        .contextMenu {
                            Button("Duplicate") { settings.duplicateScript(script.id) }
                            Divider()
                            Button("Delete", role: .destructive) { settings.deleteScript(script.id) }
                                .disabled(settings.scripts.count < 2)
                        }
                }
                .onMove { source, destination in
                    settings.scripts.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 2) {
                Button { settings.addScript() } label: { Image(systemName: "plus") }
                    .help("New Script")
                Button { settings.deleteScript(settings.currentScriptID) } label: { Image(systemName: "minus") }
                    .help("Delete script")
                    .disabled(settings.scripts.count < 2)
                Spacer()
                ImportButton(settings: settings)
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }
}

/// Opens files and adds each one as a new script.
struct ImportButton: View {
    @ObservedObject var settings: PrompterSettings

    var body: some View {
        Button {
            for file in ScriptImporter.chooseFiles() {
                settings.addScript(title: file.title, body: file.text)
            }
        } label: {
            Label("Import", systemImage: "square.and.arrow.down")
        }
        .help(Edition.isProBuild
              ? String(localized: "Import .txt, .md, .rtf, .docx, .pdf, or PowerPoint speaker notes (.pptx)")
              : String(localized: "Import .txt, .md, .rtf or .docx"))
    }
}

// MARK: - Scrolling

private struct ScrollingTab: View {
    @ObservedObject var settings: PrompterSettings
    @ObservedObject var mic: MicrophoneMonitor

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(Edition.availableModes) { mode in
                        Label(Edition.label(for: mode), systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Pro: Presentation & Memorize modes, Word Tracking status
            if let proSection = Edition.pro?.view(for: .scrollingSection) { proSection }


            Section("Speed") {
                Slider(value: $settings.speed, in: 5...150) {
                    Text("Scroll speed")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
                // Pro: Auto speed and the pacing timer
                if let extras = Edition.pro?.view(for: .speedExtras) { extras }
                Toggle("Pause while the pointer is over the prompter", isOn: $settings.pauseOnHover)
                Picker("At the end of a script", selection: $settings.endAction) {
                    ForEach(Edition.availableEndActions) { action in
                        Text(action.title).tag(action)
                    }
                }
                Picker("Countdown before starting", selection: $settings.countdownSeconds) {
                    Text("Off").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
            }

            Section("Voice") {
                Slider(value: $settings.voiceSensitivity, in: 0...1) {
                    Text("Sensitivity")
                } minimumValueLabel: {
                    Text("Loud").font(.caption)
                } maximumValueLabel: {
                    Text("Whisper").font(.caption)
                }

                VStack(alignment: .leading, spacing: 4) {
                    MicLevelMeter(level: mic.level, threshold: settings.speakingThreshold, isSpeaking: mic.isSpeaking)
                    Text(meterCaption)
                        .font(.caption)
                        .foregroundStyle(mic.permissionDenied ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                }

                if mic.permissionDenied {
                    Button("Open Microphone Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var meterCaption: String {
        if mic.permissionDenied { return String(localized: "PeekPrompt doesn't have microphone access.") }
        if !mic.isRunning { return String(localized: "Microphone is off.") }
        return mic.isSpeaking
            ? String(localized: "Hearing you. Text will move.")
            : String(localized: "Talk normally: the bar should cross the white line when you speak, but not when you're quiet.")
    }
}

/// A live loudness bar with a marker showing where "speaking" begins.
private struct MicLevelMeter: View {
    let level: CGFloat
    let threshold: CGFloat
    let isSpeaking: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(isSpeaking ? Color.green : Color.accentColor)
                    .frame(width: geo.size.width * level)
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .offset(x: geo.size.width * threshold - 1)
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 0.08), value: level)
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @ObservedObject var settings: PrompterSettings
    @State private var displayOptions = DisplayOption.all

    var body: some View {
        Form {
            Section("Display") {
                Picker("Show on", selection: $settings.displayChoice) {
                    ForEach(displayOptions, id: \.choice.storageValue) { option in
                        Text(option.name).tag(option.choice)
                    }
                }
                Text("Choose whether the prompter stays on your MacBook, follows your mouse to an external monitor, or always uses one screen. On a screen without a notch, it hangs from the top center, right under where a webcam usually sits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                displayOptions = DisplayOption.all // a monitor was plugged in or out
            }

            Section("Position") {
                Picker("Show prompter", selection: $settings.placement) {
                    ForEach(PrompterPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.segmented)

                if settings.placement == .floating {
                    HStack {
                        Text("Drag the prompter to move it. Keep it close to your camera for the best eye contact.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset Position") { settings.floatingOrigin = nil }
                    }
                } else {
                    Text("Sits right under the camera, so you look straight at your audience.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Text") {
                Picker("Font", selection: $settings.fontFamily) {
                    ForEach(PrompterFont.allCases) { family in
                        Text(family.title).font(family.font(size: 13)).tag(family)
                    }
                }
                Picker("Theme", selection: $settings.theme) {
                    ForEach(PrompterTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                LabeledSlider(title: "Background opacity", value: Binding(
                    get: { settings.backgroundOpacity * 100 },
                    set: { settings.backgroundOpacity = $0 / 100 }
                ), range: 30...100, unit: "%")
                LabeledSlider(title: "Font size", value: $settings.fontSize, range: 10...36, unit: "pt")
                LabeledSlider(title: "Line spacing", value: $settings.lineSpacing, range: 0...16, unit: "pt")
                Toggle("Highlight the line you're reading", isOn: $settings.highlightReadingLine)
            }

            Section("Size") {
                LabeledSlider(title: "Width", value: $settings.width, range: 220...700, unit: "px")
                LabeledSlider(title: "Height", value: $settings.height, range: 60...360, unit: "px")
                Toggle("Show progress", isOn: $settings.showProgress)
            }

            Section("Voice glow") {
                Toggle("Glowing border that reacts to your voice", isOn: $settings.glowEnabled)
                Picker("Colors", selection: $settings.glowPalette) {
                    ForEach(GlowPalette.allCases) { palette in
                        Text(palette.title).tag(palette)
                    }
                }
                .disabled(!settings.glowEnabled)
                HStack {
                    Text("Glow strength")
                    Slider(value: $settings.glowStrength, in: 0.5...2.5) {
                        Text("Glow strength")
                    } minimumValueLabel: {
                        Text("Subtle").font(.caption)
                    } maximumValueLabel: {
                        Text("Bold").font(.caption)
                    }
                    .labelsHidden()
                }
                .disabled(!settings.glowEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LabeledSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
            Text(verbatim: "\(Int(value)) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

// MARK: - Privacy & shortcuts

private struct PrivacyTab: View {
    @ObservedObject var settings: PrompterSettings

    var body: some View {
        Form {
            Section("Screen recording & sharing") {
                Toggle("Hide prompter from screenshots, screen sharing and recordings", isOn: $settings.hideFromCapture)
                Text("""
                Works with Zoom, Google Meet, Microsoft Teams, QuickTime and macOS screenshots. \
                On macOS 15.4 and later, some recorders (including Loom in full-screen mode) can still see it, \
                because Apple no longer lets apps block those. In Loom, record "Camera only" or pick a single window \
                instead of the full screen and the prompter stays out of your video.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Pro: phone remote
            if let remoteSection = Edition.pro?.view(for: .privacySection) { remoteSection }

            Section("Keyboard shortcuts (work in any app)") {
                Toggle("Enable global shortcuts", isOn: $settings.globalShortcuts)
                if settings.globalShortcuts {
                    ForEach(ShortcutAction.available) { action in
                        ShortcutRecorderRow(action: action, settings: settings)
                    }
                    HStack {
                        Text("Click a shortcut, then press the new keys. Delete turns it off, Esc cancels.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset All") { settings.resetAllShortcuts() }
                            .disabled(settings.shortcuts.isEmpty)
                    }
                }
            }

            Section("Siri & Shortcuts") {
                Text("Say \u{201C}Hey Siri, start PeekPrompt\u{201D}, \u{201C}Pause PeekPrompt\u{201D} or \u{201C}Next slide in PeekPrompt\u{201D}. The same actions are in the Shortcuts app, so you can add them to your own automations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Voice levels are measured on your Mac. Word Tracking and Dictation use Apple's speech recognition, which runs on your Mac when supported and otherwise on Apple's servers. PeekPrompt never saves or uploads recordings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
