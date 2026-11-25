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

    @State private var newFolderName = ""
    @State private var isNamingFolder = false
    @State private var folderBeingRenamed: String?
    @State private var renameText = ""
    @State private var isPolishing = false

    var body: some View {
        HStack(spacing: 12) {
            // Library
            VStack(spacing: 0) {
                List(selection: Binding<UUID?>(
                    get: { settings.currentScriptID },
                    set: { if let id = $0 { settings.selectScript(id) } }
                )) {
                    ForEach(settings.folderNames, id: \.self) { folder in
                        Section {
                            scriptRows(inFolder: folder)
                        } header: {
                            Label(folder, systemImage: "folder")
                                .contextMenu {
                                    Button("Rename Folder…") {
                                        renameText = folder
                                        folderBeingRenamed = folder
                                    }
                                    Button("New Script in Folder") { settings.addScript(folder: folder) }
                                    Divider()
                                    Button("Delete Folder (keeps scripts)", role: .destructive) {
                                        settings.deleteFolder(folder)
                                    }
                                }
                        }
                    }

                    Section(settings.folderNames.isEmpty ? "" : String(localized: "Other Scripts")) {
                        scriptRows(inFolder: nil)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                HStack(spacing: 2) {
                    Menu {
                        Button("New Script") { settings.addScript() }
                        Button("New Folder…") {
                            newFolderName = ""
                            isNamingFolder = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("New script or folder")

                    Button { settings.deleteScript(settings.currentScriptID) } label: { Image(systemName: "minus") }
                        .help("Delete script")
                        .disabled(settings.scripts.count < 2)
                    Spacer()
                    Button {
                        for file in ScriptImporter.chooseFiles() {
                            settings.addScript(title: file.title, body: file.text)
                        }
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .help("Import .txt, .md, .rtf, .docx, .pdf, or PowerPoint speaker notes (.pptx)")
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 190)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            .alert("New Folder", isPresented: $isNamingFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") { settings.createFolder(named: newFolderName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Folder", isPresented: Binding(
                get: { folderBeingRenamed != nil },
                set: { if !$0 { folderBeingRenamed = nil } }
            )) {
                TextField("Folder name", text: $renameText)
                Button("Rename") {
                    if let old = folderBeingRenamed { settings.renameFolder(old, to: renameText) }
                }
                Button("Cancel", role: .cancel) {}
            }

            // Editor
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: Binding(
                    get: { settings.currentTitle },
                    set: { settings.renameScript(settings.currentScriptID, to: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))

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

                HStack {
                    Button {
                        dictation.toggle()
                    } label: {
                        Label(dictation.isDictating ? String(localized: "Stop Dictating") : String(localized: "Dictate"),
                              systemImage: dictation.isDictating ? "stop.circle.fill" : "mic")
                    }
                    .tint(dictation.isDictating ? .red : nil)
                    .help("Speak and your words are added to the end of the script")
                    Button {
                        isPolishing = true
                    } label: {
                        Label("Magic Polish", systemImage: "wand.and.stars")
                    }
                    .help("Rewrite this script so it's easier to say out loud")
                    Text("\(settings.wordCount) words · about \(readingTime) to read")
                    Spacer()
                    Text("[cues] in brackets are dimmed")
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
        .sheet(isPresented: $isPolishing) {
            MagicPolishSheet(settings: settings)
        }
    }

    /// Scripts in one folder (or unfiled), draggable to reorder.
    @ViewBuilder
    private func scriptRows(inFolder folder: String?) -> some View {
        ForEach(settings.scripts(inFolder: folder)) { script in
            Text(script.title.isEmpty ? String(localized: "Untitled") : script.title)
                .lineLimit(1)
                .tag(script.id)
                .contextMenu {
                    Button("Duplicate") { settings.duplicateScript(script.id) }
                    Menu("Move to Folder") {
                        Button("None") { settings.setFolder(nil, for: script.id) }
                        if !settings.folderNames.isEmpty { Divider() }
                        ForEach(settings.folderNames, id: \.self) { name in
                            Button(name) { settings.setFolder(name, for: script.id) }
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { settings.deleteScript(script.id) }
                        .disabled(settings.scripts.count < 2)
                }
        }
        .onMove { source, destination in
            settings.moveScripts(inFolder: folder, from: source, to: destination)
        }
    }

    /// Average speaking pace is roughly 150 words per minute.
    private var readingTime: String {
        let seconds = Int((Double(settings.wordCount) / 150.0 * 60).rounded())
        return seconds < 60
            ? String(localized: "\(seconds) sec")
            : String(localized: "\(seconds / 60) min \(seconds % 60) sec")
    }
}

// MARK: - Scrolling

private struct ScrollingTab: View {
    @ObservedObject var settings: PrompterSettings
    @ObservedObject var mic: MicrophoneMonitor
    @ObservedObject var tracker: SpeechTracker = .shared

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(ScrollMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.mode == .wordTracking, let error = tracker.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Presenting & practice") {
                Toggle("Presentation mode: one slide at a time", isOn: $settings.presentationMode)
                Text("Slides are separated by a [Slide 1] line, added automatically when you import a PowerPoint, or by a line with just ---. Use ⌃⌥→ and ⌃⌥← (or the hover and phone buttons) to change slides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Memorize mode: practice in small chunks", isOn: $settings.memorizeMode)
                if settings.memorizeMode {
                    Picker("Hide", selection: $settings.memorizeLevel) {
                        ForEach(MemorizeLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    Text("Shows a paragraph at a time and hides words so you practice recalling them. Raise the level as you learn it. In Word Tracking mode, hidden words appear as you say them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Speed") {
                Slider(value: $settings.speed, in: 5...150) {
                    Text("Scroll speed")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
                Toggle("Auto speed: match how fast I talk (Voice-Activated mode)", isOn: $settings.autoSpeed)
                if settings.autoSpeed {
                    Text(autoSpeedCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Pause while the pointer is over the prompter", isOn: $settings.pauseOnHover)
                Picker("Target length (pacing timer)", selection: $settings.targetMinutes) {
                    Text("No target").tag(0.0)
                    ForEach([0.5, 1, 2, 3, 5, 10, 15, 20, 30], id: \.self) { minutes in
                        Text(minutes < 1 ? "30 seconds" : "\(Int(minutes)) min").tag(minutes)
                    }
                }
                Picker("At the end of a script", selection: $settings.endAction) {
                    ForEach(EndAction.allCases) { action in
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

    private var autoSpeedCaption: String {
        if let wpm = tracker.wordsPerMinute {
            return String(localized: "You're speaking at about \(Int(wpm)) words per minute. The slider is used until PeekPrompt has heard a few seconds of you.")
        }
        return String(localized: "Start reading in Voice-Activated mode. After a few seconds, PeekPrompt measures your pace and takes over from the speed slider.")
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

    var body: some View {
        Form {
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
    @ObservedObject var remote: RemoteServer = .shared

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

            Section("Phone remote") {
                Toggle("Control PeekPrompt from your phone", isOn: Binding(
                    get: { remote.isRunning },
                    set: { $0 ? remote.start() : remote.stop() }
                ))

                if remote.isRunning, let url = remote.address {
                    HStack(alignment: .top, spacing: 14) {
                        if let qr = RemoteServer.qrCode(for: url) {
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 120, height: 120)
                                .padding(6)
                                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Scan with your phone's camera. Your phone must be on the same Wi-Fi as this Mac.")
                                .font(.caption)
                            Text(url.absoluteString)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Button("Copy Link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            }
                            Text("The link contains a secret code and changes each time you turn the remote on.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let error = remote.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else {
                    Text("Turn this on to get a QR code. macOS may ask to let PeekPrompt find devices on your local network. Allow it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Keyboard shortcuts (work in any app)") {
                Toggle("Enable global shortcuts", isOn: $settings.globalShortcuts)
                ShortcutRow(keys: "⇧⌘Space", action: "Start / pause (hands-free start)")
                ShortcutRow(keys: "⌃⌥P", action: "Play / pause")
                ShortcutRow(keys: "⌃⌥H", action: "Show / hide prompter")
                ShortcutRow(keys: "⌃⌥R", action: "Restart from top")
                ShortcutRow(keys: "⌃⌥M", action: "Mute / unmute microphone")
                ShortcutRow(keys: "⌃⌥↑ / ↓", action: "Faster / slower")
                ShortcutRow(keys: "⌃⌥→ / ←", action: "Next / previous slide or chunk")
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

private struct ShortcutRow: View {
    let keys: String
    let action: LocalizedStringKey

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
