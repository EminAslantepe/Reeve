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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var targeted = false
    @State private var appeared = false

    var body: some View {
        // Büyük, opak kartlar yerine terminali açık bırakan hafif bir yüzey.
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(targeted ? 0.045 : 0.01))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.ink2.opacity(targeted ? 0.28 : 0.08), lineWidth: 1))
            .overlay(alignment: .bottom) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(targeted ? Theme.ink : Theme.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.appBG.opacity(targeted ? 0.88 : 0.7), in: Capsule())
                    .padding(.bottom, 20)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: targeted)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: appeared)
        .onAppear { appeared = true }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first else { return false }
            return onDrop(raw)
        } isTargeted: { targeted = $0 }
    }
}
