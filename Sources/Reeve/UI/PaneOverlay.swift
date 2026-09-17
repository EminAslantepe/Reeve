import SwiftUI

/// Sürükleme hedefleri terminalin boyutunu değiştirmeden üstünde görünür.
struct PaneOverlay: View {
    let store: SessionStore
    let drag: DragState
    let onAttach: (Session) -> Void
    let onResume: (Session) -> Void
    let onStop: (Session) -> Void

    var body: some View {
        if drag.isActive {
            HStack(spacing: 8) {
                ForEach(0..<slotCount, id: \.self) { slot in
                    ZoneCell(title: zoneTitle(slot),
                             symbol: store.paneCount < SessionStore.maxPanes ? "rectangle.split.2x1" : "arrow.down.to.line") { raw in
                        guard let id = UUID(uuidString: raw), store.session(id) != nil else { return false }
                        if store.paneCount < SessionStore.maxPanes {
                            store.insert(id, at: slot)
                        } else {
                            store.select(id, in: slot)
                        }
                        drag.end()
                        return true
                    }
                }
            }
            .padding(12)
        } else {
            HStack(spacing: 1) {
                ForEach(0..<store.paneCount, id: \.self) { index in
                    if let session = store.session(store.panes[index]), !session.hasTerminal {
                        ExternalSessionView(session: session,
                                            tick: store.tick,
                                            compact: store.paneCount > 1,
                                            onAttach: onAttach,
                                            onResume: onResume,
                                            onStop: onStop)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var slotCount: Int {
        store.paneCount < SessionStore.maxPanes ? store.paneCount + 1 : store.paneCount
    }

    private func zoneTitle(_ slot: Int) -> String {
        if store.paneCount == SessionStore.maxPanes { return "\(slot + 1). panelde aç" }
        if slot == 0 { return "Solda aç" }
        if slot == store.paneCount { return "Sağda aç" }
        return "Araya aç"
    }
}

private struct ZoneCell: View {
    let title: String
    let symbol: String
    let onDrop: (String) -> Bool
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light))
            Text(title).font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(targeted ? Theme.ink : Theme.ink2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(targeted ? Theme.selection.opacity(0.96) : Theme.appBG.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(targeted ? Theme.busy : Theme.rule,
                                  lineWidth: targeted ? 2 : 1)))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first else { return false }
            return onDrop(raw)
        } isTargeted: { targeted = $0 }
    }
}
