import AppKit
import Foundation

/// Katman 1 — `claude agents --json --all` yoklayıcısı (PLAN.md §3).
///
/// Bu katmanın işi terminal içeriği DEĞİL; sol paneldeki durum. Terminal byte'ları
/// push ile geliyor (`PtyProcess`), burası yoklama yapıyor.
///
/// **Sıklık bedava değil:** her çağrı ayrı bir süreç, ölçülen ~140 ms duvar /
/// ~0.10 s CPU. 1 Hz'de sadece sol panel için sürekli ~%10 çekirdek eder. O yüzden
/// pencere öndeyken 1 sn, arkadayken 5 sn.
final class AgentRegistry {

    /// Her başarılı yoklamadan sonra ana kuyrukta çağrılır.
    var onPoll: (([AgentRecord]) -> Void)?

    /// Bir kez çözülüp paylaşılıyor — `claude stop` gibi tek seferlik çağrılar da kullanıyor.
    static let claudePath: String? = AgentRegistry.resolveClaude()

    private let queue = DispatchQueue(label: "io.reeve.agents")
    private var timer: DispatchSourceTimer?
    private var claudePath: String?
    private var inFlight = false
    private var currentInterval: TimeInterval = 0

    /// Hook köprüsü ayaktayken yoklamanın işi "durum değişti mi" değil,
    /// yalnızca yeni/kaybolan oturumu yakalamak — o yüzden seyrekleşiyor.
    var hooksActive = false {
        didSet { schedule(interval: currentTarget) }
    }

    private var currentTarget: TimeInterval {
        let active = NSApp.isActive
        if hooksActive { return active ? 3 : 8 }
        return active ? Self.foreground : Self.background
    }

    private static let foreground: TimeInterval = 1
    private static let background: TimeInterval = 5

    func start() {
        claudePath = Self.claudePath
        guard claudePath != nil else {
            FileHandle.standardError.write(Data("reeve: `claude` bulunamadı, ajan katmanı kapalı\n".utf8))
            return
        }
        observeActivation()
        schedule(interval: currentTarget)
        queue.async { [weak self] in self?.poll() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Zamanlama

    private func observeActivation() {
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.schedule(interval: self.currentTarget)
            }
        }
    }

    private func schedule(interval: TimeInterval) {
        guard interval != currentInterval else { return }
        currentInterval = interval
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        source.setEventHandler { [weak self] in self?.poll() }
        timer = source
        source.resume()
    }

    // MARK: - Yoklama

    private func poll() {
        guard let claudePath, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["agents", "--json", "--all"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return }

        // Şema resmi değil; çözülemezse bu tur sessizce atlanır.
        guard let records = try? JSONDecoder().decode([AgentRecord].self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in self?.onPoll?(records) }
    }

    // MARK: - `claude` nerede

    /// Uygulama Finder'dan açıldığında PATH neredeyse boş olur; kabuk profiline
    /// düşmeden önce bilinen yerlere bakıyoruz.
    private static func resolveClaude() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) { return path }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return fm.isExecutableFile(atPath: path) ? path : nil
    }
}
