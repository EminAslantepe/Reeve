import AppKit
import SwiftUI
import XCTest
@testable import Reeve

final class SidebarResizeTests: XCTestCase {
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
