import Foundation

/// Hook script'inin yolladığı zarf. Şema makinede ölçüldü (claude 2.1.273):
/// `session_id`, `cwd`, `hook_event_name`, `tool_name`, `tool_input`,
/// `tool_use_id`, `duration_ms`, `last_assistant_message`, `reason`.
///
/// Resmi API değil — savunmacı çözülüyor, bozulursa katman sessizce susar.
struct HookEvent: Decodable {
    let event: String
    /// PTY'ye enjekte ettiğimiz `REEVE_PANE_ID`. Oturum `--session-id` almadan
    /// açıldıysa (kullanıcı shell'de elle `claude` yazdıysa) eşleme buradan kurulur.
    let pane: String?
    let payload: Payload

    struct Payload: Decodable {
        let sessionID: String?
        let cwd: String?
        let toolName: String?
        let toolInput: [String: JSONValue]?
        let toolUseID: String?
        let durationMS: Int?
        let lastAssistantMessage: String?
        let reason: String?
        let message: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case cwd
            case toolName = "tool_name"
            case toolInput = "tool_input"
            case toolUseID = "tool_use_id"
            case durationMS = "duration_ms"
            case lastAssistantMessage = "last_assistant_message"
            case reason
            case message
        }
    }

    var sessionUUID: UUID? { payload.sessionID.flatMap(UUID.init(uuidString:)) }
    var paneUUID: UUID? { pane.flatMap(UUID.init(uuidString:)) }

    /// Sidebar'ın ikinci satırı için: `Edit(SidebarView.swift)`, `Bash(npm run dev)`.
    var toolSummary: String? {
        guard let tool = payload.toolName else { return nil }
        guard let input = payload.toolInput,
              let detail = Self.detail(tool: tool, input: input) else { return tool }
        return "\(tool)(\(detail))"
    }

    /// Alt-ajan çağrılarında görünen ad — mockup'taki `⚙ Explore`.
    var subagentName: String? {
        guard payload.toolName == "Task", let input = payload.toolInput else { return nil }
        if case .string(let type)? = input["subagent_type"], !type.isEmpty { return type }
        if case .string(let text)? = input["description"] { return text }
        return "Task"
    }

    private static func detail(tool: String, input: [String: JSONValue]) -> String? {
        func string(_ key: String) -> String? {
            if case .string(let value)? = input[key] { return value }
            return nil
        }
        let raw: String?
        switch tool {
        case "Edit", "Write", "Read", "NotebookEdit":
            raw = string("file_path").map { ($0 as NSString).lastPathComponent }
        case "Bash":
            raw = string("command")
        case "Grep", "Glob":
            raw = string("pattern")
        case "Task":
            raw = string("subagent_type") ?? string("description")
        case "WebFetch":
            raw = string("url")
        default:
            raw = string("description") ?? string("file_path") ?? string("command")
        }
        guard let raw, !raw.isEmpty else { return nil }
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 38 ? String(flat.prefix(37)) + "…" : flat
    }
}

/// `tool_input` her araçta farklı şekilli; sadece string alanları okuyoruz.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else { self = .other }
    }
}
