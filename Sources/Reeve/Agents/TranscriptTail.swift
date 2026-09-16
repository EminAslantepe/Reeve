import Foundation

/// Bir oturumun ölçülebilir kullanımı: model, token, maliyet, süre, satır farkı.
struct Usage: Equatable {
    var model: String?
    var inputTokens = 0
    var outputTokens = 0
    var thinkingTokens = 0
    var cacheCreationTokens = 0
    var cacheReadTokens = 0
    var costUSD: Double = 0
    var linesAdded = 0
    var linesRemoved = 0
    var durationMS = 0

    /// Alt şeritte gösterilen sayı. Cache okuması milyonları buluyor ve gerçek
    /// iş hacmini temsil etmiyor, o yüzden toplamın dışında — panelde ayrı duruyor.
    var billableTokens: Int { inputTokens + outputTokens + cacheCreationTokens }

    var tokenLabel: String {
        let value = billableTokens
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }

    var costLabel: String { String(format: "$%.2f", costUSD) }
}

/// Transcript'ten çıkarılan tek bir konuşma adımı.
struct Turn: Identifiable, Equatable {
    enum Kind: String { case user, assistant, tool }
    let id: String
    let kind: Kind
    let text: String
    let at: Date
}

/// Katman 3 — transcript JSONL (PLAN.md §3).
///
/// > **Resmi API değil**, sürümle değişebilir. Bu yüzden her şey savunmacı:
/// > çözülemeyen satır atlanır, dosya bulunamazsa katman sessizce susar,
/// > uygulamanın geri kalanı etkilenmez.
///
/// Ölçülen şema (claude 2.1.273): `type:"cost-state"` kaydı `totalCostUSD`,
/// `totalDuration`, `totalLinesAdded/Removed` ve model başına `modelUsage`
/// taşıyor; `type:"assistant"` kayıtları `message.model` veriyor.
final class TranscriptTail {

    /// Ana kuyrukta: oturum kimliği → kullanım.
    var onUpdate: (([UUID: Usage]) -> Void)?

    private let queue = DispatchQueue(label: "io.reeve.transcript")
    private var paths: [UUID: URL] = [:]          // çözülen dosya yolları
    private var offsets: [UUID: UInt64] = [:]     // sadece yeni byte'ları oku
    private var usages: [UUID: Usage] = [:]
    private var turns: [UUID: [Turn]] = [:]

    /// Ana kuyrukta: oturum kimliği → son konuşma adımları.
    var onTurns: (([UUID: [Turn]]) -> Void)?

    /// Bellekte tutulan adım sayısı. Transcript megabaytlara çıkabiliyor.
    private static let keep = 40

    private static var projectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    func refresh(_ sessions: [(id: UUID, sessionID: UUID, cwd: String)]) {
        guard !sessions.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            var changed = false
            for entry in sessions {
                if self.ingest(entry) { changed = true }
            }
            guard changed else { return }
            let usage = self.usages
            let steps = self.turns
            DispatchQueue.main.async {
                self.onUpdate?(usage)
                self.onTurns?(steps)
            }
        }
    }

    func forget(_ id: UUID) {
        queue.async { [weak self] in
            self?.paths[id] = nil
            self?.offsets[id] = nil
            self?.usages[id] = nil
            self?.turns[id] = nil
        }
    }

    /// Transcript dosyasının yolu — "Finder'da göster" için.
    func file(for id: UUID) -> URL? { queue.sync { paths[id] } }

    // MARK: -

    private func ingest(_ entry: (id: UUID, sessionID: UUID, cwd: String)) -> Bool {
        guard let url = resolve(entry) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        var offset = offsets[entry.id] ?? 0
        if offset > size { offset = 0 }              // dosya döndü/kısaldı
        guard size > offset else { return false }

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return false }
        offsets[entry.id] = size

        var usage = usages[entry.id] ?? Usage()
        var steps = turns[entry.id] ?? []
        var touched = false
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            if apply(object, to: &usage) { touched = true }
            if let turn = Self.turn(from: object) {
                steps.append(turn)
                touched = true
            }
        }
        if steps.count > Self.keep { steps.removeFirst(steps.count - Self.keep) }
        let same = usages[entry.id] == usage && turns[entry.id] == steps
        guard touched, !same else { return false }
        usages[entry.id] = usage
        turns[entry.id] = steps
        return true
    }

    /// Tek bir JSONL satırını uygular. Tanımadığı her şeyi görmezden gelir.
    private func apply(_ object: [String: Any], to usage: inout Usage) -> Bool {
        switch object["type"] as? String {
        case "cost-state":
            usage.costUSD = object["totalCostUSD"] as? Double ?? usage.costUSD
            usage.durationMS = object["totalDuration"] as? Int ?? usage.durationMS
            usage.linesAdded = object["totalLinesAdded"] as? Int ?? usage.linesAdded
            usage.linesRemoved = object["totalLinesRemoved"] as? Int ?? usage.linesRemoved

            guard let models = object["modelUsage"] as? [String: [String: Any]] else { return true }
            var totals = Usage()
            var dominant: (name: String, output: Int)?
            for (name, stats) in models {
                let output = stats["outputTokens"] as? Int ?? 0
                totals.inputTokens += stats["inputTokens"] as? Int ?? 0
                totals.outputTokens += output
                totals.thinkingTokens += stats["thinkingTokens"] as? Int ?? 0
                totals.cacheCreationTokens += stats["cacheCreationInputTokens"] as? Int ?? 0
                totals.cacheReadTokens += stats["cacheReadInputTokens"] as? Int ?? 0
                // "Modeli" en çok üreten belirliyor: haiku arka planda küçük işler
                // yapıyor, kullanıcının sorduğu model o değil.
                if output > (dominant?.output ?? -1) { dominant = (name, output) }
            }
            usage.inputTokens = totals.inputTokens
            usage.outputTokens = totals.outputTokens
            usage.thinkingTokens = totals.thinkingTokens
            usage.cacheCreationTokens = totals.cacheCreationTokens
            usage.cacheReadTokens = totals.cacheReadTokens
            if let dominant { usage.model = Self.displayName(dominant.name) }
            return true

        case "assistant":
            guard usage.model == nil,
                  let message = object["message"] as? [String: Any],
                  let model = message["model"] as? String else { return false }
            usage.model = Self.displayName(model)
            return true

        default:
            return false
        }
    }

    /// Kullanıcı ve asistan adımlarını çıkarır; ara kayıtları (mode, ai-title,
    /// attachment…) görmezden gelir.
    private static func turn(from object: [String: Any]) -> Turn? {
        guard let type = object["type"] as? String,
              type == "user" || type == "assistant",
              object["isSidechain"] as? Bool != true,
              object["isMeta"] as? Bool != true,
              let uuid = object["uuid"] as? String,
              let message = object["message"] as? [String: Any] else { return nil }

        let at = (object["timestamp"] as? String).flatMap {
            ISO8601DateFormatter().date(from: $0)
        } ?? Date()

        // content ya düz metin ya da parça dizisi.
        if let text = message["content"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Turn(id: uuid, kind: type == "user" ? .user : .assistant,
                        text: clip(trimmed), at: at)
        }
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }

        var text = ""
        var tool: String?
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let value = block["text"] as? String { text += value }
            case "tool_use":
                if tool == nil { tool = block["name"] as? String }
            default:
                break
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return Turn(id: uuid, kind: type == "user" ? .user : .assistant,
                        text: clip(trimmed), at: at)
        }
        if let tool {
            return Turn(id: uuid, kind: .tool, text: tool, at: at)
        }
        return nil
    }

    private static func clip(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        return flat.count > 220 ? String(flat.prefix(219)) + "…" : flat
    }

    /// `claude-opus-5[1m]` → `Opus 5`
    static func displayName(_ raw: String) -> String {
        var name = raw
        if let bracket = name.firstIndex(of: "[") { name = String(name[..<bracket]) }
        name = name.replacingOccurrences(of: "claude-", with: "")
        // Tarih ekini at: haiku-4-5-20251001 → haiku-4-5
        let parts = name.split(separator: "-").filter { $0.count != 8 || Int($0) == nil }
        guard let family = parts.first else { return raw }
        let version = parts.dropFirst().joined(separator: ".")
        let capitalized = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? capitalized : "\(capitalized) \(version)"
    }

    /// Önce slug kuralıyla dene, tutmazsa dosyayı ara.
    /// Slug resmi bir sözleşme değil; arama yavaş ama kesin.
    private func resolve(_ entry: (id: UUID, sessionID: UUID, cwd: String)) -> URL? {
        if let known = paths[entry.id],
           FileManager.default.fileExists(atPath: known.path) { return known }

        let fm = FileManager.default
        let file = entry.sessionID.uuidString.lowercased() + ".jsonl"
        let slug = entry.cwd.replacingOccurrences(of: "/", with: "-")
        let direct = Self.projectsRoot.appendingPathComponent(slug).appendingPathComponent(file)
        if fm.fileExists(atPath: direct.path) {
            paths[entry.id] = direct
            return direct
        }
        guard let dirs = try? fm.contentsOfDirectory(at: Self.projectsRoot,
                                                     includingPropertiesForKeys: nil) else { return nil }
        for dir in dirs {
            let candidate = dir.appendingPathComponent(file)
            if fm.fileExists(atPath: candidate.path) {
                paths[entry.id] = candidate
                return candidate
            }
        }
        return nil
    }
}
