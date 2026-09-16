import AppKit
import SwiftUI

/// Sol panel, üç kademede (UI.md §1.1).
/// Durum rengi her kademede taşınıyor; izin bekleyen oturum en ince halde bile görünür.
struct SidebarView: View {
    let store: SessionStore
    let drag: DragState
    let tier: SidebarTier
    let onNew: () -> Void
    let onAttach: (Session) -> Void
    let onStop: (Session) -> Void

    @State private var query = ""

    var body: some View {
        Group {
            switch tier {
            case .wide:   wide
            case .narrow: narrow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebar)
    }

    // MARK: - Geniş (268 px)

    private var wide: some View {
        VStack(spacing: 0) {
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !waiting.isEmpty {
                        SectionLabel(title: "Dikkat", count: waiting.count, git: nil, alarm: true)
                        ForEach(waiting) { row($0) }
                    }
                    ForEach(visibleGroups, id: \.cwd) { group in
                        SectionLabel(title: group.title, count: nil, git: group.git, alarm: false)
                        ForEach(group.sessions) { row($0) }
                    }
                    if store.sessions.isEmpty { empty }
                    else if visibleGroups.isEmpty && waiting.isEmpty { noMatch }
                }
                .animation(.easeOut(duration: 0.18), value: store.sessions.map(\.id))
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Dar (58 px) ve kapalı (30 px)

    private var narrow: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    switch chip {
                    case .rule:
                        Rectangle().fill(Theme.ruleSoft)
                            .frame(width: 30, height: 1).padding(.vertical, 4)
                    case .session(let session, let tag):
                        chipView(session, tag: tag)
                    }
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }

    private func chipView(_ session: Session, tag: String) -> some View {
        let selected = store.pane(of: session.id) != nil
        return VStack(spacing: 4) {
            StatusDot(status: session.status, origin: session.origin)
            Text(tag)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(session.status.isWaiting ? Theme.wait
                                 : selected ? Theme.ink : Theme.ink3)
        }
        .frame(width: 44)
        .padding(.vertical, 5)
        .background(chipBackground(session, selected: selected))
        .contentShape(Rectangle())
        .opacity(drag.sessionID == session.id ? 0.3 : 1)
        .overlay(alignment: .top) { insertionLine(above: session) }
        .onTapGesture { store.select(session.id) }
        .onDrag {
            drag.begin(session.id)
            return NSItemProvider(object: session.id.uuidString as NSString)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let id = UUID(uuidString: raw),
                  id != session.id else { drag.end(); return false }
            withAnimation(.easeOut(duration: 0.18)) {
                store.move(id, before: session.id)
            }
            drag.end()
            return true
        } isTargeted: { inside in
            drag.hover(before: inside ? session.id : nil)
        }
        .contextMenu { menu(session) }
        .help("\(session.name) · \(session.displayCwd)")
    }

    @ViewBuilder
    private func chipBackground(_ session: Session, selected: Bool) -> some View {
        if session.status.isWaiting {
            RoundedRectangle(cornerRadius: 7).fill(Theme.wait.opacity(0.13))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.wait.opacity(0.3), lineWidth: 1))
        } else if selected {
            RoundedRectangle(cornerRadius: 7).fill(Theme.selection)
        }
    }

    /// Dar/kapalı kademenin düz listesi: önce bekleyenler, sonra gruplar, aralarda çizgi.
    private enum Chip {
        case session(Session, String)
        case rule
    }

    private var chips: [Chip] {
        var ordered: [[Session]] = []
        if !waiting.isEmpty { ordered.append(waiting) }
        ordered.append(contentsOf: visibleGroups.map(\.sessions))

        let flat = ordered.flatMap { $0 }
        let tags = Abbreviator.suffixes(for: flat.map(\.name))
        var index = 0
        var out: [Chip] = []
        for (position, bucket) in ordered.enumerated() {
            if position > 0 { out.append(.rule) }
            for session in bucket {
                out.append(.session(session, tags[index]))
                index += 1
            }
        }
        return out
    }

    // MARK: - Veri

    private var waiting: [Session] { store.waiting.filter(matches) }

    private var visibleGroups: [(cwd: String, title: String, git: GitState?, sessions: [Session])] {
        store.groups.compactMap { group in
            let rows = group.sessions.filter(matches)
            return rows.isEmpty ? nil : (group.cwd, group.title, group.git, rows)
        }
    }

    private func matches(_ session: Session) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return session.name.lowercased().contains(needle)
            || session.displayCwd.lowercased().contains(needle)
    }

    // MARK: - Parçalar

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.ink3)
            TextField("ara", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.searchBG)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.ruleSoft, lineWidth: 1)))
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func row(_ session: Session) -> some View {
        let shown = store.pane(of: session.id) != nil
        SessionRow(session: session, isSelected: shown, tick: store.tick)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            // Sürüklenen satır yerinde soluyor: nereden çıktığı görünür kalıyor.
            .opacity(drag.sessionID == session.id ? 0.3 : 1)
            .overlay(alignment: .top) { insertionLine(above: session) }
            .onTapGesture { store.select(session.id) }
            .contextMenu { menu(session) }
            .onDrag {
                drag.begin(session.id)
                return NSItemProvider(object: session.id.uuidString as NSString)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let id = UUID(uuidString: raw),
                      id != session.id else { drag.end(); return false }
                withAnimation(.easeOut(duration: 0.18)) {
                    store.move(id, before: session.id)
                }
                drag.end()
                return true
            } isTargeted: { inside in
                drag.hover(before: inside ? session.id : nil)
            }

        // Alt öğeler yalnızca panelde duran oturumda — her satırda göstermek
        // sidebar'ı gürültüye boğardı (UI.md §2, açık soru 5).
        if shown {
            ForEach(session.subagents) { agent in
                SubItemRow(symbol: "gearshape",
                           label: agent.name,
                           value: agent.elapsed,
                           dimmed: agent.finishedAt != nil,
                           tick: store.tick)
            }
            ForEach(session.children) { child in
                SubItemRow(symbol: "chevron.right.square",
                           label: child.name,
                           value: "pid \(child.id)",
                           dimmed: false,
                           tick: store.tick)
            }
        }
    }

    /// Satırın üstünde ince bir çizgi: bırakınca buraya girecek.
    @ViewBuilder
    private func insertionLine(above session: Session) -> some View {
        if drag.beforeRow == session.id, drag.sessionID != session.id {
            Capsule()
                // Mavi fazla bağırıyordu; nötr ve ince.
                .fill(Theme.ink2)
                .frame(height: 2)
                .padding(.horizontal, 8)
                .offset(y: -1)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Henüz oturum yok")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink2)
            Text("⌘N ile bir tane aç")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
    }

    private var noMatch: some View {
        Text("eşleşme yok")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.ink3)
            .padding(.horizontal, 13)
            .padding(.top, 10)
    }

    @ViewBuilder
    private func menu(_ session: Session) -> some View {
        Button("Odaklan") { store.select(session.id) }
        Button("İkinci panelde aç") { store.sendToSecondPane(session.id) }
        Divider()
        if session.hasTerminal {
            Button("Kapat (SIGHUP)") { store.close(session) }
            Button("Kill (SIGKILL)") { store.kill(session) }
        } else {
            if session.origin == .backgroundAgent {
                Button("Terminalde aç") { onAttach(session) }
                Button("Durdur (claude stop)") { onStop(session) }
            }
            Button("Listeden çıkar") { store.remove(session) }
        }
        Divider()
        Button("Finder'da göster") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
        }
        Button("cwd'yi kopyala") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.cwd, forType: .string)
        }
        if let pid = session.pid {
            Divider()
            Text("pid \(pid)")
        }
    }
}

/// Seçili oturumun altındaki girintili satır: alt-ajan ya da arka plan süreci.
private struct SubItemRow: View {
    let symbol: String
    let label: String
    let value: String
    let dimmed: Bool
    let tick: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(Theme.ink3)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.ink3)
                .fixedSize()
        }
        .padding(.leading, 28)
        .padding(.trailing, 13)
        .padding(.vertical, 3)
        .opacity(dimmed ? 0.5 : 1)
    }
}

/// Bölüm başlığı: `ETİKET ──────── main ●3 ↑2`
private struct SectionLabel: View {
    let title: String
    let count: Int?
    let git: GitState?
    let alarm: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.75)
                .foregroundStyle(alarm ? Theme.wait : Theme.ink3)
                .lineLimit(1)
            if let count {
                Text("(\(count))")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(alarm ? Theme.wait : Theme.ink3)
            }
            Rectangle().fill(Theme.ruleSoft).frame(height: 1)
            if let git { GitBadge(state: git) }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 5)
    }
}

/// `main ●3 ↑2` — branch · commit'lenmemiş dosya · push edilmemiş commit.
private struct GitBadge: View {
    let state: GitState

    var body: some View {
        HStack(spacing: 5) {
            Text(state.branch)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
            if state.dirty > 0 {
                Text("●\(state.dirty)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.wait)
            }
            if state.ahead > 0 {
                Text("↑\(state.ahead)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .fixedSize()
    }
}
