import SwiftUI
import UniformTypeIdentifiers

/// Geniş satır ve dar çip aynı bırakma geometrisini ve geri bildirimi kullanır.
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
            .overlay(alignment: drag.rowTarget?.placement == .after ? .bottom : .top) {
                if drag.rowTarget?.id == session.id {
                    Capsule()
                        .fill(Theme.ink2.opacity(0.75))
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.text], delegate: SessionReorderDelegate(
                session: session, store: store, drag: drag, height: height))
    }
}

/// Üst yarı → önüne, alt yarı → arkasına. Son satırın altı da geçerli hedeftir.
struct SessionReorderDelegate: DropDelegate {
    let session: Session
    let store: SessionStore
    let drag: DragState
    let height: CGFloat

    static func placement(at y: CGFloat, height: CGFloat) -> SessionStore.RowPlacement {
        y < height / 2 ? .before : .after
    }

    private var canMove: Bool {
        guard let id = drag.sessionID, id != session.id,
              let source = store.session(id) else { return false }
        return source.cwd == session.cwd && source.status.isWaiting == session.status.isWaiting
    }

    func validateDrop(info: DropInfo) -> Bool {
        canMove && info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) { updateTarget(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canMove else { return DropProposal(operation: .forbidden) }
        updateTarget(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { drag.leave(row: session.id) }

    func performDrop(info: DropInfo) -> Bool {
        guard canMove, let id = drag.sessionID else { return false }
        store.move(id, relativeTo: session.id,
                   placement: Self.placement(at: info.location.y, height: height))
        drag.end()
        // Zaten aynı konumdaysa da bırakmayı kabul et; geri dönüş animasyonu yapma.
        return true
    }

    private func updateTarget(_ info: DropInfo) {
        guard canMove else { return }
        drag.hover(row: session.id,
                   placement: Self.placement(at: info.location.y, height: height))
    }
}
