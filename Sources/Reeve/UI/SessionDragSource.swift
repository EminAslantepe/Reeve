import AppKit
import SwiftUI

/// SwiftUI'nin otomatik geri dönüş önizlemesi yerine tek native sürükleme resmi.
struct SessionDragSource<Preview: View>: NSViewRepresentable {
    let session: Session
    let store: SessionStore
    let drag: DragState
    var actionArea: CGSize = .zero
    var onHover: (Bool) -> Void = { _ in }
    @ViewBuilder var preview: () -> Preview

    func makeNSView(context: Context) -> SessionDragView { SessionDragView() }

    func updateNSView(_ view: SessionDragView, context: Context) {
        view.sessionID = session.id
        view.actionArea = actionArea
        view.onHover = onHover
        view.onSelect = { store.select(session.id) }
        view.onBegin = { drag.begin(session.id, store: store) }
        view.onEnd = { drag.end(accepted: $0) }
        view.makeImage = { [weak view] in
            let renderer = ImageRenderer(content: preview().environment(\.colorScheme, .dark))
            renderer.scale = view?.window?.backingScaleFactor ?? 2
            return renderer.nsImage
        }
        view.setAccessibilityLabel(session.name)
        view.setAccessibilityRole(.button)
    }
}

final class SessionDragView: NSView, NSDraggingSource {
    var sessionID = UUID()
    var actionArea: CGSize = .zero
    var onHover: ((Bool) -> Void)?
    private var hoverTracking: NSTrackingArea?
    var onSelect: (() -> Void)?
    var onBegin: (() -> Void)?
    var onEnd: ((Bool) -> Void)?
    var makeImage: (() -> NSImage?)?
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Sağ tıklama, SwiftUI satırının mevcut bağlam menüsüne gider.
        if NSApp.currentEvent?.type == .rightMouseDown { return nil }
        let local = convert(point, from: superview)
        let controls = NSRect(x: bounds.maxX - actionArea.width, y: bounds.minY,
                              width: actionArea.width, height: actionArea.height)
        if controls.contains(local) { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero,
                                 options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                 owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = convert(event.locationInWindow, from: nil)
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { onSelect?(); return }
            let point = convert(next.locationInWindow, from: nil)
            guard hypot(point.x - start.x, point.y - start.y) >= 4 else { continue }
            guard let image = makeImage?() else { return }
            let item = NSPasteboardItem()
            item.setString(sessionID.uuidString, forType: .string)
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            let frame = NSRect(x: (bounds.width - image.size.width) / 2,
                               y: (bounds.height - image.size.height) / 2,
                               width: image.size.width, height: image.size.height)
            draggingItem.setDraggingFrame(frame, contents: image)
            onBegin?()
            let session = beginDraggingSession(with: [draggingItem], event: next, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = false
            return
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        onEnd?(!operation.isEmpty)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    override func accessibilityPerformPress() -> Bool { onSelect?(); return true }
}
