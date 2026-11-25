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
                Button(settings.isPrompterVisible ? "Hide Prompter" : "Show Prompter") {
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
        .frame(width: 520, height: 500)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $settings.script)
                .font(.system(size: 13, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            HStack {
                Text("\(settings.wordCount) words · about \(readingTime) to read")
                Spacer()
                Text("Tip: [cues] in brackets are dimmed")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// Average speaking pace is roughly 150 words per minute.
    private var readingTime: String {
        let seconds = Int((Double(settings.wordCount) / 150.0 * 60).rounded())
        return seconds < 60 ? "\(seconds) sec" : "\(seconds / 60) min \(seconds % 60) sec"
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
                    ForEach(ScrollMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Speed") {
                Slider(value: $settings.speed, in: 5...150) {
                    Text("Scroll speed")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
                Toggle("Pause while the pointer is over the prompter", isOn: $settings.pauseOnHover)
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
        if mic.permissionDenied { return "PeekPrompt doesn't have microphone access." }
        if !mic.isRunning { return "Microphone is off." }
        return mic.isSpeaking
            ? "Hearing you. Text will move."
            : "Talk normally: the bar should cross the white line when you speak, but not when you're quiet."
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
                LabeledSlider(title: "Font size", value: $settings.fontSize, range: 10...36, unit: "pt")
                LabeledSlider(title: "Line spacing", value: $settings.lineSpacing, range: 0...16, unit: "pt")
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
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
            Text("\(Int(value)) \(unit)")
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

            Section("Keyboard shortcuts (work in any app)") {
                Toggle("Enable global shortcuts", isOn: $settings.globalShortcuts)
                ShortcutRow(keys: "⌃⌥P", action: "Play / pause")
                ShortcutRow(keys: "⌃⌥H", action: "Show / hide prompter")
                ShortcutRow(keys: "⌃⌥R", action: "Restart from top")
                ShortcutRow(keys: "⌃⌥M", action: "Mute / unmute microphone")
                ShortcutRow(keys: "⌃⌥↑ / ↓", action: "Faster / slower")
            }

            Section {
                Text("Audio is only measured for loudness. Nothing is recorded, transcribed or sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String

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
