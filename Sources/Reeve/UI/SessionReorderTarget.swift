import SwiftUI
import UniformTypeIdentifiers

struct SessionReorderTarget: ViewModifier {
    let session: Session
    let store: SessionStore
    let drag: DragState
    @State private var height: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { height = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, value in height = value }
                }
            }
            .onDrop(of: [UTType.text], delegate: SessionReorderDelegate(
                session: session, drag: drag, height: height))
    }
}

/// Yer değiştirme hover sırasında tamamlanır; bırakırken ikinci kez taşıma yok.
struct SessionReorderDelegate: DropDelegate {
    let session: Session
    let drag: DragState
    let height: CGFloat

    static func placement(at y: CGFloat, height: CGFloat) -> SessionStore.RowPlacement {
        y < height / 2 ? .before : .after
    }

    func validateDrop(info: DropInfo) -> Bool {
        drag.canDrop(on: session) && info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard drag.canDrop(on: session) else { return DropProposal(operation: .forbidden) }
        update(info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard drag.canDrop(on: session) else { return false }
        update(info)
        drag.acceptSidebarDrop()
        return true
    }

    private func update(_ info: DropInfo) {
        drag.preview(over: session, y: info.location.y, height: height)
    }
}
