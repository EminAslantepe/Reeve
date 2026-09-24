import AppKit

/// Panel açıkken seçili zemini korur; hover yalnızca üzerine eklenir.
final class PanelToolbarButton: NSButton {
    private var hovered = false
    private var hoverArea: NSTrackingArea?

    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                 options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                 owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        if selected || hovered || isHighlighted {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            NSColor(calibratedWhite: isHighlighted ? 0.24 : (selected ? 0.18 : 0.12), alpha: 1).setFill()
            shape.fill()
            if selected {
                NSColor(calibratedWhite: 0.32, alpha: 1).setStroke()
                shape.lineWidth = 0.5
                shape.stroke()
            }
        }
        super.draw(dirtyRect)
    }
}
