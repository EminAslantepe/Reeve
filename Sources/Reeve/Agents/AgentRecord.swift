import Foundation

/// `claude agents --json --all` çıktısındaki tek kayıt.
///
/// Doğrulanmış alanlar (claude 2.1.273). Savunmacı çözülüyor: bu resmi bir şema
/// değil, sürümle değişirse katman sessizce boş dönmeli, uygulama etkilenmemeli.
struct AgentRecord: Decodable, Equatable {
    /// Arka plan ajanlarında **yok**: onların bir terminal süreci olmuyor.
    let pid: Int32?
    /// Yalnızca arka plan oturumlarında var; `attach`/`logs`/`stop`/`rm` bunu alıyor.
    /// Varlığı tek başına "bu bir arka plan ajanı" demek.
    let id: String?
    let cwd: String
    let kind: String            // "interactive" | "background"
    let startedAt: Double?      // epoch ms
    let sessionId: String
    let name: String
    /// Yalnızca etkileşimli oturumlarda; arka planda yerine `state` geliyor.
    let status: String?         // "idle" | "busy" | "waiting"
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
        case .none:
            // Arka plan ajanının durumu `state`'te. Biten ajanı `.exited`
            // yapmıyoruz: `apply` ölmüş oturumun kaydını tüketmeden atlıyor,
            // o kayıt her turda yeni oturum diye yeniden eklenirdi.
            return state == "running" ? .busy : .idle
        default: return .live
        }
    }
}

/// Tek bir kaydın çözülememesi bütün turu düşürmemeli. Şema resmi değil:
/// bir alan değiştiğinde yalnızca o kayıt atlanıyor, kalanı görünür kalıyor.
private struct AgentRecordEnvelope: Decodable {
    let record: AgentRecord?
    init(from decoder: Decoder) throws {
        record = try? AgentRecord(from: decoder)
    }
}

extension AgentRecord {
    /// `nil` = çıktı hiç dizi değil (tur atlanır); `[]` = gerçekten ajan yok.
    static func list(from data: Data) -> [AgentRecord]? {
        guard let items = try? JSONDecoder().decode([AgentRecordEnvelope].self, from: data)
        else { return nil }
        return items.compactMap(\.record)
    }
}
