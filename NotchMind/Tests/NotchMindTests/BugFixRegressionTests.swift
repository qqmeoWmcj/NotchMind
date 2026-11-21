import AppKit
import SwiftUI
import Testing
@testable import NotchMind

enum TestSource {
    /// Loads a UI source file from the repo so regression tests can guard against
    /// structural regressions (e.g. someone re-adding a stacked shadow layer).
    static func load(_ fileName: String) -> String {
        let candidates = [
            FileManager.default.currentDirectoryPath + "/Sources/NotchMind/UI/\(fileName)",
            FileManager.default.currentDirectoryPath + "/../NotchMind/Sources/NotchMind/UI/\(fileName)",
        ]
        for path in candidates {
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                return text
            }
        }
        return ""
    }

    static func countOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<haystack.endIndex
        }
        return count
    }
}

@Suite("Bug Fix Regression Tests (2026-11-20)")
struct BugFixRegressionTests {
    // Bug 1: expanded HUD must not stack multiple ambient shadows (gray edge veil).
    @Test("NotchHUDView carries at most one outer shadow modifier in source")
    func testSingleOuterShadow() {
        let source = TestSource.load("NotchHUDView.swift")
        let shadowCount = TestSource.countOccurrences(of: ".shadow(", in: source)
        #expect(shadowCount == 1, "HUD shell must render exactly one shadow layer, found \(shadowCount)")
    }

    // Bug 1: SurfaceSpec scrim alpha floor must reach the contrast baseline (WCAG 4.5:1
    // against a pure-white wallpaper is the DESIGN.md worst case).
    @Test("Clear-glass scrim floor stays at 0.24 after Antigravity's contrast fix")
    func testScrimFloor() {
        let spec = SurfaceSpec.resolve(
            style: .liquidGlass,
            preset: .clear,
            intensity: 0.0,
            isExpanded: true,
            hasNotch: true,
            reduceTransparency: false,
            increasedContrast: false
        )
        // Color.description renders as "24% black" for 0.24 alpha on black.
        #expect(spec.scrim.description.contains("24%"), "scrim floor should stay at 0.24, got \(spec.scrim.description)")
    }

    // Bug 2: hit-test outside the interactive HUD bounds must pass through (buttons
    // dead / whole-panel swallowing was the original defect).
    @Test("Hit-test outside interactive bounds passes through to background")
    @MainActor
    func testHitTestPassesThroughOutsideHUD() {
        let view = HUDHostingView(rootView: Text("HUD"))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 444, height: 560),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.layoutIfNeeded()
        view.interactiveBounds = CGRect(x: 10, y: 0, width: 424, height: 520)

        // In AppKit, (0,0) is bottom-left of the window (height 560).
        // Clicks at y=10 (550pt from top, outside 520pt HUD card) must pass through.
        #expect(view.hitTest(NSPoint(x: 200, y: 10)) == nil)
        // Clicks at y=540 (20pt from top, inside header buttons) must be captured.
        #expect(view.hitTest(NSPoint(x: 200, y: 540)) !== nil)
    }
}
