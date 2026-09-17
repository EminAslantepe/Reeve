import Foundation
import Observation

/// Tek bir oturum. PTY'si, kimliği ve sol panelde görünen her şeyi taşır.
@MainActor
@Observable
final class Session: Identifiable {

    enum Kind: String {
        case shell
        case claude
    }

    /// Oturumu kim açtı — dört bölümdeki üç farklı davranışı bu belirliyor (UI.md D4).
    enum Origin {
        case center            // PTY bizde, terminal gösterilebilir
        case backgroundAgent   // `claude --bg`; `claude attach <id>` ile PTY açılabilir
        case external          // iTerm'de elle açılmış; terminali gösteremeyiz
    }

    enum Status: Equatable {
        /// Çalışıyor ama durumu bilmiyoruz — shell oturumları hep böyle.
        case live
        case idle
        case busy
        case waiting(String)
        case exited(Int32)

        var isOver: Bool { if case .exited = self { return true }; return false }
        var isWaiting: Bool { if case .waiting = self { return true }; return false }
    }

    struct Launch {
        var executable: String
        var args: [String]
        var env: [String: String]
    }

    /// Şu an çalışan tool — `PreToolUse` ile doluyor, `PostToolUse`/`Stop` ile boşalıyor.
    struct Activity: Equatable {
        var summary: String          // "Edit(SidebarView.swift)"
        var toolUseID: String?
        var startedAt: Date
    }

    /// `Task` çağrıları — mockup'taki `⚙ Explore 18s`.
    struct Subagent: Identifiable, Equatable {
        let id: String               // tool_use_id
        var name: String
        var startedAt: Date
        var finishedAt: Date?

        var elapsed: String {
            let seconds = Int((finishedAt ?? Date()).timeIntervalSince(startedAt))
            return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)dk"
        }
    }

    let id = UUID()
    /// Reeve üretiyor ve `claude --session-id` ile veriyoruz; PTY ↔ oturum ↔ JSONL
    /// eşlemesi böylece tahminle değil garantiyle kuruluyor (PLAN.md §5).
    /// Oturum kabuk içinden elle `claude` ile başlatıldıysa bu sonradan öğreniliyor,
    /// o yüzden `var` (bkz. `SessionStore.apply(_ event:)`).
    var claudeSessionID: UUID
    /// PTY'ye enjekte edilen `REEVE_PANE_ID`. `--session-id` verilmemiş
    /// oturumlarda hook'u doğru satıra bağlayan tek ip ucu.
    let paneID: UUID

    var name: String
    var customName: String?
    var cwd: String
    let kind: Kind
    var origin: Origin
    var status: Status = .live
    var startedAt = Date()
    /// Sen bakmazken çıktı üretti mi (UI.md D4).
    var hasUnseenOutput = false
    /// Arka plan ajanlarının kısa id'si — `attach`/`logs`/`stop`/`rm` bunu alıyor.
    var shortID: String?
    /// Harici oturumlarda `claude agents --json`'dan gelir; bizimkilerde PTY'den.
    var reportedPID: Int32?

    // --- Katman 2 (hook) ve Katman 4 (süreç ağacı) ---
    var activity: Activity?
    var subagents: [Subagent] = []
    var children: [ChildProcess] = []
    /// `Stop` olayındaki son asistan mesajı — "işi bitti" özeti.
    var lastMessage: String?

    // --- Katman 3 (transcript) ---
    var usage: Usage?
    var turns: [Turn] = []

    @ObservationIgnored var pty = PtyProcess()
    @ObservationIgnored let launch: Launch?

    init(name: String,
         cwd: String,
         kind: Kind,
         origin: Origin = .center,
         claudeSessionID: UUID,
         paneID: UUID = UUID(),
         launch: Launch?,
         customName: String? = nil) {
        self.name = customName ?? name
        self.customName = customName
        self.cwd = cwd
        self.kind = kind
        self.origin = origin
        self.claudeSessionID = claudeSessionID
        self.paneID = paneID
        self.launch = launch
    }

    /// Reeve'in açmadığı bir oturum — `claude agents --json`'dan doğdu.
    convenience init(discovered record: AgentRecord) {
        self.init(name: record.name,
                  cwd: record.cwd,
                  kind: .claude,
                  origin: record.isBackground ? .backgroundAgent : .external,
                  claudeSessionID: record.sessionUUID ?? UUID(),
                  launch: nil)
        startedAt = record.started
        status = record.mappedStatus
        shortID = record.id
        reportedPID = record.pid
    }

    /// Terminalini gösterebiliyor muyuz (UI.md §4 tablosu).
    var hasTerminal: Bool { origin == .center }

    var pid: Int32? {
        if pty.pid > 0 { return pty.pid }
        return reportedPID
    }

    var displayCwd: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }

    var folderName: String { (cwd as NSString).lastPathComponent }

    /// Sidebar'ın ikinci satırı (UI.md §2).
    /// Faz 3'te `busy` satırı hook'tan gelen tool adıyla dolacak.
    var subtitle: String {
        switch status {
        case .exited(let code):
            return code < 0 ? "sinyal \(-code) ile öldü" : "exit \(code)"
        case .waiting(let what):
            return what
        case .busy:
            // Hook köprüsü kuruluysa burada hangi tool'un çalıştığı yazıyor.
            // Transcript okunduysa başına model adı geliyor: "Opus 5 · Edit(...)".
            if let activity { return prefixed(activity.summary) }
            return origin == .backgroundAgent ? "çalışıyor · claude --bg"
                                              : prefixed("çalışıyor")
        case .idle, .live:
            if let activity { return prefixed(activity.summary) }
            switch origin {
            case .backgroundAgent: return "arka plan · claude --bg"
            case .external:        return prefixed("\(displayCwd) · terminal yok")
            case .center:          return prefixed(displayCwd)
            }
        }
    }

    /// Mockup'taki `Opus 5 · Edit(SidebarView.swift)` biçimi.
    private func prefixed(_ text: String) -> String {
        guard let model = usage?.model else { return text }
        return "\(model) · \(text)"
    }

    /// Satırın sağ alt köşesi — mockup'ın `.tail` hücresi.
    var costLabel: String? {
        guard let usage else { return nil }
        if usage.costUSD > 0 { return usage.costLabel }
        if usage.billableTokens > 0 { return "\(usage.tokenLabel) tk" }
        return nil
    }

    var elapsed: String {
        let seconds = Int(Date().timeIntervalSince(startedAt))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)dk" }
        if seconds < 86400 { return "\(seconds / 3600)sa" }
        return "\(seconds / 86400)g"
    }
}
