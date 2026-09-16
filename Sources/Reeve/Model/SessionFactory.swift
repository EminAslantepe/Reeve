import Foundation

/// Yeni oturum şablonları (PLAN.md §5).
enum Template: String, CaseIterable, Identifiable {
    case claude
    case claudeWorktree
    case shell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude:         return "Claude"
        case .claudeWorktree: return "Claude + yeni worktree"
        case .shell:          return "Shell"
        }
    }

    /// Mockup'taki sağdaki gri ipucu — hangi flag'e karşılık geldiği.
    var hint: String {
        switch self {
        case .claude:         return "--session-id"
        case .claudeWorktree: return "--worktree"
        case .shell:          return "$SHELL"
        }
    }

    var kind: Session.Kind { self == .shell ? .shell : .claude }
}

enum SessionFactory {

    static var loginShell: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// `center-9f` gibi. Klasör adı + iki karakterlik ayırıcı.
    static func name(for cwd: String, existing: [String]) -> String {
        let base = (cwd as NSString).lastPathComponent
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let stem = base.isEmpty ? "session" : base
        let alphabet = Array("0123456789abcdef")
        for _ in 0..<64 {
            let suffix = String((0..<2).map { _ in alphabet.randomElement()! })
            let candidate = "\(stem)-\(suffix)"
            if !existing.contains(candidate) { return candidate }
        }
        return "\(stem)-\(UUID().uuidString.prefix(4))"
    }

    /// Arka plan ajanını gerçek bir terminalde açar: yeni PTY + `claude attach`.
    /// `attach` tam ekranı devralıyor; Ctrl+Z ile alttaki kabuğa düşülüyor.
    static func attach(to agent: Session) -> Session? {
        guard let shortID = agent.shortID else { return nil }
        let shell = loginShell
        let paneID = UUID()
        var env = baseEnvironment()
        env["REEVE_PANE_ID"] = paneID.uuidString
        return Session(
            name: agent.name,
            cwd: agent.cwd,
            kind: .claude,
            origin: .center,
            claudeSessionID: agent.claudeSessionID,
            paneID: paneID,
            launch: .init(executable: shell,
                          args: ["-l", "-c", "claude attach '\(shortID)'; exec '\(shell)' -i"],
                          env: env))
    }

    /// Kaydedilmiş bir oturumu `claude --resume` ile geri getirir.
    static func resume(_ saved: SavedSession) -> Session {
        let shell = loginShell
        let paneID = UUID()
        let sessionID = UUID(uuidString: saved.claudeSessionID) ?? UUID()
        var env = baseEnvironment()
        env["REEVE_PANE_ID"] = paneID.uuidString

        let args: [String]
        if saved.isClaude {
            let command = "claude --resume '\(sessionID.uuidString.lowercased())'"
                        + "; exec '\(shell)' -i"
            args = ["-l", "-c", command]
        } else {
            args = ["-i", "-l"]
        }
        return Session(name: saved.name,
                       cwd: saved.cwd,
                       kind: saved.isClaude ? .claude : .shell,
                       origin: .center,
                       claudeSessionID: sessionID,
                       paneID: paneID,
                       launch: .init(executable: shell, args: args, env: env))
    }

    static func make(template: Template, cwd: String, name: String) -> Session {
        let claudeSessionID = UUID()
        let paneID = UUID()
        return Session(
            name: name,
            cwd: cwd,
            kind: template.kind,
            origin: .center,
            claudeSessionID: claudeSessionID,
            paneID: paneID,
            launch: launchSpec(template: template,
                               name: name,
                               claudeSessionID: claudeSessionID,
                               paneID: paneID,
                               shell: loginShell))
    }

    static func baseEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // PLAN.md §2.2 — yoksa claude kendini kısıtlı terminalde sanıp sade moda düşer.
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        env.removeValue(forKey: "TERM_PROGRAM")

        // Reeve bir Claude oturumunun terminalinden başlatılmışsa o oturumun
        // işaretleri ortamda kalıyor ve açtığımız her yeni oturuma miras geçiyor
        // ("Transcript saving is off - inherited CLAUDE_CODE_CHILD_SESSION").
        // Kabuğu login modunda açtığımız için kullanıcının kendi profili bu
        // değişkenleri yeniden kuruyor; mirası temizlemek güvenli.
        for key in env.keys where key.hasPrefix("CLAUDE_") || key == "CLAUDECODE" {
            env.removeValue(forKey: key)
        }
        return env
    }

    private static func launchSpec(template: Template,
                                   name: String,
                                   claudeSessionID: UUID,
                                   paneID: UUID,
                                   shell: String) -> Session.Launch {
        var env = baseEnvironment()
        // Hook script'i bunu geri yolluyor; oturum `--session-id` almadan
        // başlatılmış olsa bile satırı doğru bağlayabiliyoruz (ölçüldü).
        env["REEVE_PANE_ID"] = paneID.uuidString

        switch template {
        case .shell:
            return .init(executable: shell, args: ["-i", "-l"], env: env)

        case .claude, .claudeWorktree:
            var command = "claude --session-id '\(claudeSessionID.uuidString.lowercased())'"
                        + " --name '\(name)'"
            if template == .claudeWorktree {
                command += " --worktree '\(name)'"
            }
            // Claude'dan çıkılınca terminal ölmesin (PLAN.md §5).
            command += "; exec '\(shell)' -i"
            return .init(executable: shell, args: ["-l", "-c", command], env: env)
        }
    }
}
