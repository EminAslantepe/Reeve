import SwiftUI

/// Panel başlıkları (UI.md §1). Hangi panelde ne olduğunu, ne kadara geldiğini
/// ve hangisinin klavyeyi aldığını söylüyor; sağındaki ✕ paneli kapatıyor.
struct PaneHeaderBar: View {
    let store: SessionStore

    var body: some View {
        HStack(spacing: Theme.hairline) {
            ForEach(0..<store.paneCount, id: \.self) { index in
                header(index)
            }
        }
        .frame(height: 50)
        .background(Theme.rule)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.ruleSoft).frame(height: Theme.hairline)
        }
    }

    private func header(_ index: Int) -> some View {
        let session = store.session(store.panes[index])
        let focused = store.activePane == index
        return HStack(spacing: 10) {
            if let session {
                StatusDot(status: session.status, origin: session.origin)
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(focused ? Theme.ink : Theme.ink2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(session.name)
                        .padding(.leading, 7)
                    DirectoryMenu(session: session, store: store)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 6)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(trailing(session))
                }
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(session.status.isWaiting ? Theme.wait : Theme.ink3)
                    .lineLimit(1)
                    .fixedSize()
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
        .padding(.leading, 14)
        .padding(.trailing, store.paneCount > 1 ? 8 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(focused ? Theme.control : Theme.sidebar)
        .overlay(alignment: .bottom) {
            if focused && store.paneCount > 1 {
                Rectangle().fill(Theme.focusRule).frame(height: Theme.hairline)
            }
        }
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
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(hovering ? Theme.ink : Theme.ink3)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? Theme.choiceOn : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Paneli kapat")
    }
}
