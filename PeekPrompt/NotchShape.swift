import SwiftUI

/// The outline of the prompter: flat top that tucks under the notch,
/// small inward-curving "ears" at the top corners (like the real notch),
/// and rounded bottom corners.
///
///   ╲_______________________╱   <- top edge flush with the top of the screen
///    |                     |
///    |                     |
///     ╲___________________╱
struct NotchShape: Shape {
    var topCornerRadius: CGFloat = 10
    var bottomCornerRadius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let top = topCornerRadius
        let bottom = min(bottomCornerRadius, (rect.height - top) / 2, (rect.width - 2 * top) / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left ear (curves inward)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))

        // Bottom-left corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))

        // Bottom-right corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))

        // Top-right ear
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
