import SwiftUI
import AppKit

struct PrompterView: View {
    @ObservedObject var settings: PrompterSettings
    @ObservedObject var engine: ScrollEngine
    @ObservedObject var mic: MicrophoneMonitor
    @ObservedObject var layout: NotchLayout
    @Environment(\.openSettings) private var openSettings

    /// Notch outline under the notch; a plain rounded card in Anywhere mode.
    private var shape: AnyShape {
        layout.isFloating
            ? AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            : AnyShape(NotchShape(topCornerRadius: notchEar, bottomCornerRadius: 22))
    }

    /// Width of the inward-curving "ears" at the top corners (none when floating).
    private var notchEar: CGFloat { layout.isFloating ? 0 : 10 }

    var body: some View {
        ZStack(alignment: .top) {
            settings.theme.background.opacity(settings.backgroundOpacity)

            VStack(spacing: 0) {
                statusRow
                    .frame(height: layout.topInset)
                ScriptViewport(settings: settings, engine: engine)
                    .padding(.horizontal, notchEar)
            }

            if settings.glowEnabled && mic.isRunning {
                GlowBorder(shape: shape, intensity: glowIntensity, colors: settings.glowPalette.colors,
                           strength: CGFloat(settings.glowStrength))
            }

            if let count = engine.countdown {
                VStack(spacing: 0) {
                    Color.clear.frame(height: layout.topInset)
                    ZStack {
                        settings.theme.background.opacity(0.8)
                        Text("\(count)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(settings.theme.text)
                            .contentTransition(.numericText(countsDown: true))
                            .id(count)
                            .transition(.scale(scale: 1.6).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.35), value: count)
                .transition(.opacity)
            }

            if engine.isHovering {
                VStack {
                    Spacer()
                    HoverControls(settings: settings, engine: engine, mic: mic)
                        .padding(.bottom, 8)
                }
                .transition(.opacity)
            }
        }
        .frame(width: CGFloat(settings.width), height: layout.topInset + CGFloat(settings.height))
        .clipShape(shape)
        .animation(.easeInOut(duration: 0.18), value: engine.isHovering)
        .animation(.easeInOut(duration: 0.2), value: engine.countdown == nil)
        .preferredColorScheme(settings.theme.colorScheme)
        .contextMenu {
            Button(engine.isRunning ? String(localized: "Pause") : String(localized: "Play")) { engine.toggle() }
            Button("Restart from Top") { engine.restart() }
            Divider()
            Button(settings.placement == .notch ? String(localized: "Move Anywhere (drag to place)") : String(localized: "Move Back Under Notch")) {
                settings.placement = settings.placement == .notch ? .floating : .notch
            }
            if engine.isSegmented {
                Button(settings.presentationMode ? String(localized: "Next Slide") : String(localized: "Next Chunk")) { engine.nextSegment() }
                    .disabled(engine.isOnLastSegment)
                Button(settings.presentationMode ? String(localized: "Previous Slide") : String(localized: "Previous Chunk")) { engine.previousSegment() }
                    .disabled(engine.segmentIndex == 0)
            }
            if Edition.isProBuild {
                Toggle(Edition.hasPro ? String(localized: "Presentation Mode") : String(localized: "Presentation Mode") + " · Pro",
                       isOn: $settings.presentationMode)
                Toggle(Edition.hasPro ? String(localized: "Memorize Mode") : String(localized: "Memorize Mode") + " · Pro",
                       isOn: $settings.memorizeMode)
            }
            Picker("Script", selection: Binding(
                get: { settings.currentScriptID },
                set: { settings.selectScript($0) }
            )) {
                ForEach(settings.orderedScripts) { script in
                    Text(script.title).tag(script.id)
                }
            }
            if NSScreen.screens.count > 1 {
                Picker("Display", selection: $settings.displayChoice) {
                    ForEach(DisplayOption.all, id: \.choice.storageValue) { option in
                        Text(option.name).tag(option.choice)
                    }
                }
            }
            Button("Hide Prompter") { settings.isPrompterVisible = false }
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            Divider()
            Button("Quit PeekPrompt") { NSApp.terminate(nil) }
        }
    }

    /// How strongly the border should glow: 0 when quiet, 1 when clearly speaking.
    private var glowIntensity: CGFloat {
        guard !mic.isMuted else { return 0 }
        let floor = settings.speakingThreshold * 0.6
        let value = (mic.level - floor) / max(1 - floor, 0.01)
        return min(max(value, 0), 1)
    }

    /// Small indicators in the "ears" on either side of the notch,
    /// shown only when the prompter is wider than the notch.
    private var statusRow: some View {
        HStack {
            if showsEars {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                if let label = engine.segmentLabel {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(settings.theme.text.opacity(0.55))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer()
                if settings.showProgress {
                    PaceLabel(engine: engine, settings: settings)
                }
            }
        }
        .padding(.horizontal, notchEar + 14)
    }

    private var showsEars: Bool {
        layout.isFloating || layout.notchWidth == 0 || CGFloat(settings.width) > layout.notchWidth + 70
    }

    private var statusColor: Color {
        if settings.mode.usesMicrophone && mic.isMuted { return .red }
        if engine.isAdvancing { return .green }
        if engine.countdown != nil { return .orange }
        if engine.isRunning { return .yellow }
        return settings.theme.text.opacity(0.3)
    }
}

// MARK: - Script

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ScriptViewport: View {
    @ObservedObject var settings: PrompterSettings
    @ObservedObject var engine: ScrollEngine

    /// The current slide/chunk (or whole script), with Memorize mode's hidden words applied.
    private var shownText: String {
        let text = engine.displayedText
        guard settings.memorizeMode, let pro = Edition.pro else { return text }
        let reveal = settings.mode == .wordTracking ? engine.spokenUTF16Offset : 0
        return pro.memorize(text, level: settings.memorizeLevel, revealUpTo: reveal)
    }

    /// The line you're reading sits this far down the text area.
    private let readingLine: CGFloat = 0.3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Text(ScriptFormatter.attributed(shownText, fontSize: settings.fontSize,
                                                family: settings.fontFamily, theme: settings.theme,
                                                spokenUTF16Offset: settings.mode == .wordTracking ? engine.spokenUTF16Offset : 0))
                    .lineSpacing(CGFloat(settings.lineSpacing))
                    .multilineTextAlignment(.center)
                    .frame(width: max(geo.size.width - 28, 50))
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.preference(key: ContentHeightKey.self, value: textGeo.size.height)
                        }
                    )
                    .offset(y: geo.size.height * readingLine - engine.offset)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                if settings.showProgress {
                    ProgressStrip(progress: engine.progress, color: settings.theme.text)
                        .padding(.trailing, 2)
                        .padding(.vertical, 10)
                }
            }
            .clipped()
            .mask(readingMask(height: geo.size.height))
            .onPreferenceChange(ContentHeightKey.self) { height in
                engine.contentHeight = height
            }
            .onChange(of: settings.script) { _, _ in
                engine.restart()
            }
        }
    }

    /// Fades the text in at the top and out at the bottom. With the reading-line
    /// highlight on, the line you're reading is full brightness and the rest is dimmed.
    private func readingMask(height: CGFloat) -> some View {
        guard settings.highlightReadingLine, height > 0 else {
            return LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.78),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        // One line of text, as a fraction of the visible height.
        let lineHeight = CGFloat(settings.fontSize) * 1.3 + CGFloat(settings.lineSpacing)
        let band = min(lineHeight / height, 0.3)
        let top = readingLine
        let bottom = min(readingLine + band * 1.1, 0.9)
        let soft = band * 0.6
        let dim = Color.black.opacity(0.35)

        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: dim, location: max(0.05, top - soft - 0.08)),
                .init(color: dim, location: max(0.06, top - soft)),
                .init(color: .black, location: top),
                .init(color: .black, location: bottom),
                .init(color: dim, location: min(0.94, bottom + soft)),
                .init(color: dim, location: 0.9),
                .init(color: .clear, location: 1)
            ].sorted { $0.location < $1.location },
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Turns the script into styled text. Anything in [square brackets] is a cue:
/// dimmed and italic so you don't read it aloud.
enum ScriptFormatter {
    static func attributed(_ script: String, fontSize: Double,
                           family: PrompterFont = .rounded, theme: PrompterTheme = .dark,
                           spokenUTF16Offset: Int = 0) -> AttributedString {
        let text = script.isEmpty ? "Open Settings and paste your script." : script
        var result = AttributedString(text)
        result.font = family.font(size: fontSize)
        result.foregroundColor = theme.text

        guard let regex = try? NSRegularExpression(pattern: "\\[[^\\]]+\\]") else { return result }
        let nsRange = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: nsRange) {
            guard let stringRange = Range(match.range, in: text),
                  let attributedRange = Range(stringRange, in: result) else { continue }
            result[attributedRange].font = family.font(size: fontSize * 0.85, italic: true, weight: .regular)
            result[attributedRange].foregroundColor = theme.text.opacity(0.4)
        }

        // Word tracking: words you've already said fade back.
        if spokenUTF16Offset > 0, !script.isEmpty {
            let utf16 = text.utf16
            let clamped = min(spokenUTF16Offset, utf16.count)
            let end = String.Index(utf16Offset: clamped, in: text)
            if let spokenRange = Range(text.startIndex..<end, in: result) {
                result[spokenRange].foregroundColor = theme.text.opacity(0.35)
            }
        }
        return result
    }
}

struct ProgressStrip: View {
    let progress: Double
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Capsule().fill(color.opacity(0.12))
                Capsule()
                    .fill(color.opacity(0.55))
                    .frame(height: geo.size.height * progress)
            }
        }
        .frame(width: 3)
        .allowsHitTesting(false)
    }
}

// MARK: - Hover controls

struct HoverControls: View {
    @ObservedObject var settings: PrompterSettings
    @ObservedObject var engine: ScrollEngine
    @ObservedObject var mic: MicrophoneMonitor
    @Environment(\.openSettings) private var openSettings

    /// Name of the button under the pointer, shown above the bar.
    @State private var hoveredLabel: String?

    var body: some View {
        VStack(spacing: 4) {
            // Hover label: tells you what a button does before you click it.
            Text(hoveredLabel ?? " ")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.black.opacity(hoveredLabel == nil ? 0 : 0.7), in: Capsule())
                .opacity(hoveredLabel == nil ? 0 : 1)
                .animation(.easeOut(duration: 0.12), value: hoveredLabel)

            HStack(spacing: 8) {
                // Navigation
                control("backward.end.fill", label: String(localized: "Restart from Top")) { engine.restart() }
                if engine.isSegmented {
                    let kindPrevious = settings.presentationMode ? String(localized: "Previous Slide") : String(localized: "Previous Chunk")
                    let kindNext = settings.presentationMode ? String(localized: "Next Slide") : String(localized: "Next Chunk")
                    control("chevron.left", label: kindPrevious) { engine.previousSegment() }
                    control("chevron.right", label: kindNext) { engine.nextSegment() }
                }

                // Speed (not used by Word Tracking, which follows your voice)
                if settings.mode != .wordTracking {
                    divider
                    control("minus", label: String(localized: "Slower")) { engine.changeSpeed(by: -5) }
                    Text("\(Int(settings.speed))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(minWidth: 18)
                        .onHover { hoveredLabel = $0 ? String(localized: "Scroll speed") : nil }
                    control("plus", label: String(localized: "Faster")) { engine.changeSpeed(by: 5) }
                }

                divider

                // Play / pause: the same in every mode
                control(engine.isRunning ? "pause.fill" : "play.fill",
                        label: engine.isRunning
                            ? String(localized: "Pause")
                            : (settings.mode.usesMicrophone ? String(localized: "Start Listening") : String(localized: "Play")),
                        size: 15) { engine.toggle() }

                divider

                // Microphone & mode
                if settings.mode.usesMicrophone {
                    control(mic.isMuted ? "mic.slash.fill" : "mic.fill",
                            label: mic.isMuted ? String(localized: "Unmute Microphone") : String(localized: "Mute Microphone"),
                            tint: mic.isMuted ? .red : .white) {
                        mic.isMuted.toggle()
                    }
                }

                Menu {
                    Picker("Scrolling Mode", selection: $settings.mode) {
                        ForEach(Edition.availableModes) { mode in
                            Label(Edition.label(for: mode), systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: settings.mode.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.white)
                .onHover { hoveredLabel = $0 ? String(localized: "Mode: \(settings.mode.title)") : nil }

                control("gearshape.fill", label: String(localized: "Settings")) {
                    NSApp.activate()
                    openSettings()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .environment(\.colorScheme, .dark)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 14)
    }

    private func control(_ symbol: String, label: String, size: CGFloat = 12, tint: Color = .white,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering in
            if hovering { hoveredLabel = label } else if hoveredLabel == label { hoveredLabel = nil }
        }
    }
}

// MARK: - Pacing

/// "0:42 / 2:00 · +5s" in the right ear. Green = on time, orange = behind, blue = ahead.
struct PaceLabel: View {
    @ObservedObject var engine: ScrollEngine
    @ObservedObject var settings: PrompterSettings

    var body: some View {
        HStack(spacing: 4) {
            if engine.elapsed > 0 || settings.targetMinutes > 0 {
                Text(timeText)
            }
            if let delta = engine.paceDelta {
                Text(deltaText(delta))
                    .foregroundStyle(color(for: delta))
            } else if engine.elapsed == 0 {
                Text("\(Int(engine.progress * 100))%")
            }
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(settings.theme.text.opacity(0.55))
        .monospacedDigit()
        .lineLimit(1)
    }

    private var timeText: String {
        let elapsed = format(engine.elapsed)
        guard settings.targetMinutes > 0 else { return elapsed }
        return "\(elapsed) / \(format(settings.targetMinutes * 60))"
    }

    private func deltaText(_ delta: TimeInterval) -> String {
        if abs(delta) < 5 { return String(localized: "on time") }
        let seconds = Int(abs(delta).rounded())
        let amount = seconds >= 60 ? format(TimeInterval(seconds)) : "\(seconds)s"
        return delta > 0 ? String(localized: "\(amount) ahead") : String(localized: "\(amount) behind")
    }

    private func color(for delta: TimeInterval) -> Color {
        if abs(delta) < 5 { return .green }
        return delta > 0 ? .cyan : .orange
    }

    private func format(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
