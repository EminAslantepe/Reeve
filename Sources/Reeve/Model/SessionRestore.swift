import Foundation

/// Uygulama kapanınca açık oturumların kimlikleri saklanıyor; `claude --resume`
/// ile konuşma kaldığı yerden açılabiliyor (PLAN.md §7, Faz 4).
///
/// **Otomatik değil.** Açılışta kendiliğinden yeniden süreç doğurmak sürpriz
/// olurdu; geri yükleme menüden tetikleniyor (Oturum ▸ Önceki oturumları geri
/// yükle). PLAN.md §8'deki "v1'de kalıcılık yok mu" sorusunun cevabı bu:
/// PTY'ler yaşamıyor, ama konuşmalar geri getirilebiliyor.
struct SavedSession: Codable, Equatable {
    var name: String
    var cwd: String
    var isClaude: Bool
    var claudeSessionID: String
}

enum SessionRestore {
    private static let key = "OpenSessions"

    static func save(_ sessions: [Session]) {
        let saved = sessions
            .filter { $0.origin == .center }          // yalnızca bizim açtıklarımız
            .map {
                SavedSession(name: $0.name,
                             cwd: $0.cwd,
                             isClaude: $0.kind == .claude,
                             claudeSessionID: $0.claudeSessionID.uuidString)
            }
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static var saved: [SavedSession] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([SavedSession].self, from: data)
        else { return [] }
        return list
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
