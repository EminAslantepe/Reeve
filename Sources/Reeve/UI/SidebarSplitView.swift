import AppKit

/// Native ayırıcı takibini korur; fare bırakılınca arada kalan genişliği toparlar.
final class SidebarSplitView: NSSplitView {
    var onSidebarResizeEnded: ((CGFloat) -> Void)?

    override var dividerColor: NSColor { NSColor(Theme.rule) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let edge = subviews.first?.frame.maxX ?? 0
        let resizingSidebar = isVertical && abs(point.x - edge) <= 6
        super.mouseDown(with: event)
        if resizingSidebar, let sidebar = subviews.first {
            onSidebarResizeEnded?(sidebar.frame.width)
        }
    }
}
