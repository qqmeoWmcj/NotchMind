import SwiftUI

/// Resolved surface specification for the single outer HUD material layer.
public struct SurfaceSpec {
    public enum Material {
        case solid(Color)
        case glass(Glass)
    }

    public let material: Material
    public let scrim: Color
    public let frostedDiffusion: Color
    public let edge: Color
    public let edgeWidth: CGFloat
    public let palette: NotchPalette
    public let needsTextShadow: Bool

    public var isGlass: Bool {
        if case .glass = material { return true }
        return false
    }

    public static func resolve(
        style: CapsuleStyle,
        preset: GlassStylePreset,
        intensity: Double,
        isExpanded: Bool,
        hasNotch: Bool,
        reduceTransparency: Bool,
        increasedContrast: Bool
    ) -> SurfaceSpec {
        let clampedI = min(max(intensity, 0.0), 1.0)

        // MacBook notch screen collapsed state is always pure black to fuse seamlessly with the hardware notch.
        if style == .pureBlack || (hasNotch && !isExpanded) {
            let basePalette: NotchPalette = increasedContrast ? .dark.withIncreasedContrast() : .dark
            let edgeOpacity: Double = isExpanded ? (increasedContrast ? 0.20 : 0.10) : 0.0
            return SurfaceSpec(
                material: .solid(.black),
                scrim: .clear,
                frostedDiffusion: .clear,
                edge: Color.white.opacity(edgeOpacity),
                edgeWidth: increasedContrast ? 1.0 : 0.5,
                palette: basePalette,
                needsTextShadow: false
            )
        }

        let isFrosted = (preset == .frosted)
        let basePalette: NotchPalette = isFrosted ? .light : .dark
        let palette = increasedContrast ? basePalette.withIncreasedContrast() : basePalette

        if reduceTransparency {
            let solidBg = isFrosted ? Color(white: 0.95) : Color(white: 0.09)
            let edgeColor = isFrosted
                ? Color.black.opacity(increasedContrast ? 0.18 : 0.10)
                : Color.white.opacity(increasedContrast ? 0.22 : 0.12)
            return SurfaceSpec(
                material: .solid(solidBg),
                scrim: .clear,
                frostedDiffusion: .clear,
                edge: edgeColor,
                edgeWidth: increasedContrast ? 1.0 : 0.5,
                palette: palette,
                needsTextShadow: false
            )
        }

        let glass: Glass
        var scrimAlpha: Double
        let scrimBase: Color
        let baseEdgeColor: Color
        let baseEdgeAlpha: Double
        let needsShadow: Bool
        var diffusionColor: Color = .clear

        let tier = GlassToneTier.from(intensity: clampedI)

        switch preset {
        case .clear:
            glass = .clear
            scrimBase = .black
            scrimAlpha = 0.24 + clampedI * 0.14
            baseEdgeColor = .white
            baseEdgeAlpha = 0.36
            needsShadow = true
            diffusionColor = .clear
        case .frosted:
            glass = .regular
            scrimBase = .white
            scrimAlpha = 0.52 + clampedI * 0.30
            baseEdgeColor = .black
            baseEdgeAlpha = 0.08
            needsShadow = false
            diffusionColor = Color.white.opacity(0.10)
        case .tintedDark:
            glass = .regular
            scrimBase = Color(white: 0.05)
            scrimAlpha = 0.64 + clampedI * 0.24
            baseEdgeColor = .white
            baseEdgeAlpha = 0.10
            needsShadow = false
            diffusionColor = Color(white: 0.20).opacity(0.10)
        case .regular:
            switch tier {
            case .clear:
                glass = .clear
                scrimBase = .black
                scrimAlpha = 0.24 + clampedI * 0.14
                baseEdgeColor = .white
                baseEdgeAlpha = 0.34
                needsShadow = true
                diffusionColor = .clear
            case .regular:
                glass = .regular
                scrimBase = .black
                scrimAlpha = 0.34 + (clampedI - 0.33) * 0.24
                baseEdgeColor = .white
                baseEdgeAlpha = 0.18
                needsShadow = false
                diffusionColor = .clear
            case .tinted:
                glass = .regular
                scrimBase = Color(white: 0.06)
                scrimAlpha = 0.64 + (clampedI - 0.67) * 0.24
                baseEdgeColor = .white
                baseEdgeAlpha = 0.10
                needsShadow = false
                diffusionColor = Color(white: 0.25).opacity(0.12)
            }
        }

        if increasedContrast {
            scrimAlpha = min(scrimAlpha + 0.15, 0.92)
        }

        let edgeAlpha = increasedContrast ? min(baseEdgeAlpha * 2.0, 0.6) : baseEdgeAlpha
        return SurfaceSpec(
            material: .glass(glass),
            scrim: scrimBase.opacity(scrimAlpha),
            frostedDiffusion: diffusionColor,
            edge: baseEdgeColor.opacity(edgeAlpha),
            edgeWidth: increasedContrast ? 1.0 : 0.5,
            palette: palette,
            needsTextShadow: needsShadow
        )
    }
}

/// The sole material surface layer for NotchMind HUD.
/// Never nest `.glassEffect()` inside this view — all internal controls use `NotchPalette` fill tokens.
public struct NotchSurface: View {
    public let shape: ConcaveNotchShape
    public let spec: SurfaceSpec
    public let notchFuseHeight: CGFloat

    public init(shape: ConcaveNotchShape, spec: SurfaceSpec, notchFuseHeight: CGFloat) {
        self.shape = shape
        self.spec = spec
        self.notchFuseHeight = notchFuseHeight
    }

    public var body: some View {
        ZStack {
            // 1. Base material (single outer glass or solid black)
            switch spec.material {
            case .solid(let color):
                shape.fill(color)
            case .glass(let glass):
                shape.fill(.clear).glassEffect(glass, in: shape)
            }

            // 1.5 Frosted diffusion wash (色调/毛玻璃 layer)
            if spec.isGlass && spec.frostedDiffusion != .clear {
                shape.fill(spec.frostedDiffusion)
            }

            // 2. Contrast scrim
            shape.fill(spec.scrim)

            // 3. Hardware notch fusion gradient (top pure black -> clear)
            if notchFuseHeight > 0 && spec.isGlass {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: notchFuseHeight + 10)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipShape(shape)
            }

            // 4. Rim highlight: transparent on top edge (DESIGN.md §1), subtle on sides & bottom
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: spec.edge.opacity(0), location: 0),
                        .init(color: spec.edge.opacity(0), location: notchFuseHeight > 0 ? 0.18 : 0.0),
                        .init(color: spec.edge, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: spec.edgeWidth
            )
        }
        .allowsHitTesting(false)
    }
}
