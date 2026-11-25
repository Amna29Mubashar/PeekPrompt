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
            settings.theme.background

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
            Button(engine.isRunning ? "Pause" : "Play") { engine.toggle() }
            Button("Restart from Top") { engine.restart() }
            Divider()
            Button(settings.placement == .notch ? "Move Anywhere (drag to place)" : "Move Back Under Notch") {
                settings.placement = settings.placement == .notch ? .floating : .notch
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
                Spacer()
                if settings.showProgress {
                    Text("\(Int(engine.progress * 100))%")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(settings.theme.text.opacity(0.5))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, notchEar + 14)
    }

    private var showsEars: Bool {
        layout.isFloating || (layout.notchWidth > 0 && CGFloat(settings.width) > layout.notchWidth + 70)
    }

    private var statusColor: Color {
        if settings.mode == .voiceActivated && mic.isMuted { return .red }
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

    /// The line you're reading sits this far down the text area.
    private let readingLine: CGFloat = 0.3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Text(ScriptFormatter.attributed(settings.script, fontSize: settings.fontSize,
                                                family: settings.fontFamily, theme: settings.theme))
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
                           family: PrompterFont = .rounded, theme: PrompterTheme = .dark) -> AttributedString {
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

    var body: some View {
        HStack(spacing: 10) {
            control("backward.end.fill", help: "Restart") { engine.restart() }

            control("minus", help: "Slower") { engine.changeSpeed(by: -5) }

            control(playSymbol, help: engine.isRunning ? "Pause" : "Play", size: 15) { engine.toggle() }

            control("plus", help: "Faster") { engine.changeSpeed(by: 5) }

            if settings.mode == .voiceActivated {
                control(mic.isMuted ? "mic.slash.fill" : "mic.fill",
                        help: mic.isMuted ? "Unmute" : "Mute",
                        tint: mic.isMuted ? .red : .white) {
                    mic.isMuted.toggle()
                }
            }

            control(settings.mode == .classic ? "waveform" : "play.circle",
                    help: settings.mode == .classic ? "Switch to Voice-Activated" : "Switch to Classic") {
                settings.mode = settings.mode == .classic ? .voiceActivated : .classic
            }

            control("gearshape.fill", help: "Settings") {
                NSApp.activate()
                openSettings()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private var playSymbol: String {
        if engine.isRunning { return "pause.fill" }
        return settings.mode == .voiceActivated ? "waveform.circle.fill" : "play.fill"
    }

    private func control(_ symbol: String, help: String, size: CGFloat = 12, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .help(help)
    }
}
