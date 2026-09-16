import Foundation

/// Katman 2 — hook olaylarını anlık alan köprü (PLAN.md §3).
///
/// **Plandan sapma, bilerek.** Plan `NWListener` + 127.0.0.1 + token diyordu.
/// Bunun yerine bir **spool dizini** kullanıyoruz: hook script'i olayı benzersiz
/// bir geçici dosyaya yazıp `mv` ile dizine atıyor, Center dizini `DispatchSource`
/// ile izliyor. Gerekçeler:
///
/// - İmzasız bir uygulamanın soket dinlemesi macOS güvenlik duvarı uyarısı
///   çıkarabiliyor; dosya sisteminde böyle bir sorun yok.
/// - Port her açılışta değişir, hook komutu ise `settings.json`'da sabittir;
///   spool'da eşgüdüm gereken bir şey yok, token'a da gerek kalmıyor.
/// - `mv` atomik olduğu için büyük `tool_input` payload'ları birbirine karışmıyor
///   (aynı dosyaya `>>` ile yazmak PIPE_BUF üstünde karışabilirdi).
/// - Reeve kapalıyken dizin de yok; script tek `[ -d ]` kontrolüyle sessizce
///   çıkıyor, dosya birikmiyor.
final class HookBridge {

    /// Ana kuyrukta, olay geldikçe.
    var onEvent: ((HookEvent) -> Void)?

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/reeve")
    }
    static var spool: URL { root.appendingPathComponent("events") }
    static var script: URL { root.appendingPathComponent("hook.sh") }

    private let queue = DispatchQueue(label: "io.reeve.hooks")
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1

    func start() {
        let fm = FileManager.default
        // Eski oturumdan kalan olaylar taze sanılmasın.
        try? fm.removeItem(at: Self.spool)
        try? fm.createDirectory(at: Self.spool, withIntermediateDirectories: true)

        descriptor = open(Self.spool.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write], queue: queue)
        watcher.setEventHandler { [weak self] in self?.drain() }
        watcher.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        source = watcher
        watcher.resume()
        queue.async { [weak self] in self?.drain() }
    }

    func stop() {
        source?.cancel()
        source = nil
        // Dizin yoksa script hiç iş yapmıyor — kapanınca temizliyoruz.
        try? FileManager.default.removeItem(at: Self.spool)
    }

    // MARK: -

    private func drain() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Self.spool.path) else { return }
        let decoder = JSONDecoder()
        var events: [(Date, HookEvent)] = []

        for name in names where name.hasSuffix(".json") {
            let url = Self.spool.appendingPathComponent(name)
            defer { try? fm.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let event = try? decoder.decode(HookEvent.self, from: data) else { continue }
            let stamp = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            events.append((stamp, event))
        }
        guard !events.isEmpty else { return }

        // Dosya sistemi sırayı garanti etmiyor; olayları zamana göre diziyoruz.
        let ordered = events.sorted { $0.0 < $1.0 }.map(\.1)
        DispatchQueue.main.async { [weak self] in
            for event in ordered { self?.onEvent?(event) }
        }
    }
}
