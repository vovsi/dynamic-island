import SwiftUI

/// Notch-like silhouette: concave "ears" at the top that blend into the bezel
/// and rounded corners at the bottom. Both radii are animatable.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = max(0, min(bottomRadius, (rect.width - 2 * t) / 2, rect.height - t))

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left ear.
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + t, y: rect.minY + t),
            control: CGPoint(x: rect.minX + t, y: rect.minY)
        )
        // Left wall + bottom-left corner.
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addArc(
            tangent1End: CGPoint(x: rect.minX + t, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX + t + b, y: rect.maxY),
            radius: b
        )
        // Bottom edge + bottom-right corner.
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addArc(
            tangent1End: CGPoint(x: rect.maxX - t, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
            radius: b
        )
        // Right wall + right ear.
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - t, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}
