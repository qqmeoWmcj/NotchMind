import AppKit
import SwiftUI
import Testing
@testable import NotchMind

@Suite("HUD Window & Hit-Testing Tests")
struct HUDWindowControllerTests {
    @Test("HUDHostingView hit-test accepts clicks inside interactive bounds and passes through outside")
    @MainActor
    func testHitTestWithInteractiveBounds() {
        let view = HUDHostingView(rootView: Text("Interactive HUD"))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 444, height: 560),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.layoutIfNeeded()

        view.interactiveBounds = CGRect(x: 10, y: 0, width: 424, height: 520)

        // Inside interactive bounds: in AppKit unflipped coords, y=540 is 20pt from top (header buttons)
        let insidePoint = NSPoint(x: 200, y: 540)
        let hitInside = view.hitTest(insidePoint)
        #expect(hitInside === view, "Clicks inside interactive bounds (e.g. header bar) must be captured by the hosting view")

        // Outside interactive bounds horizontally (x=2 is in the 10pt transparent left margin)
        let outsideLeftPoint = NSPoint(x: 2, y: 540)
        let hitLeft = view.hitTest(outsideLeftPoint)
        #expect(hitLeft == nil, "Clicks outside horizontal bounds must pass through to background apps")

        // Outside interactive bounds vertically (y=10 is 550pt from top, in the transparent bottom area below 520pt card)
        let outsideBottomPoint = NSPoint(x: 200, y: 10)
        let hitBottom = view.hitTest(outsideBottomPoint)
        #expect(hitBottom == nil, "Clicks below HUD card must pass through to background apps")
    }

    @Test("HUDHostingView hit-test falls back to super when interactive bounds are empty")
    @MainActor
    func testHitTestFallbackWhenEmpty() {
        let view = HUDHostingView(rootView: Text("Fallback"))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.layoutIfNeeded()
        view.interactiveBounds = .zero

        let insideFrame = NSPoint(x: 50, y: 50)
        #expect(view.hitTest(insideFrame) === view)
    }
}
