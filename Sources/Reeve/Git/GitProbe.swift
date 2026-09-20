import Foundation

/// Grup başlığındaki rozet: `main ●3 ↑2`
struct GitState: Equatable {
    var branch: String
    /// Commit'lenmemiş (untracked dahil) dosya sayısı.
    var dirty: Int
    /// Remote'a gönderilmemiş commit sayısı.
    var ahead: Int
}

/// `git diff --numstat` satırı.
struct GitChange: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let added: Int
    let removed: Int

    var name: String { (path as NSString).lastPathComponent }
}

/// `git worktree list` girdisi.
struct Worktree: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let branch: String?

    var name: String { (path as NSString).lastPathComponent }
}

/// Repo'daki dosyaların adı → yol dizini.
///
/// Terminalde yalın yazılmış dosya adlarını ("main.swift") bağlayabilmek için:
/// çalışma dizinine göre çözülemiyorlar, repo içinde aranmaları gerekiyor.
struct FileIndex {
    /// Repo kökünün tam yolu.
    let root: String
    /// Dosya adı → repo köküne göre yollar. Aynı ad birden fazla yerde olabilir.
    let byName: [String: [String]]
}

/// Klasör başına git durumunu okur. Üç ucuz komut + kısa ömürlü önbellek;
/// hook'lara, transcript'e, libproc'a bağlı değil.
final class GitProbe {

    /// Ana kuyrukta, durum değiştiğinde çağrılır.
    var onUpdate: (([String: GitState]) -> Void)?

    private let queue = DispatchQueue(label: "io.reeve.git")
    private var states: [String: GitState] = [:]
    private var indexes: [String: (index: FileIndex, at: Date)] = [:]
    private var gitPath: String?

    init() {
        let fm = FileManager.default
        gitPath = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
            .first { fm.isExecutableFile(atPath: $0) }
    }

    func refresh(cwds: [String]) {
        guard gitPath != nil else { return }
        let unique = Array(Set(cwds))
        queue.async { [weak self] in
            guard let self else { return }
            var next: [String: GitState] = [:]
            for cwd in unique {
                if let state = self.probe(cwd) { next[cwd] = state }
            }
            guard next != self.states else { return }
            self.states = next
            DispatchQueue.main.async { self.onUpdate?(next) }
        }
    }

    // MARK: - İnceleme paneli için, istek üzerine

    /// Ham birleşik fark. Görüntüleyici açıkken istek üzerine; çıktı devasa
    /// olabildiği için tavanla kesiliyor (panel zaten o kadarını göstermiyor).
    func diff(in cwd: String, path: String? = nil, limit: Int = 400_000,
              completion: @escaping (String) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var args = ["diff", "HEAD"]
            // `--` ayracı şart: yol bir dal adıyla çakışırsa git yolu değil dalı seçerdi.
            //
            // `:(top,literal)` öneki de şart: `--numstat` yolları repo KÖKÜNE göre
            // veriyor, pathspec ise komutun çalıştığı dizine göre çözülüyor. Alt
            // dizinde açılmış bir oturumda ikisi uyuşmuyor ve fark boş çıkıyordu.
            // `literal`, adında `*` ya da `[` geçen dosyanın glob sanılmasını önler.
            if let path { args += ["--", ":(top,literal)" + path] }
            var raw = self.run(args, in: cwd) ?? ""
            if raw.count > limit {
                raw = String(raw.prefix(limit)) + "\n\n… fark çıktısı kısaltıldı"
            }
            DispatchQueue.main.async { completion(raw) }
        }
    }

    /// `git diff --stat` — panel açıkken çağrılıyor. Büyük repolarda pahalı
    /// olabildiği için düzenli yoklamaya sokulmadı.
    func changes(in cwd: String, completion: @escaping ([GitChange]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let raw = self.run(["diff", "--numstat", "HEAD"], in: cwd) ?? ""
            var out: [GitChange] = []
            for line in raw.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 2)
                guard parts.count == 3 else { continue }
                out.append(GitChange(path: String(parts[2]),
                                     added: Int(parts[0]) ?? 0,
                                     removed: Int(parts[1]) ?? 0))
            }
            DispatchQueue.main.async { completion(out) }
        }
    }

    /// Repo'nun dosya listesi. Takip edilenlerin yanında yoksayılmayan yeni
    /// dosyalar da var: az önce yaratılmış bir dosyanın adı da tıklanabilsin.
    func files(in cwd: String, completion: @escaping (FileIndex?) -> Void) {
        queue.async { [weak self] in
            let index = self?.index(for: cwd)
            DispatchQueue.main.async { completion(index) }
        }
    }

    /// Liste nadiren değişiyor; kısa ömürlü önbellek her fare gezinişinde
    /// `git ls-files` çalıştırmayı önlüyor.
    private func index(for cwd: String) -> FileIndex? {
        guard let root = run(["rev-parse", "--show-toplevel"], in: cwd)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !root.isEmpty else { return nil }
        if let cached = indexes[root], Date().timeIntervalSince(cached.at) < 15 {
            return cached.index
        }
        // Kökten çalıştırmak şart: `ls-files` alt dizinden çağrıldığında yalnızca
        // o dizinin altını listeliyor.
        guard let raw = run(["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                            in: root) else { return nil }
        var byName: [String: [String]] = [:]
        var seen = 0
        for entry in raw.split(separator: "\0") where !entry.isEmpty {
            let path = String(entry)
            byName[(path as NSString).lastPathComponent, default: []].append(path)
            seen += 1
            if seen >= 40_000 { break }   // devasa repoda liste ucu açık kalmasın
        }
        let index = FileIndex(root: root, byName: byName)
        indexes[root] = (index, Date())
        return index
    }

    /// `claude --worktree` her ajana kendi dalını veriyor; biriken worktree'leri
    /// görebilmek için (PLAN.md §7, Faz 4).
    func worktrees(in cwd: String, completion: @escaping ([Worktree]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let raw = self.run(["worktree", "list", "--porcelain"], in: cwd) ?? ""
            var out: [Worktree] = []
            var path: String?
            var branch: String?
            func flush() {
                if let path { out.append(Worktree(path: path, branch: branch)) }
                path = nil; branch = nil
            }
            for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("worktree ") {
                    flush()
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("branch ") {
                    branch = String(line.dropFirst("branch refs/heads/".count))
                } else if line.isEmpty {
                    flush()
                }
            }
            flush()
            DispatchQueue.main.async { completion(out) }
        }
    }

    // MARK: -

    private func probe(_ cwd: String) -> GitState? {
        guard run(["rev-parse", "--is-inside-work-tree"], in: cwd)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "true" else { return nil }

        let branch = run(["rev-parse", "--abbrev-ref", "HEAD"], in: cwd)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"

        let dirty = run(["status", "--porcelain"], in: cwd)?
            .split(separator: "\n").count ?? 0

        // Upstream yoksa komut hata verir; ahead 0 sayılır.
        let ahead = Int(run(["rev-list", "--count", "@{upstream}..HEAD"], in: cwd)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0

        return GitState(branch: branch, dirty: dirty, ahead: ahead)
    }

    private func run(_ arguments: [String], in cwd: String) -> String? {
        guard let gitPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        // Repo dışında çalışırken git üst dizinlere tırmanmasın; tavan ev dizini.
        //
        // Tavanı `cwd`'nin bir üstü yapmak ölçüldü ve yanlıştı: repo kökünün
        // ALTINDAKİ her dizinde git "repo yok" diyordu, yani alt klasöre `cd`
        // eden oturumda ne özet ne de fark listesi doluyordu. Ev dizini tavanken
        // alt dizinler kökü buluyor, ev dizininin kendisi bir repoysa (dotfiles)
        // o da yalnızca orada görünüyor, altındaki alakasız klasörlere sızmıyor.
        var env = ProcessInfo.processInfo.environment
        env["GIT_CEILING_DIRECTORIES"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
