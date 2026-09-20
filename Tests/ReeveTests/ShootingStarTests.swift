import AppKit
import XCTest
@testable import Reeve

final class ShootingStarTests: XCTestCase {
    func testEffectDoesNotInterceptToolbarClicks() async {
        await MainActor.run {
            let effect = ShootingStarView(frame: NSRect(x: 0, y: 0, width: 500, height: 32))
            XCTAssertNil(effect.hitTest(NSPoint(x: 250, y: 16)))
            XCTAssertTrue(effect.mouseDownCanMoveWindow)
        }
    }

    func testEffectFillsToolbarSpaceAndShrinksWithWindow() async {
        await MainActor.run {
            _ = NSApplication.shared
            let delegate = StarToolbarDelegate()
            let toolbar = NSToolbar(identifier: "StarLayoutTest")
            toolbar.delegate = delegate
            toolbar.displayMode = .iconOnly
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 400),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.titleVisibility = .hidden
            window.toolbar = toolbar
            window.toolbarStyle = .unifiedCompact
            window.orderFront(nil)
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            guard let effect = toolbar.items.compactMap({ $0.view as? ShootingStarView }).first else {
                XCTFail("Efekt araç çubuğuna eklenmeli")
                return
            }
            let wide = effect.frame.width
            XCTAssertGreaterThan(wide, 500, "Efekt mevcut esnek boşluğu doldurmalı")
            window.setContentSize(NSSize(width: 600, height: 400))
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertLessThan(effect.frame.width, wide - 200)
            XCTAssertGreaterThanOrEqual(effect.frame.height, 16)
            XCTAssertLessThanOrEqual(effect.frame.height, 32)
            XCTAssertEqual(toolbar.visibleItems?.count, 3, "Daraltma düğmeleri gizlememeli")
            window.orderOut(nil)
        }
    }
}

@MainActor
private final class StarToolbarDelegate: NSObject, NSToolbarDelegate {
    private let star = NSToolbarItem.Identifier("star")
    private let title = NSToolbarItem.Identifier("title")
    private let action = NSToolbarItem.Identifier("action")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [title, star, action]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [title, star, action]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == star { return ShootingStarView.toolbarItem(identifier: identifier) }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = NSTextField(labelWithString: identifier == title ? "Reeve" : "+20 −4")
        return item
    }
}
