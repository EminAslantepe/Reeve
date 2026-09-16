import Foundation

/// `claude agents --json --all` çıktısındaki tek kayıt.
///
/// Doğrulanmış alanlar (claude 2.1.273). Savunmacı çözülüyor: bu resmi bir şema
/// değil, sürümle değişirse katman sessizce boş dönmeli, uygulama etkilenmemeli.
struct AgentRecord: Decodable, Equatable {
    let pid: Int32
    /// Yalnızca arka plan oturumlarında var; `attach`/`logs`/`stop`/`rm` bunu alıyor.
    /// Varlığı tek başına "bu bir arka plan ajanı" demek.
    let id: String?
    let cwd: String
    let kind: String            // "interactive" | "background"
    let startedAt: Double?      // epoch ms
    let sessionId: String
    let name: String
    let status: String          // "idle" | "busy" | "waiting"
    let waitingFor: String?
    let state: String?

    var isBackground: Bool { kind == "background" || id != nil }

    var started: Date {
        guard let startedAt else { return Date() }
        return Date(timeIntervalSince1970: startedAt / 1000)
    }

    var sessionUUID: UUID? { UUID(uuidString: sessionId) }

    var mappedStatus: Session.Status {
        switch status {
        case "busy": return .busy
        case "waiting": return .waiting(waitingFor ?? "izin bekliyor")
        case "idle": return .idle
        default: return .live
        }
    }
}
