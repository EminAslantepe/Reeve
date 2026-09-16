import Foundation

/// `~/.claude/settings.json` içine hook'ları kurar ve geri alır.
///
/// > **Kullanıcının hook'larını ezmek geri dönüşü zor bir hata** (PLAN.md §8).
/// > Bu yüzden: yazmadan önce zaman damgalı yedek, mevcut anahtarlar korunarak
/// > birleştirme, ve yalnızca bizim script'imizi işaret eden girdileri silen bir
/// > kaldırma. Kurulum opt-in — menüden açılıp kapatılıyor.
enum HookInstaller {

    static let events = ["SessionStart", "PreToolUse", "PostToolUse",
                         "Notification", "Stop", "SubagentStop", "SessionEnd"]

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    enum Outcome {
        case installed(backup: URL?)
        case removed(backup: URL?)
        case failed(String)
    }

    static var isInstalled: Bool {
        guard let hooks = load()?["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { group in
            entries(group).contains { isOurs($0) }
        }
    }

    // MARK: - Kur / kaldır

    static func install() -> Outcome {
        do {
            try writeScript()
        } catch {
            return .failed("hook script'i yazılamadı: \(error.localizedDescription)")
        }

        var settings = load() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var group = (hooks[event] as? [[String: Any]]) ?? []
            group.removeAll { matcher in isOurs(matcher) }      // eskisi varsa tazele
            group.append([
                "matcher": "*",
                "hooks": [["type": "command", "command": command(for: event)]],
            ])
            hooks[event] = group
        }
        settings["hooks"] = hooks
        return save(settings, installing: true)
    }

    static func uninstall() -> Outcome {
        guard var settings = load() else { return .failed("settings.json okunamadı") }
        guard var hooks = settings["hooks"] as? [String: Any] else { return .removed(backup: nil) }

        for (event, group) in hooks {
            var remaining = entries(group).filter { !isOurs($0) }
            // Bizim dışımızda hiçbir şey kalmadıysa anahtarı da bırakmayalım.
            if remaining.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = remaining }
            remaining = []
        }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") }
        else { settings["hooks"] = hooks }
        return save(settings, installing: false)
    }

    // MARK: - Ayrıntılar

    private static func command(for event: String) -> String {
        "\(HookBridge.script.path) \(event)"
    }

    /// Bir hook girdisi bizim script'imizi mi çağırıyor?
    private static func isOurs(_ entry: [String: Any]) -> Bool {
        let inner = (entry["hooks"] as? [[String: Any]]) ?? []
        return inner.contains { hook in
            (hook["command"] as? String)?.contains(HookBridge.script.path) == true
        }
    }

    private static func entries(_ group: Any) -> [[String: Any]] {
        (group as? [[String: Any]]) ?? []
    }

    private static func load() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private static func save(_ settings: [String: Any], installing: Bool) -> Outcome {
        let fm = FileManager.default
        var backup: URL?
        if fm.fileExists(atPath: settingsURL.path) {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let target = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.json.center-backup-\(stamp)")
            do {
                try fm.copyItem(at: settingsURL, to: target)
                backup = target
            } catch {
                return .failed("yedek alınamadı, hiçbir şey yazılmadı: \(error.localizedDescription)")
            }
        }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try fm.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try data.write(to: settingsURL, options: .atomic)
            return installing ? .installed(backup: backup) : .removed(backup: backup)
        } catch {
            return .failed("settings.json yazılamadı: \(error.localizedDescription)")
        }
    }

    private static func writeScript() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: HookBridge.root, withIntermediateDirectories: true)
        let body = """
        #!/bin/bash
        # Reeve hook köprüsü — otomatik üretildi, elle düzenlenmeyin.
        # Tek kuralı var: Claude'u asla bloklamaz ve daima 0 döner.
        dir="$HOME/.claude/reeve/events"
        [ -d "$dir" ] || exit 0          # Reeve kapalı — sessizce çık
        tmp="$dir/.tmp.$$.$RANDOM"
        {
          printf '{"event":"%s","pane":"%s","payload":' "$1" "${REEVE_PANE_ID:-}"
          cat
          printf '}'
        } > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; exit 0; }
        # mv atomik: büyük payload'lar birbirine karışmıyor.
        mv -f "$tmp" "$dir/$(date +%s).$$.$RANDOM.json" 2>/dev/null
        exit 0
        """
        try body.write(to: HookBridge.script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: HookBridge.script.path)
    }
}
