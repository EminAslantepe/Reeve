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
                DirectoryMenu(session: session, store: store)
                Spacer(minLength: 6)
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
        .overlay(alignment: .bottom) {
            if focused { Rectangle().fill(Theme.primary.opacity(0.65)).frame(height: 2) }
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

/// Panelin sol üstündeki dizin göstergesi ve gezgini.
///
/// Gösterdiği şey kabuğun **gerçek** çalışma dizini (çekirdekten okunuyor),
/// açılış dizini değil. Menüden bir klasör seçilince terminale `cd` yazılıyor —
/// kabuğun dizinini dışarıdan değiştirmenin başka yolu yok.
///
/// Claude çalışırken menü sönük ve tıklanamıyor: PTY'yi Claude okuyor, yani
/// yazdığımız `cd` kabuğa değil onun girdi kutusuna düşerdi. Yol gösterilmeye
/// devam ediyor — kabuğun dizini değişmiyor, sadece oraya yazı gönderemiyoruz.
private struct DirectoryMenu: View {
    let session: Session
    let store: SessionStore

    var body: some View {
        Menu {
            let current = session.currentCwd
            let parent = (current as NSString).deletingLastPathComponent
            if !parent.isEmpty, parent != current {
                Button("↑ Üst dizin — \(Session.tilde(parent))") {
                    store.changeDirectory(session, to: parent)
                }
                Divider()
            }
            let folders = subdirectories(of: current)
            if folders.isEmpty {
                Text("alt klasör yok")
            } else {
                ForEach(folders, id: \.self) { name in
                    Button(name) {
                        store.changeDirectory(session, to: (current as NSString)
                            .appendingPathComponent(name))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                Text(Session.tilde(session.currentCwd))
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .foregroundStyle(Theme.ink3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(session.claudeIsLive)
        .opacity(session.claudeIsLive ? 0.45 : 1)
        .help(session.claudeIsLive
              ? "Claude çalışırken dizin değiştirilemiyor — \(session.currentCwd)"
              : session.currentCwd)
    }

    /// Menü açıldığında okunuyor. Gizli klasörler dışarıda: `cd` menüsünde
    /// `.git` ve `.build` gürültüden başka bir şey değil.
    private func subdirectories(of path: String) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var found: [String] = []
        for name in names where !name.hasPrefix(".") {
            var isDir: ObjCBool = false
            let full = (path as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                found.append(name)
            }
        }
        return found.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(200).map { $0 }
    }
}
