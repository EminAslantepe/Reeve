import SwiftUI

/// Terminalin üstünde duran, panel hizasına bölünmüş katman.
///
/// İki işi var:
/// - PTY'si bizde olmayan oturum hangi panelde seçiliyse bilgi kartını orada gösterir.
/// - Sidebar'dan bir oturum sürüklenirken bırakma bölgelerini açar.
///
/// Sürükleme yokken bütün hücreler tıklamayı altındaki terminale geçiriyor.
struct PaneOverlay: View {
    let store: SessionStore
    let drag: DragState
    let onAttach: (Session) -> Void
    let onStop: (Session) -> Void

    var body: some View {
        if drag.isActive {
            dropZones
        } else {
            cards
        }
    }

    // MARK: - Bırakma bölgeleri

    /// Kesikli kutu çizmiyoruz: geri bildirim **panellerin kendisi**. Şeritler
    /// görünmez, tek işleri imlecin hangi araya denk geldiğini bildirmek.
    /// Boşluğu açan ve kapatan animasyon terminal tarafında (`reevePreview`).
    private var dropZones: some View {
        HStack(spacing: 0) {
            ForEach(0..<slotCount, id: \.self) { slot in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first, let id = UUID(uuidString: raw)
                        else { return false }
                        commit(id, slot: slot)
                        return true
                    } isTargeted: { inside in
                        drag.hover(insertion: inside ? slot : nil)
                    }
            }
        }
    }

    /// Tavana ulaşılmadıysa panel sayısı + 1 ara var; ulaşıldıysa hedef panel seçiliyor.
    private var slotCount: Int {
        store.paneCount < SessionStore.maxPanes ? store.paneCount + 1 : store.paneCount
    }

    private func commit(_ id: Session.ID, slot: Int) {
        if store.paneCount < SessionStore.maxPanes {
            store.insert(id, at: slot)
        } else {
            store.select(id, in: min(slot, store.paneCount - 1))
        }
        drag.end()
    }

    // MARK: - Bilgi kartları

    private var cards: some View {
        HStack(spacing: 1) {
            ForEach(0..<store.paneCount, id: \.self) { index in
                if let session = store.session(store.panes[index]), !session.hasTerminal {
                    ExternalSessionCard(session: session,
                                        tick: store.tick,
                                        compact: store.paneCount > 1,
                                        onAttach: onAttach,
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

private struct ZoneCell: View {
    let title: String
    let symbol: String
    let onDrop: (String) -> Bool

    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
            Text(title)
                .font(.system(size: 11, design: .monospaced))
        }
        .foregroundStyle(targeted ? Theme.ink : Theme.ink2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(targeted ? Theme.busy.opacity(0.18) : Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(targeted ? Theme.busy : Theme.rule,
                                  style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [5, 4])))
                .padding(6))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first else { return false }
            return onDrop(raw)
        } isTargeted: { targeted = $0 }
    }
}
