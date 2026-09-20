import SwiftUI

/// Kabuğun canlı çalışma dizini; seçim terminale `cd` gönderir.
struct DirectoryMenu: View {
    let session: Session
    let store: SessionStore
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                Text(Session.tilde(session.currentCwd))
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                if !session.claudeIsLive {
                    Image(systemName: isPresented ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .medium))
                }
            }
            .padding(.horizontal, 7)
            .frame(minWidth: 100, minHeight: 24, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DirectoryButtonStyle(isPresented: isPresented))
        .disabled(session.claudeIsLive)
        // Açılır paneli esneyen başlık satırına değil, düğmenin kendisine bağla.
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            DirectoryPicker(path: session.currentCwd, onSelect: { path in
                // Panel açıkken Claude başlamış olabilir; girdisini değiştirme.
                guard !session.claudeIsLive else { isPresented = false; return }
                store.changeDirectory(session, to: path)
                isPresented = false
            }, onClose: { isPresented = false })
            .presentationBackground(Theme.paletteBG)
            .preferredColorScheme(.dark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: session.claudeIsLive) { _, live in
            if live { isPresented = false }
        }
        .onChange(of: session.id) { _, _ in isPresented = false }
        .accessibilityLabel("Çalışma dizini: \(session.currentCwd)")
        .help(session.claudeIsLive
              ? "Claude çalışırken dizin değiştirilemiyor — \(session.currentCwd)"
              : "Dizin değiştir — \(session.currentCwd)")
    }
}

private struct DirectoryButtonStyle: ButtonStyle {
    let isPresented: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = isEnabled && (hovering || isPresented)
        configuration.label
            .foregroundStyle(highlighted ? Theme.ink : Theme.ink3)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isEnabled && configuration.isPressed ? Theme.button
                          : highlighted ? Theme.selection : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(highlighted ? Theme.rule : .clear,
                                  lineWidth: Theme.hairline)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

struct DirectoryPicker: View {
    let path: String
    let onSelect: (String) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var folders: [String] = []
    @State private var readFailed = false
    @State private var cursor = 0
    @FocusState private var searchFocused: Bool

    private var parent: String? {
        let value = (path as NSString).deletingLastPathComponent
        return value.isEmpty || value == path ? nil : value
    }

    private var matches: [String] {
        folders.filter { query.isEmpty || $0.localizedStandardContains(query) }
    }

    private var destinations: [String] {
        (parent.map { [$0] } ?? []) + matches.map {
            (path as NSString).appendingPathComponent($0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Dizin değiştir")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(Session.tilde(path))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
            }
            .padding(14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.ink3)
                TextField("Alt klasör ara…", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.ink)
                    .focused($searchFocused)
                    .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape], action: handle)
            }
            .font(.system(size: 11.5))
            .padding(9)
            .background(Theme.searchBG, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.rule, lineWidth: Theme.hairline))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            if let parent {
                row(title: "Üst dizin", detail: Session.tilde(parent),
                    symbol: "arrow.turn.up.left", destination: parent, index: 0)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 7)
            }
            Rectangle().fill(Theme.ruleSoft).frame(height: Theme.hairline)
            HStack {
                Text("ALT KLASÖRLER").kerning(0.8)
                Spacer()
                Text("\(matches.count)").monospacedDigit()
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.ink3)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if matches.isEmpty {
                Text(readFailed ? "Bu dizin okunamadı" : query.isEmpty
                     ? "Bu dizinde alt klasör yok" : "Eşleşen klasör yok")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 18)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(matches.enumerated()), id: \.element) { offset, name in
                                let index = offset + (parent == nil ? 0 : 1)
                                row(title: name, symbol: "folder",
                                    destination: (path as NSString).appendingPathComponent(name),
                                    index: index)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(height: min(250, CGFloat(matches.count) * 34 - 2))
                    .onChange(of: cursor) { _, index in proxy.scrollTo(index) }
                }
                .padding(.bottom, 8)
            }
            HStack(spacing: 14) {
                Text("↑↓ gezin")
                Text("↵ seç")
                Spacer()
                Text("esc kapat")
            }
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(Theme.ink3)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.paletteFoot)
        }
        .frame(width: 256)
        .background(Theme.paletteBG)
        .onAppear { reload(); searchFocused = true }
        .onChange(of: path) { _, _ in query = ""; reload() }
        .onChange(of: query) { _, _ in cursor = parent == nil || matches.isEmpty ? 0 : 1 }
    }

    private func row(title: String, detail: String? = nil, symbol: String,
                     destination: String, index: Int) -> some View {
        Button { onSelect(destination) } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if cursor == index {
                    Image(systemName: "return")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(cursor == index ? Theme.paletteRowOn : .clear,
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { cursor = index } }
        .help(destination)
        .accessibilityLabel(detail.map { "\(title): \($0)" } ?? title)
    }

    private func reload() {
        cursor = 0
        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: path)
            folders = names.filter { name in
                guard !name.hasPrefix(".") else { return false }
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(
                    atPath: (path as NSString).appendingPathComponent(name),
                    isDirectory: &isDirectory) && isDirectory.boolValue
            }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            readFailed = false
        } catch {
            folders = []
            readFailed = true
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .escape: onClose()
        case .upArrow: cursor = max(0, cursor - 1)
        case .downArrow: cursor = min(max(0, destinations.count - 1), cursor + 1)
        case .return:
            if destinations.indices.contains(cursor) { onSelect(destinations[cursor]) }
        default: return .ignored
        }
        return .handled
    }
}
