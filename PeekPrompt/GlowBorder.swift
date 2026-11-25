import SwiftUI

/// A slowly rotating gradient outline that brightens and thickens with your voice.
///
/// `intensity` is 0 (silent) ... 1 (speaking loudly).
/// `strength` scales everything: 0.5 = subtle, 1 = normal, 2 = very bold.
/// When everything is quiet the rotation pauses, so it costs almost nothing.
struct GlowBorder<S: Shape>: View {
    let shape: S
    let intensity: CGFloat
    let colors: [Color]
    var strength: CGFloat = 1.4

    private var isIdle: Bool { intensity < 0.02 }

    /// Square root makes normal speech look lively instead of only loud speech.
    private var boosted: CGFloat { sqrt(min(max(intensity, 0), 1)) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isIdle)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((seconds * 70).truncatingRemainder(dividingBy: 360))
            let gradient = AngularGradient(colors: colors, center: .center, angle: angle)
            let level = boosted

            ZStack {
                // Wide, soft bloom that spills inward
                shape
                    .stroke(gradient, lineWidth: (8 + 22 * level) * strength)
                    .blur(radius: (10 + 16 * level) * strength)
                    .opacity(Double(min(1, (0.35 + 0.65 * level) * strength)))

                // Medium glow
                shape
                    .stroke(gradient, lineWidth: (3 + 7 * level) * strength)
                    .blur(radius: 3 * strength)
                    .opacity(Double(min(1, (0.5 + 0.5 * level) * strength)))

                // Crisp bright edge
                shape
                    .stroke(gradient, lineWidth: (2 + 2.5 * level) * strength)
                    .opacity(Double(min(1, 0.6 + 0.4 * level)))
            }
            .blendMode(.screen)
        }
        .animation(.easeOut(duration: 0.1), value: intensity)
        .allowsHitTesting(false)
    }
}
