import Foundation
import Observation

/// Native sürükleme yaşam döngüsü ve sidebar'ın canlı sıralama önizlemesi.
@MainActor
@Observable
final class DragState {
    private(set) var sessionID: Session.ID?
    var isActive: Bool { sessionID != nil }
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private weak var store: SessionStore?
    @ObservationIgnored private var originalOrder: [Session.ID] = []
    @ObservationIgnored private var acceptedInSidebar = false

    func begin(_ id: Session.ID, store: SessionStore) {
        guard !isActive, store.session(id) != nil else { return }
        self.store = store
        originalOrder = store.sessions.map(\.id)
        acceptedInSidebar = false
        sessionID = id
        onChange?()
    }

    func canDrop(on target: Session) -> Bool {
        guard let id = sessionID, let source = store?.session(id) else { return false }
        return source.cwd == target.cwd && source.status.isWaiting == target.status.isWaiting
    }

    /// Yalnızca hareket yönündeki yarı geçildiğinde değiştir. Satır imlecin
    /// altından kayınca gelen tekrar olayları sıralamayı tersine çevirmesin.
    func preview(over target: Session, y: CGFloat, height: CGFloat) {
        guard canDrop(on: target), let id = sessionID, let store,
              let from = store.sessions.firstIndex(where: { $0.id == id }),
              let to = store.sessions.firstIndex(where: { $0.id == target.id }),
              from != to else { return }
        if from < to && y >= height / 2 {
            store.move(id, relativeTo: target.id, placement: .after)
        } else if from > to && y < height / 2 {
            store.move(id, relativeTo: target.id, placement: .before)
        }
    }

    func acceptSidebarDrop() { acceptedInSidebar = true }

    /// AppKit önizlemeyi kaldırınca çağrılır. Mouse-up zamanlayıcısı veya ikinci
    /// bir solma animasyonu yok; kaynak satır yalnızca bu noktada görünür olur.
    func end(accepted: Bool = false) {
        guard isActive else { return }
        if !accepted || !acceptedInSidebar { store?.restoreOrder(originalOrder) }
        sessionID = nil
        originalOrder = []
        acceptedInSidebar = false
        store = nil
        onChange?()
    }
}
