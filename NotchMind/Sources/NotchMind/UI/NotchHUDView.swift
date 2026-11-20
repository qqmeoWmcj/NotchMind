import AppKit
import SwiftUI

public struct NotchHUDView: View {
    @ObservedObject public var engine: CompanionEngine
    @ObservedObject public var settings: SettingsStore
    public let metrics: ScreenNotchMetrics
    public let onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var isHovered: Bool = false
    @State private var isPinnedOpen: Bool = false
    @State private var hoverExpandTask: Task<Void, Never>?
    @State private var hoverCollapseTask: Task<Void, Never>?

    public init(
        engine: CompanionEngine,
        metrics: ScreenNotchMetrics,
        onOpenSettings: @escaping () -> Void
    ) {
        self.engine = engine
        self.settings = engine.settings
        self.metrics = metrics
        self.onOpenSettings = onOpenSettings
    }

    private var isExpanded: Bool {
        isHovered || isPinnedOpen || engine.isHUDForceExpanded || engine.undoBanner != nil
    }

    private var collapsedWidth: CGFloat {
        if metrics.hasNotch {
            return (engine.status.isActive || engine.status.isError)
                ? metrics.notchWidth + 108
                : metrics.notchWidth + 16
        }
        return (engine.status.isActive || engine.status.isError) ? 196 : 140
    }

    private var collapsedHeight: CGFloat {
        metrics.hasNotch ? metrics.notchHeight : 34
    }

    private var hudShape: ConcaveNotchShape {
        ConcaveNotchShape(
            hasNotch: metrics.hasNotch,
            topEarRadius: metrics.hasNotch ? (isExpanded ? 16 : 8) : 0,
            bottomRadius: isExpanded ? 24 : (metrics.hasNotch ? 12 : 17)
        )
    }

    private var resolvedSpec: SurfaceSpec {
        SurfaceSpec.resolve(
            style: settings.capsuleStyle,
            preset: settings.glassStylePreset,
            intensity: settings.glassTintIntensity,
            isExpanded: isExpanded,
            hasNotch: metrics.hasNotch,
            reduceTransparency: reduceTransparency,
            increasedContrast: colorSchemeContrast == .increased
        )
    }

    private var containerAlignment: Alignment {
        if metrics.hasNotch { return .top }
        switch settings.externalDisplayPlacement {
        case .topCenter, .custom:
            return .top
        case .topLeading:
            return .topLeading
        case .topTrailingSafe:
            return .topTrailing
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            hudContainer
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: containerAlignment)
        .background(Color.clear)
    }

    @ViewBuilder
    private var hudContainer: some View {
        let shape = hudShape
        let spec = resolvedSpec
        let palette = spec.palette

        ZStack(alignment: .top) {
            if isExpanded {
                NotchExpandedContentView(
                    engine: engine,
                    settings: settings,
                    metrics: metrics,
                    isPinnedOpen: $isPinnedOpen,
                    statusGlyph: AnyView(statusGlyph(palette: palette)),
                    onOpenSettings: onOpenSettings
                )
                .frame(width: 424)
                .shadow(
                    color: spec.needsTextShadow ? .black.opacity(0.35) : .clear,
                    radius: spec.needsTextShadow ? 1.5 : 0,
                    y: spec.needsTextShadow ? 0.5 : 0
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.06)),
                        removal: .opacity.animation(.easeIn(duration: 0.09))
                    )
                )
            } else {
                collapsedContent(palette: palette)
                    .frame(width: collapsedWidth, height: collapsedHeight)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.12)),
                            removal: .opacity.animation(.easeIn(duration: 0.06))
                        )
                    )
            }
        }
        .background {
            NotchSurface(
                shape: shape,
                spec: spec,
                notchFuseHeight: metrics.hasNotch ? metrics.notchHeight : 0
            )
            .animation(.easeInOut(duration: 0.24), value: settings.capsuleStyle)
            .animation(.easeInOut(duration: 0.24), value: settings.glassStylePreset)
            .animation(.easeInOut(duration: 0.24), value: settings.glassTintIntensity)
            .animation(.easeInOut(duration: 0.24), value: settings.glassToneTier)
        }
        .clipShape(shape)
        .contentShape(shape)
        .onHover { hovering in
            handleHover(hovering)
        }
        .shadow(
            color: isExpanded
                ? Color.black.opacity(0.18)
                : .clear,
            radius: 5,
            y: 2
        )
        .shadow(
            color: isExpanded
                ? Color.black.opacity(spec.isGlass ? 0.26 : 0.46)
                : .clear,
            radius: spec.isGlass ? 22 : 24,
            y: spec.isGlass ? 10 : 12
        )
        .environment(\.colorScheme, palette.scheme)
        .environment(\.notchPalette, palette)
        .animation(
            isExpanded
                ? NotchSpring.expandAnimation(reduceMotion: reduceMotion)
                : NotchSpring.collapseAnimation(reduceMotion: reduceMotion),
            value: isExpanded
        )
        .animation(reduceMotion ? .easeOut(duration: 0.15) : NotchSpring.snappy, value: engine.status)
    }

    // MARK: - Collapsed State

    @ViewBuilder
    private func collapsedContent(palette: NotchPalette) -> some View {
        if metrics.hasNotch {
            HStack(spacing: 0) {
                if engine.status.isActive || engine.status.isError {
                    statusGlyph(palette: palette)
                        .frame(width: 46, alignment: .center)
                        .transition(.blurReplace.combined(with: .scale(0.85)))
                }
                Spacer(minLength: metrics.notchWidth)
                if engine.status.isActive || engine.status.isError {
                    Text("\(engine.captureCountToday)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.primary.opacity(0.84))
                        .contentTransition(.numericText(value: Double(engine.captureCountToday)))
                        .animation(NotchSpring.snappy, value: engine.captureCountToday)
                        .frame(width: 46, alignment: .center)
                        .transition(.blurReplace.combined(with: .scale(0.85)))
                }
            }
            .padding(.horizontal, 8)
        } else {
            HStack(spacing: 8) {
                statusGlyph(palette: palette)
                Text(engine.status.shortLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(engine.captureCountToday)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
                    .contentTransition(.numericText(value: Double(engine.captureCountToday)))
                    .animation(NotchSpring.snappy, value: engine.captureCountToday)
            }
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder
    private func statusGlyph(palette: NotchPalette) -> some View {
        switch engine.status {
        case .watching:
            NotchWaveformView(isAnalyzing: false, tint: palette.primary)
        case .analyzing:
            NotchWaveformView(isAnalyzing: true, tint: palette.primary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.destructive)
                .contentTransition(.symbolEffect(.replace.downUp))
                .symbolEffect(.bounce, value: engine.status)
        case .paused, .idle:
            Image(systemName: settings.monitoringMode.symbolName)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.tertiary)
                .contentTransition(.symbolEffect(.replace.downUp))
        }
    }

    // MARK: - Hover Intent (80ms expand delay, 260ms collapse delay)

    private func handleHover(_ hovering: Bool) {
        hoverExpandTask?.cancel()
        hoverCollapseTask?.cancel()
        if hovering {
            if isHovered { return }
            hoverExpandTask = Task {
                try? await Task.sleep(for: .milliseconds(80))
                if !Task.isCancelled {
                    isHovered = true
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
        } else {
            hoverCollapseTask = Task {
                try? await Task.sleep(for: .milliseconds(260))
                if !Task.isCancelled {
                    isHovered = false
                }
            }
        }
    }
}
