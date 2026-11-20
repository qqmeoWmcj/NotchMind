import SwiftUI

/// Top-anchored Dynamic Island shape with outward-flaring concave ears for
/// MacBook notch screens, and a continuous rounded pill for non-notch screens.
/// Uses cubic Bézier curves (k = 0.56) for smooth continuous curvature and conforms to `InsettableShape`.
public struct ConcaveNotchShape: InsettableShape {
    public var hasNotch: Bool
    public var topEarRadius: CGFloat
    public var bottomRadius: CGFloat
    public var insetAmount: CGFloat = 0

    public init(
        hasNotch: Bool,
        topEarRadius: CGFloat,
        bottomRadius: CGFloat,
        insetAmount: CGFloat = 0
    ) {
        self.hasNotch = hasNotch
        self.topEarRadius = topEarRadius
        self.bottomRadius = bottomRadius
        self.insetAmount = insetAmount
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topEarRadius, bottomRadius) }
        set {
            topEarRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    public func inset(by amount: CGFloat) -> ConcaveNotchShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    public func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = insetRect.width
        let h = insetRect.height
        guard w > 0, h > 0 else { return Path() }

        if !hasNotch {
            let r = min(max(bottomRadius - insetAmount, 0), min(w, h) / 2)
            return Path(roundedRect: insetRect, cornerRadius: r, style: .continuous)
        }

        let ox = insetRect.minX
        let oy = insetRect.minY
        let ear = min(max(topEarRadius, 0), min(w / 4, h / 2))
        let br = min(max(bottomRadius - insetAmount, 0), min(h - ear, w / 2 - ear))
        let k: CGFloat = 0.56

        var path = Path()
        path.move(to: CGPoint(x: ox, y: oy))
        path.addLine(to: CGPoint(x: ox + w, y: oy))

        // Top-right concave ear
        path.addCurve(
            to: CGPoint(x: ox + w - ear, y: oy + ear),
            control1: CGPoint(x: ox + w - ear * k, y: oy),
            control2: CGPoint(x: ox + w - ear, y: oy + ear * (1 - k))
        )

        // Right edge
        path.addLine(to: CGPoint(x: ox + w - ear, y: oy + h - br))

        // Bottom-right continuous corner
        path.addCurve(
            to: CGPoint(x: ox + w - ear - br, y: oy + h),
            control1: CGPoint(x: ox + w - ear, y: oy + h - br * (1 - k)),
            control2: CGPoint(x: ox + w - ear - br * (1 - k), y: oy + h)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: ox + ear + br, y: oy + h))

        // Bottom-left continuous corner
        path.addCurve(
            to: CGPoint(x: ox + ear, y: oy + h - br),
            control1: CGPoint(x: ox + ear + br * (1 - k), y: oy + h),
            control2: CGPoint(x: ox + ear, y: oy + h - br * (1 - k))
        )

        // Left edge
        path.addLine(to: CGPoint(x: ox + ear, y: oy + ear))

        // Top-left concave ear
        path.addCurve(
            to: CGPoint(x: ox, y: oy),
            control1: CGPoint(x: ox + ear, y: oy + ear * (1 - k)),
            control2: CGPoint(x: ox + ear * k, y: oy)
        )

        path.closeSubpath()
        return path
    }
}
