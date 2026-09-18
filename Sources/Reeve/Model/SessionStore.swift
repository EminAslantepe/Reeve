import AppKit
import Foundation
import Observation

/// Tek doğruluk kaynağı. PTY'ler, `claude agents --json` ve git hepsi buraya yazar;
/// UI sadece burayı izler.
@MainActor
@Observable
final class SessionStore {

    /// `busy → idle` gibi geçişler. Anlık durumu bilmek yetmiyor, bildirim ve
    /// "bitti" rozeti geçişin kendisine bakıyor (UI.md D6).
    struct Transition {
        let session: Session
        let from: Session.Status
        let to: Session.Status
    }

    private(set) var sessions: [Session] = []
    private(set) var gitStates: [String: GitState] = [:]
    /// Katman 1'in gördüğü canlı Claude süreçlerinin pid'leri.
    @ObservationIgnored private var liveClaudePIDs: Set<pid_t> = []

    /// Hangi oturum hangi panelde. Tek `selectedID` yetmiyor: ⌥⏎ ile oturum
    /// değiştirmeden ikinci panele gönderiliyor (UI.md D11).
    /// Görünür paneller, soldan sağa. Dizinin uzunluğu panel sayısıdır.
    private(set) var panes: [Session.ID?] = [nil]
    /// Klavyenin ve seçimin gittiği panel.
    private(set) var activePane = 0

    /// Dar alanda TUI bozulmasın diye bölme asgari genişlik eşiğine bağlı (UI.md D9).
    static let maxPanes = 3

    var paneCount: Int { panes.count }
    var selectedID: Session.ID? { panes.indices.contains(activePane) ? panes[activePane] : nil }
    var visibleIDs: [Session.ID?] { panes }

    /// Geçen süreyi tazelemek için saniyede bir artıyor.
    private(set) var tick = 0

    @ObservationIgnored var onCreate: ((Session) -> Void)?
    @ObservationIgnored var onSelect: ((Session) -> Void)?
    @ObservationIgnored var onDispose: ((Session) -> Void)?
    @ObservationIgnored var onTransitions: (([Transition]) -> Void)?
    /// Panel yerleşimi değişti — köprüye hangi div'lerin nerede duracağını söyle.
    @ObservationIgnored var onLayout: (([Session.ID?]) -> Void)?

    @ObservationIgnored private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            // Timer ana çalışma döngüsünde tetikleniyor; izolasyonu derleyiciye söylüyoruz.
            MainActor.assumeIsolated { self?.tick &+= 1 }
        }
    }

    var selected: Session? { session(panes[activePane]) }

    func session(_ id: Session.ID?) -> Session? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    func pane(of id: Session.ID) -> Int? {
        panes.firstIndex(of: id)
    }

    // MARK: - Panel yerleşimi

    func setPaneCount(_ count: Int) {
        let clamped = min(max(count, 1), Self.maxPanes)
        guard clamped != paneCount else { return }
        while panes.count > clamped { panes.removeLast() }
        while panes.count < clamped {
            // Yeni panel boş açılmasın: bekleyen varsa onu, yoksa bir sonrakini koy.
            let taken = Set(panes.compactMap { $0 })
            let next = waiting.first { !taken.contains($0.id) }
                    ?? sessions.first { !taken.contains($0.id) }
            panes.append(next?.id)
        }
        if activePane >= paneCount { activePane = paneCount - 1 }
        onLayout?(visibleIDs)
        if let session = selected { onSelect?(session) }
    }

    func focusPane(_ index: Int) {
        guard index < paneCount, index != activePane else { return }
        activePane = index
        if let session = selected { onSelect?(session) }
    }

    /// DİKKAT bölümü — hangi repoda olduğuna bakmaksızın izin bekleyenler.
    var waiting: [Session] {
        sessions.filter(\.status.isWaiting)
    }

    /// cwd bazında gruplar. Bekleyenler yukarıdaki bölüme taşındığı için burada yok.
    var groups: [(cwd: String, title: String, git: GitState?, sessions: [Session])] {
        var order: [String] = []
        var buckets: [String: [Session]] = [:]
        for session in sessions where !session.status.isWaiting {
            if buckets[session.cwd] == nil { order.append(session.cwd) }
            buckets[session.cwd, default: []].append(session)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return order.map { cwd in
            (cwd: cwd,
             title: cwd == home ? "~" : (cwd as NSString).lastPathComponent,
             git: gitStates[cwd],
             // Sıralama `sessions` dizisinden geliyor: kullanıcı sidebar'da
             // sürükleyerek değiştirebiliyor.
             sessions: buckets[cwd]!)
        }
    }

    var uniqueCwds: [String] { Array(Set(sessions.map(\.cwd))) }

    // MARK: - Katman 1 uygulanıyor

    func apply(_ records: [AgentRecord]) {
        var byID: [UUID: AgentRecord] = [:]
        for record in records {
            if let uuid = record.sessionUUID { byID[uuid] = record }
        }
        // Canlı etkileşimli Claude süreçleri. Süreç adına bakmıyoruz: npm
        // kurulumunda `claude` bir node betikidir ve `proc_name` "node" der.
        liveClaudePIDs = Set(records.filter { !$0.isBackground }.compactMap(\.pid))

        var transitions: [Transition] = []
        var vanished: [Session] = []

        for session in sessions where session.kind == .claude {
            guard !session.status.isOver else { continue }   // ölmüş oturumu diriltme

            if let record = byID.removeValue(forKey: session.claudeSessionID) {
                let before = session.status
                let after = record.mappedStatus
                if before != after {
                    session.status = after
                    transitions.append(Transition(session: session, from: before, to: after))
                }
                if session.customName == nil { session.name = record.name }
                session.reportedPID = record.pid
                session.shortID = record.id
                if session.origin != .center {
                    session.origin = record.isBackground ? .backgroundAgent : .external
                }
            } else if session.origin != .center {
                vanished.append(session)          // dışarıda kapanmış
            }
        }

        for session in vanished { remove(session) }

        refreshClaudePresence()

        // Reeve'in açmadıkları sidebar'a **girmiyor**: ne başka terminalde elle
        // açılmış oturumlar ne de arka plan ajanları. Yoklamanın buradaki tek işi
        // kendi oturumlarımızın durumunu tazelemek. Geri almak için: eşleşmeyen
        // her `byID` kaydından `Session(discovered:)` üretip listeye eklemek yeter.

        if !transitions.isEmpty { onTransitions?(transitions) }
    }

    func applyGit(_ states: [String: GitState]) {
        gitStates = states
    }

    func applyUsage(_ usages: [UUID: Usage]) {
        for session in sessions {
            guard let usage = usages[session.id], session.usage != usage else { continue }
            session.usage = usage
        }
    }

    func applyTurns(_ turns: [UUID: [Turn]]) {
        for session in sessions {
            guard let steps = turns[session.id], session.turns != steps else { continue }
            session.turns = steps
        }
    }

    /// Transcript okuyucunun ihtiyacı olan üçlü.
    var transcriptTargets: [(id: UUID, sessionID: UUID, cwd: String)] {
        sessions.filter { $0.kind == .claude }
            .map { ($0.id, $0.claudeSessionID, $0.cwd) }
    }

    func applyCwds(_ cwds: [pid_t: String]) {
        for session in sessions {
            guard let pid = session.pid, let path = cwds[pid] else { continue }
            if session.liveCwd != path { session.liveCwd = path }
        }
    }

    /// Terminale `cd` yazdırıyoruz — kabuğun dizinini dışarıdan değiştirmenin
    /// başka yolu yok. Yol tek tırnak içinde: boşluk ve özel karakterler
    /// kabuk tarafından yorumlanmasın.
    func changeDirectory(_ session: Session, to path: String) {
        let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        session.pty.write(Data("cd \(quoted)\n".utf8))
    }

    func applyChildren(_ trees: [pid_t: [ChildProcess]]) {
        for session in sessions {
            guard let pid = session.pid else { continue }
            let found = trees[pid] ?? []
            if session.children != found { session.children = found }
        }
        // Süreç ağacı değişti: `claude` başlamış ya da bitmiş olabilir.
        refreshClaudePresence()
    }

    /// Simge şablona değil gerçeğe baksın: Katman 1'in bildirdiği canlı Claude
    /// pid'leriyle oturumun süreç ağacını kesiştiriyoruz. Kabukta elle açılan
    /// Claude de yakalanıyor, çıkılan Claude de düşüyor.
    private func refreshClaudePresence() {
        for session in sessions {
            var live = false
            if let pid = session.pid, liveClaudePIDs.contains(pid) { live = true }
            if !live {
                live = session.children.contains { liveClaudePIDs.contains($0.id) }
            }
            // PTY'si bizde olmayan oturumun ağacını göremiyoruz; orada şablon
            // bilgisi elimizdeki tek şey.
            if !live, session.origin != .center, session.kind == .claude { live = true }
            if session.claudeIsLive != live { session.claudeIsLive = live }
        }
    }

    // MARK: - Katman 2 uygulanıyor (hook)

    /// Hook olayları anlık geliyor; yoklamanın 1–5 saniyesini beklemiyoruz.
    func apply(_ event: HookEvent) {
        guard let session = match(event) else { return }
        let before = session.status
        let now = Date()

        switch event.event {
        case "SessionStart":
            adopt(event, into: session)
            session.activity = nil
            session.status = .idle

        case "PreToolUse":
            adopt(event, into: session)
            if let name = event.subagentName, let id = event.payload.toolUseID {
                session.subagents.append(
                    .init(id: id, name: name, startedAt: now, finishedAt: nil))
            } else if let summary = event.toolSummary {
                session.activity = .init(summary: summary,
                                         toolUseID: event.payload.toolUseID,
                                         startedAt: now)
            }
            session.status = .busy

        case "PostToolUse":
            if event.subagentName != nil, let id = event.payload.toolUseID,
               let index = session.subagents.firstIndex(where: { $0.id == id }) {
                session.subagents[index].finishedAt = now
                // Biten alt-ajanların son üçü kalsın, gerisi gürültü.
                let finished = session.subagents.filter { $0.finishedAt != nil }
                if finished.count > 3 {
                    let drop = Set(finished.prefix(finished.count - 3).map(\.id))
                    session.subagents.removeAll { drop.contains($0.id) }
                }
            } else if session.activity?.toolUseID == event.payload.toolUseID {
                session.activity = nil
            }

        case "Notification":
            session.status = .waiting(event.payload.message ?? "izin bekliyor")

        case "Stop", "SubagentStop":
            if event.event == "Stop" {
                session.activity = nil
                session.lastMessage = event.payload.lastAssistantMessage
                session.status = .idle
            }

        case "SessionEnd":
            session.activity = nil
            session.subagents.removeAll()
            session.status = .idle

        default:
            break
        }

        if session.status != before {
            onTransitions?([Transition(session: session, from: before, to: session.status)])
        }
    }

    /// Önce `session_id`, olmazsa `REEVE_PANE_ID`.
    private func match(_ event: HookEvent) -> Session? {
        if let id = event.sessionUUID,
           let found = sessions.first(where: { $0.claudeSessionID == id }) {
            return found
        }
        if let pane = event.paneUUID {
            return sessions.first { $0.paneID == pane }
        }
        return nil
    }

    /// Kullanıcı bir shell oturumunda elle `claude` yazdıysa oturum kimliğini
    /// ancak hook'tan öğreniyoruz; öğrenince Katman 1 eşleşmesi de kuruluyor.
    private func adopt(_ event: HookEvent, into session: Session) {
        guard let id = event.sessionUUID, session.claudeSessionID != id else { return }
        session.claudeSessionID = id
    }

    // MARK: - Yaşam döngüsü

    func add(_ session: Session) {
        sessions.append(session)
        onCreate?(session)
        select(session.id)
    }

    func select(_ id: Session.ID?) {
        select(id, in: activePane)
    }

    func select(_ id: Session.ID?, in pane: Int) {
        guard panes.indices.contains(pane) else { return }
        guard let id, let session = sessions.first(where: { $0.id == id }) else {
            panes[pane] = nil
            onLayout?(visibleIDs)
            return
        }
        if panes[pane] == id {
            activePane = pane
            session.hasUnseenOutput = false
            onSelect?(session)
            return
        }
        // Aynı oturum iki panelde birden durmasın — yerlerini takas et.
        if let other = panes.firstIndex(of: id), other != pane {
            panes[other] = panes[pane]
        }
        panes[pane] = id
        activePane = pane
        session.hasUnseenOutput = false
        onLayout?(visibleIDs)
        onSelect?(session)
    }

    /// ⌥⏎ — oturum değiştirmeden ikinci panele gönder.
    func sendToSecondPane(_ id: Session.ID) {
        if paneCount == 1 { setPaneCount(2) }
        let keepActive = activePane
        select(id, in: 1)
        focusPane(keepActive)
    }

    /// Sidebar'dan terminal alanına bırakılan oturum: `index` panellerin arasına
    /// açılacak boşluğun yeri. Tavana ulaşıldıysa araya sıkıştırmak yerine o
    /// panelin içeriği değişiyor.
    func insert(_ id: Session.ID, at index: Int) {
        guard session(id) != nil else { return }
        var slot = min(max(index, 0), paneCount)
        // Zaten görünür olan bir oturumu taşımak boş panel üretmemeli.
        if let existing = panes.firstIndex(of: id) {
            panes.remove(at: existing)
            if existing < slot { slot -= 1 }
            panes.insert(id, at: slot)
        } else if let empty = panes.firstIndex(of: nil) {
            panes[empty] = id
            slot = empty
        } else if paneCount >= Self.maxPanes {
            select(id, in: min(slot, paneCount - 1))
            return
        } else {
            panes.insert(id, at: slot)
        }
        activePane = slot
        onLayout?(visibleIDs)
        if let session = selected {
            session.hasUnseenOutput = false
            onSelect?(session)
        }
    }

    /// Panel başlığındaki ✕ — paneli kapatır, oturumu kapatmaz.
    func closePane(_ index: Int) {
        guard paneCount > 1, panes.indices.contains(index) else { return }
        panes.remove(at: index)
        if index < activePane { activePane -= 1 }
        if activePane >= paneCount { activePane = paneCount - 1 }
        onLayout?(visibleIDs)
        if let session = selected { onSelect?(session) }
    }

    enum RowPlacement { case before, after }

    /// Kaynak çıkarıldıktan sonra hedefi bul: aşağı taşırken indeks kayması olmaz.
    /// Tek dizi ataması, SwiftUI'nin aradaki eksik satır durumunu çizmesini önler.
    @discardableResult
    func move(_ id: Session.ID, relativeTo target: Session.ID,
              placement: RowPlacement) -> Bool {
        guard id != target,
              let source = session(id), let destination = session(target),
              source.cwd == destination.cwd,
              source.status.isWaiting == destination.status.isWaiting else { return false }
        var reordered = sessions.filter { $0.id != id }
        guard let index = reordered.firstIndex(where: { $0.id == target }) else { return false }
        reordered.insert(source, at: index + (placement == .after ? 1 : 0))
        guard reordered.map(\.id) != sessions.map(\.id) else { return false }
        sessions = reordered
        return true
    }

    /// İptal edilen canlı sıralamayı geri al; bu sırada eklenen/kapanan oturumları koru.
    func restoreOrder(_ ids: [Session.ID]) {
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let known = Set(ids)
        let restored = ids.compactMap { byID[$0] } + sessions.filter { !known.contains($0.id) }
        if restored.map(\.id) != sessions.map(\.id) { sessions = restored }
    }

    @discardableResult
    func rename(_ session: Session, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, sessions.contains(where: { $0.id == session.id }) else { return false }
        session.customName = trimmed
        session.name = trimmed
        return true
    }

    func close(_ session: Session) {
        session.pty.hangUp()
        remove(session)
    }

    func kill(_ session: Session) {
        session.pty.kill()
        remove(session)
    }

    func remove(_ session: Session) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions.remove(at: index)
        onDispose?(session)

        let next = sessions.indices.contains(index) ? sessions[index]
                 : sessions.indices.contains(index - 1) ? sessions[index - 1]
                 : sessions.first
        for pane in panes.indices where panes[pane] == session.id {
            panes[pane] = (pane == 0 || next?.id != panes[0]) ? next?.id : nil
        }
        // Kapanan oturum yüzünden boşalan fazla paneli de kapat.
        while panes.count > 1, panes.last! == nil { panes.removeLast() }
        if activePane >= paneCount { activePane = paneCount - 1 }
        onLayout?(visibleIDs)
        if let current = selected { onSelect?(current) }
    }

    // MARK: - Gezinme

    private var flatOrder: [Session] {
        waiting + groups.flatMap(\.sessions)
    }

    func selectNext(by offset: Int) {
        let flat = flatOrder
        guard !flat.isEmpty else { return }
        let current = flat.firstIndex { $0.id == selectedID } ?? 0
        select(flat[(current + offset + flat.count) % flat.count].id)
    }

    func select(index: Int) {
        let flat = flatOrder
        guard flat.indices.contains(index) else { return }
        select(flat[index].id)
    }

    /// ⌘⇧A — çok ajanlı akışın bel kemiği (UI.md §6).
    func selectFirstWaiting() {
        guard let first = waiting.first else { return }
        select(first.id)
    }

    func markOutput(for session: Session) {
        guard !panes.contains(session.id) else { return }
        session.hasUnseenOutput = true
    }
}
