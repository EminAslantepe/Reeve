import AppKit
import SwiftUI

/// Klasörlere göre gruplanmış, iki genişlikte kullanılabilen oturum listesi.
/// Durum rengi her kademede taşınıyor; izin bekleyen oturum en ince halde bile görünür.
struct SidebarView: View {
    let store: SessionStore
    let drag: DragState
    let onNew: () -> Void
    let onAttach: (Session) -> Void
    let onResume: (Session) -> Void
    let onStop: (Session) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredSessionID: Session.ID?
    /// Adı yerinde düzenlenen oturum. Ayrı bir sayfa yok; satırın kendisi değişiyor.
    @State private var editingSessionID: Session.ID?
    /// Kapatma onayı bekleyen oturum.
    @State private var closingSession: Session?
    @State private var query = ""
    @State private var collapsedFolders: Set<String> = []
    @State private var expandedSessions: Set<UUID> = []

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch SidebarTier.fitting(width: geometry.size.width) {
                case .wide:   wide
                case .narrow: narrow(width: geometry.size.width)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: SidebarTier.fitting(width: geometry.size.width)) { _, next in
                if next == .narrow { query = "" }
            }
        }
        .background(Theme.sidebar)
        .tint(Theme.primary)
        .alert("Oturumu kapat?",
               isPresented: Binding(get: { closingSession != nil },
                                    set: { if !$0 { closingSession = nil } }),
               presenting: closingSession) { session in
            Button("Kapat", role: .destructive) {
                if session.hasTerminal { store.close(session) } else { store.remove(session) }
                closingSession = nil
            }
            Button("Vazgeç", role: .cancel) { closingSession = nil }
        } message: { session in
            Text(Self.closeWarning(for: session))
        }
    }

    // MARK: - Geniş

    private var wide: some View {
        VStack(spacing: 0) {
            sidebarHeader
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !waiting.isEmpty {
                        SectionLabel(title: "Yanıt bekleyenler", count: waiting.count, alarm: true)
                        ForEach(waiting) { row($0) }
                    }
                    ForEach(visibleGroups, id: \.cwd) { group in
                        Button {
                            if !collapsedFolders.insert(group.cwd).inserted {
                                collapsedFolders.remove(group.cwd)
                            }
                        } label: {
                            SectionLabel(title: group.title, count: group.sessions.count,
                                         alarm: false,
                                         collapsed: collapsedFolders.contains(group.cwd) && query.isEmpty)
                        }
                        .buttonStyle(.plain)
                        .help(group.cwd)
                        .accessibilityLabel("\(group.title), \(group.sessions.count) oturum")
                        .accessibilityValue(collapsedFolders.contains(group.cwd) ? "Kapalı" : "Açık")
                        if !collapsedFolders.contains(group.cwd) || !query.isEmpty {
                            ForEach(group.sessions) { row($0) }
                        }
                    }
                    if store.sessions.isEmpty { empty }
                    else if visibleGroups.isEmpty && waiting.isEmpty { noMatch }
                }
                .animation(reorderAnimation, value: store.sessions.map(\.id))
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Dar

    private func narrow(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            newSessionButton(compact: true)
                .padding(.top, 12)
                .padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(chips) { chip in
                        switch chip {
                        case .rule:
                            Rectangle().fill(Theme.rule)
                                .frame(width: 20, height: 1).padding(.vertical, 2)
                        case .session(let session, let tag):
                            chipView(session, tag: tag, width: max(48.4, width - 15.6))
                        }
                    }
                }
                .animation(reorderAnimation, value: store.sessions.map(\.id))
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chipView(_ session: Session, tag: String, width: CGFloat) -> some View {
        let hovered = hoveredSessionID == session.id && !drag.isActive
        return SessionChip(session: session, tag: tag,
                    selected: store.pane(of: session.id) != nil,
                    focused: store.selectedID == session.id, isHovered: hovered, width: width)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .opacity(drag.sessionID == session.id ? 0 : 1)
            .animation(nil, value: drag.sessionID)
            .overlay { dragPlaceholder(for: session) }
            .overlay {
                SessionDragSource(session: session, store: store, drag: drag,
                                  actionArea: hovered ? CGSize(width: width, height: 24) : .zero,
                                  actionEdge: .bottom,
                                  onHover: { setHover($0, for: session) }) {
                    SessionChip(session: session, tag: tag, selected: true, focused: true, width: width)
                }
            }
            .overlay(alignment: .bottom) {
                rowActions(session, compact: true)
                    .opacity(hovered ? 1 : 0)
                    .allowsHitTesting(hovered)
                    .accessibilityHidden(!hovered)
            }
            .onHover { setHover($0, for: session) }
            .modifier(SessionReorderTarget(session: session, store: store, drag: drag))
            .contextMenu { menu(session) }
            .help("\(session.name) · \(session.displayCwd)")
            .accessibilityLabel(session.name)
    }

    /// Dar/kapalı kademenin düz listesi: önce bekleyenler, sonra gruplar, aralarda çizgi.
    /// Kimlik `offset` olamaz: sıra değişince SwiftUI "0. eleman hâlâ 0. eleman"
    /// sanıp taşıma animasyonu yerine içerik takası yapıyor, liste zıplıyor.
    private enum Chip: Identifiable {
        case session(Session, String)
        case rule(Int)

        var id: String {
            switch self {
            case .session(let session, _): return session.id.uuidString
            case .rule(let index): return "rule-\(index)"
            }
        }
    }

    private var chips: [Chip] {
        var ordered: [[Session]] = []
        if !waiting.isEmpty { ordered.append(waiting) }
        ordered.append(contentsOf: visibleGroups.map(\.sessions))

        let flat = ordered.flatMap { $0 }
        let tags = Abbreviator.labels(for: flat.map(\.name))
        var index = 0
        var out: [Chip] = []
        for (position, bucket) in ordered.enumerated() {
            if position > 0 { out.append(.rule(position)) }
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

    private var reorderAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.1)
    }

    private var sidebarHeader: some View {
        HStack {
            Text("Oturumlar")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("\(store.sessions.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink2)
            Spacer()
            newSessionButton(compact: false)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func newSessionButton(compact: Bool) -> some View {
        Button(action: onNew) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink2)
                .frame(width: compact ? 36 : 28, height: compact ? 36 : 28)
                .background(Theme.choiceOn, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Yeni oturum (⌘N)")
        .accessibilityLabel("Yeni oturum")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.ink3)
            TextField("Oturum ara…", text: $query)
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
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.searchBG)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.ruleSoft, lineWidth: Theme.hairline)))
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func row(_ session: Session) -> some View {
        let shown = store.pane(of: session.id) != nil
        let hovered = hoveredSessionID == session.id && !drag.isActive
        VStack(alignment: .leading, spacing: 0) {
            SessionRow(session: session, isSelected: shown,
                       isFocused: store.selectedID == session.id, isHovered: hovered,
                       isEditing: editingSessionID == session.id,
                       onCommitName: { name in
                           store.rename(session, to: name)
                           editingSessionID = nil
                       },
                       onCancelEdit: { editingSessionID = nil })
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                // Satırın ölçüsü korunur; içerik yalnızca taşınan kartta görünür.
                .opacity(drag.sessionID == session.id ? 0 : 1)
                .animation(nil, value: drag.sessionID)
                .overlay { dragPlaceholder(for: session).padding(.horizontal, 6) }
                .overlay {
                    SessionDragSource(session: session, store: store, drag: drag,
                                      actionArea: hovered ? CGSize(width: 62, height: 30) : .zero,
                                      onHover: { setHover($0, for: session) }) {
                        SessionDragPreview(session: session)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    rowActions(session, compact: false)
                        .padding(.trailing, 11)
                        .padding(.top, 5)
                        .opacity(hovered ? 1 : 0)
                        .allowsHitTesting(hovered)
                        .accessibilityHidden(!hovered)
                }
                .onHover { setHover($0, for: session) }
                .contextMenu { menu(session) }
                .modifier(SessionReorderTarget(session: session, store: store, drag: drag))

            // Alt öğeler yalnızca panelde duran oturumda — her satırda göstermek
            // sidebar'ı gürültüye boğardı (UI.md §2, açık soru 5).
            if shown && (!session.subagents.isEmpty || !session.children.isEmpty) {
                Button {
                    if !expandedSessions.insert(session.id).inserted { expandedSessions.remove(session.id) }
                } label: {
                    Label("Alt ajanlar ve süreçler (\(session.subagents.count + session.children.count))",
                          systemImage: expandedSessions.contains(session.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink2)
                        .padding(.leading, 30)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            if shown && expandedSessions.contains(session.id) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    ForEach(session.subagents) { agent in
                        SubItemRow(symbol: "gearshape",
                                   label: agent.name,
                                   value: agent.elapsed,
                                   dimmed: agent.finishedAt != nil)
                    }
                }
                ForEach(session.children) { child in
                    SubItemRow(symbol: "chevron.right.square",
                               label: child.name,
                               value: "pid \(child.id)",
                               dimmed: false)
                }
            }
        }
    }

    /// Kapatmanın ne yaptığını açıkça yazıyoruz: SIGHUP, SIGKILL değil. Çalışan
    /// bir şey varsa önce onu söylüyoruz — asıl kaybı göze aldıran o.
    static func closeWarning(for session: Session) -> String {
        var parts: [String] = []

        let running: String?
        switch session.status {
        case .busy:    running = "Claude şu an çalışıyor"
        case .waiting: running = "Bu oturum senden izin bekliyor"
        default:       running = nil
        }
        if let running {
            parts.append("\(running). Kapatırsan yarıda kesilecek.")
        } else if !session.children.isEmpty {
            let names = session.children.prefix(3).map(\.name).joined(separator: ", ")
            let extra = session.children.count > 3 ? " ve \(session.children.count - 3) tane daha" : ""
            parts.append("Bu oturumda çalışan süreç var: \(names)\(extra).")
        }

        if session.hasTerminal {
            parts.append("Terminale SIGHUP gönderilecek ve oturum listeden kalkacak.")
        } else {
            parts.append("Oturum listeden kaldırılacak.")
        }
        return parts.joined(separator: " ")
    }

    private func setHover(_ inside: Bool, for session: Session) {
        if inside { hoveredSessionID = session.id }
        else if hoveredSessionID == session.id { hoveredSessionID = nil }
    }

    private func rowActions(_ session: Session, compact: Bool) -> some View {
        SessionActionBar(session: session, compact: compact,
                         onRename: { editingSessionID = session.id },
                         onClose: { closingSession = session })
    }

    @ViewBuilder
    private func dragPlaceholder(for session: Session) -> some View {
        if drag.sessionID == session.id {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Theme.ink3.opacity(0.22),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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
        Button("Yeniden adlandır") { editingSessionID = session.id }
        Divider()
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
            } else {
                Button("Reeve'de devam et") { onResume(session) }
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

/// Klasör adı, açma/kapama oku ve oturum sayısı.
private struct SectionLabel: View {
    let title: String
    let count: Int?
    let alarm: Bool
    var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: alarm ? "exclamationmark.bubble" : (collapsed ? "chevron.right" : "chevron.down"))
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.choiceOn, in: Capsule())
                }
            }
            .foregroundStyle(alarm ? Theme.wait : Theme.ink2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
    }
}

/// Kaynak satırın şeffaflığından bağımsız, imleçle taşınan okunaklı kart.
private struct SessionDragPreview: View {
    let session: Session

    var body: some View {
        HStack(spacing: 10) {
            SessionLeadingIcon(session: session)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(session.displayCwd)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .background(Theme.paletteBG, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.busy.opacity(0.55), lineWidth: Theme.hairline))
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

/// Dar kartlar ayırıcıyla birlikte genişler; kontroller gövdenin altında kalır.
private struct SessionChip: View {
    let session: Session
    let tag: String
    let selected: Bool
    let focused: Bool
    var isHovered = false
    var width: CGFloat = 48.4

    private var nameProgress: CGFloat { min(1, max(0, (width - 64) / 40)) }

    var body: some View {
        HStack(spacing: 0) {
            Text(tag)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .minimumScaleFactor(0.7)
                .frame(width: 48.4)
            Text(session.name)
                .font(.system(size: 11.5, weight: .medium))
                .truncationMode(.tail)
                .frame(width: max(0, width - 56.4), alignment: .leading)
                .clipped()
                .opacity(nameProgress)
        }
            .lineLimit(1)
            .foregroundStyle(focused ? Theme.ink : Theme.ink2)
            .frame(width: width, height: 26, alignment: .leading)
            .padding(.top, 4)
            // Alan hover öncesinde de ayrılır; kontroller belirince liste oynamaz.
            .padding(.bottom, 24)
            .background(selected ? Theme.selection : isHovered ? Theme.choiceOn : Theme.control,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(focused ? Theme.focusRule : isHovered ? Theme.rule : Theme.ruleSoft, lineWidth: Theme.hairline))
            .overlay(alignment: .topLeading) {
                if session.claudeIsLive {
                    ClaudeMark().fill(Theme.primary)
                        .frame(width: 9, height: 9)
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                StatusDot(status: session.status, origin: session.origin)
                    .scaleEffect(0.65)
                    .frame(width: 10, height: 10)
                    .padding(3)
            }
    }
}

/// Satırın sağ üstündeki hızlı kontroller. Kapsayıcı hover olduğunda görünür;
/// her düğme de kendi hover yüzeyini değiştirerek tıklanabilir olduğunu belli eder.
private struct SessionActionBar: View {
    let session: Session
    let compact: Bool
    let onRename: () -> Void
    let onClose: () -> Void
    @State private var hoveredAction: Action?

    private enum Action: Hashable { case menu, close }

    var body: some View {
        HStack(spacing: compact ? 0 : 1) {
            Menu {
                Button("Yeniden adlandır", action: onRename)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: compact ? 10 : 11, weight: .bold))
                    .frame(width: compact ? 20 : 25, height: compact ? 20 : 25)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(hoveredAction == .menu ? Theme.ink : Theme.ink2)
            .background(hoveredAction == .menu ? Theme.selection : .clear,
                        in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .fixedSize()
            .onHover { hoveredAction = $0 ? .menu : nil }
            .help("Oturum seçenekleri")
            .accessibilityLabel("Oturum seçenekleri")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: compact ? 9 : 10, weight: .bold))
                    .foregroundStyle(hoveredAction == .close ? Theme.error : Theme.ink2)
                    .frame(width: compact ? 20 : 25, height: compact ? 20 : 25)
                    .background(hoveredAction == .close ? Theme.error.opacity(0.22) : .clear,
                                in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .onHover { hoveredAction = $0 ? .close : nil }
            .help(session.hasTerminal ? "Oturumu kapat" : "Listeden çıkar")
            .accessibilityLabel(session.hasTerminal ? "Oturumu kapat" : "Listeden çıkar")
        }
        .padding(2)
        .foregroundStyle(Theme.ink2)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Theme.ruleSoft.opacity(hoveredAction == nil ? 0.9 : 1), lineWidth: Theme.hairline))
        .fixedSize(horizontal: true, vertical: true)
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        .animation(.easeOut(duration: 0.1), value: hoveredAction)
    }
}
