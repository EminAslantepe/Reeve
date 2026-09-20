import AppKit
import SwiftUI
import XCTest
@testable import Reeve

final class SidebarResizeTests: XCTestCase {
    func testCompactControlsDoNotCoverTheDragBody() async {
        await MainActor.run {
            _ = NSApplication.shared
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            let source = SessionDragView(frame: NSRect(x: 10, y: 10, width: 48.4, height: 54))
            container.addSubview(source)
            source.actionArea = CGSize(width: 48.4, height: 24)
            source.actionEdge = .bottom

            for x: CGFloat in [4, 24.2, 44.4] {
                for y: CGFloat in [4, 16, 28] {
                    let point = source.convert(NSPoint(x: x, y: y), to: container)
                    XCTAssertTrue(source.hitTest(point) === source,
                                  "Kartın gövdesi hover sırasında da sürüklenebilmeli")
                }
                let control = source.convert(NSPoint(x: x, y: 42), to: container)
                XCTAssertNil(source.hitTest(control), "Alt kontroller tıklamayı alabilmeli")
            }
            source.actionArea = .zero
            let bottom = source.convert(NSPoint(x: 24.2, y: 42), to: container)
            XCTAssertTrue(source.hitTest(bottom) === source,
                          "Kontroller gizliyken bütün kart sürüklenebilmeli")
        }
    }

    func testNativeDividerCanShrinkToRailAndExpandAgain() async {
        await MainActor.run {
            _ = NSApplication.shared
            let store = SessionStore()
            let sidebar = NSHostingController(rootView: SidebarView(
                store: store, drag: DragState(), onNew: {},
                onAttach: { _ in }, onResume: { _ in }, onStop: { _ in }))
            let item = NSSplitViewItem(viewController: sidebar)
            item.minimumThickness = SidebarTier.narrow.width
            item.maximumThickness = SidebarTier.maximumWidth
            item.canCollapse = false
            let content = NSViewController()
            content.view = NSView()
            let split = NSSplitViewController()
            split.splitView = SidebarSplitView()
            split.splitView.isVertical = true
            split.addSplitViewItem(item)
            split.addSplitViewItem(NSSplitViewItem(viewController: content))
            let window = NSWindow(contentViewController: split)
            window.setContentSize(NSSize(width: 900, height: 500))
            window.contentView?.layoutSubtreeIfNeeded()

            for width: CGFloat in [236, 64, 220, 280, 64, 236] {
                split.splitView.setPosition(width, ofDividerAt: 0)
                window.contentView?.layoutSubtreeIfNeeded()
                XCTAssertEqual(sidebar.view.frame.width, width, accuracy: 1)
                XCTAssertEqual(SidebarTier.fitting(width: sidebar.view.frame.width),
                               width == 64 ? .narrow : .wide)
            }
            window.orderOut(nil)
        }
    }

    func testPartialDragSettlesAtUsableWidth() {
        XCTAssertEqual(SidebarTier.settledWidth(120), 64)
        XCTAssertEqual(SidebarTier.settledWidth(180), 208)
        XCTAssertEqual(SidebarTier.settledWidth(250), 250)
        XCTAssertEqual(SidebarTier.settledWidth(350), 280)
    }
}
