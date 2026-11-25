import SwiftUI

/// A slowly rotating gradient outline that brightens and thickens with your voice.
///
/// `intensity` is 0 (silent) ... 1 (speaking loudly). When everything is quiet the
/// animation pauses, so it costs almost nothing while you're not talking.
struct GlowBorder<S: Shape>: View {
    let shape: S
    let intensity: CGFloat
    let colors: [Color]

    private var isIdle: Bool { intensity < 0.02 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isIdle)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((seconds * 60).truncatingRemainder(dividingBy: 360))
            let gradient = AngularGradient(colors: colors, center: .center, angle: angle)

            ZStack {
                // Soft outer bloom
                shape
                    .stroke(gradient, lineWidth: 3 + 8 * intensity)
                    .blur(radius: 6 + 10 * intensity)
                    .opacity(Double(0.2 + 0.8 * intensity))

                // Crisp inner line
                shape
                    .stroke(gradient, lineWidth: 1.5 + 1.5 * intensity)
                    .opacity(Double(0.25 + 0.75 * intensity))
            }
        }
        .animation(.easeOut(duration: 0.12), value: intensity)
        .allowsHitTesting(false)
    }
}
