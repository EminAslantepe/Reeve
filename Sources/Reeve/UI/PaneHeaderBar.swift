import SwiftUI

/// Panel başlıkları (UI.md §1). Hangi panelde ne olduğunu, ne kadara geldiğini
/// ve hangisinin klavyeyi aldığını söylüyor; sağındaki ✕ paneli kapatıyor.
struct PaneHeaderBar: View {
    let store: SessionStore

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<store.paneCount, id: \.self) { index in
                header(index)
            }
        }
        .frame(height: 36)
        .background(Theme.rule)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.ruleSoft).frame(height: 1)
        }
    }

    private func header(_ index: Int) -> some View {
        let session = store.session(store.panes[index])
        let focused = store.activePane == index && store.paneCount > 1
        return HStack(spacing: 7) {
            if let session {
                StatusDot(status: session.status, origin: session.origin)
                Text(session.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(focused ? Theme.ink : Theme.ink2)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let cost = session.costLabel {
                    Text(cost)
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink3)
                }
                Text(trailing(session))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(session.status.isWaiting ? Theme.wait : Theme.ink3)
                    .lineLimit(1)
            } else {
                Text("boş panel")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.ink3)
                Spacer(minLength: 0)
            }
            if store.paneCount > 1 {
                CloseButton { store.closePane(index) }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, store.paneCount > 1 ? 6 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(focused ? Theme.choiceOn : Theme.control)
        .contentShape(Rectangle())
        .onTapGesture { store.focusPane(index) }
    }

    private func trailing(_ session: Session) -> String {
        session.status.isWaiting ? "bekliyor" : session.elapsed
    }
}

/// Paneli kapatır, oturumu kapatmaz. Üzerine gelince belirginleşiyor —
/// sürekli parlak durması başlığı gürültüye çeviriyordu.
private struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hovering ? Theme.ink : Theme.ink3)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? Color.white.opacity(0.1) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Paneli kapat")
    }
}
