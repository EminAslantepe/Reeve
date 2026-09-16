import Foundation

/// `forkpty()` ile bir süreç başlatır, PTY'sini dinler, çıktısını **toplu** halde verir.
///
/// İki kural buradan çıkıyor (PLAN.md §2.1):
/// - Okuma push: `DispatchSource` fd'yi dinler, boşta CPU yakılmaz.
/// - Çıktı ~8 ms'de bir tek parça halinde yukarı verilir; her `read` için ayrı
///   `evaluateJavaScript` köprüyü boğardı.
final class PtyProcess {

    struct Size: Equatable {
        var cols: UInt16
        var rows: UInt16
    }

    enum Failure: Error, CustomStringConvertible {
        case forkFailed(Int32)
        var description: String {
            switch self {
            case .forkFailed(let e): return "forkpty(): \(String(cString: strerror(e)))"
            }
        }
    }

    private(set) var masterFD: Int32 = -1
    private(set) var pid: pid_t = -1

    /// Ana kuyrukta, biriktirilmiş veriyle çağrılır.
    var onOutput: ((Data) -> Void)?
    /// Ana kuyrukta. Pozitif = exit kodu, negatif = öldüren sinyal.
    var onExit: ((Int32) -> Void)?

    private let ioQueue = DispatchQueue(label: "io.reeve.pty")
    private var readSource: DispatchSourceRead?
    private var pending = Data()
    private var flushScheduled = false
    private var finished = false

    private static let flushInterval = DispatchTimeInterval.milliseconds(8)
    private static let maxPending = 8 << 20   // 8 MB: sel gibi çıktıda tavan

    // MARK: - Başlatma

    func start(executable: String,
               args: [String] = [],
               cwd: String,
               env: [String: String],
               size: Size) throws {

        // fork'tan SONRA Swift ayırma yapmak güvenli değil; C dizilerini önce kur.
        let pathC = strdup(executable)
        let cwdC = strdup(cwd)
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + args).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)

        var ws = winsize(ws_row: size.rows, ws_col: size.cols, ws_xpixel: 0, ws_ypixel: 0)
        var fd: Int32 = -1
        let child = forkpty(&fd, nil, nil, &ws)

        if child == 0 {
            // --- çocuk: sadece async-signal-safe çağrılar ---
            if let cwdC { _ = chdir(cwdC) }
            execve(pathC, &argv, &envp)
            _exit(127)
        }

        free(pathC); free(cwdC)
        for p in argv where p != nil { free(p) }
        for p in envp where p != nil { free(p) }

        guard child > 0 else { throw Failure.forkFailed(errno) }

        pid = child
        masterFD = fd
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        startReading()
    }

    // MARK: - Okuma

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: ioQueue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            close(self.masterFD)
            self.masterFD = -1
        }
        readSource = source
        source.resume()
    }

    private func drain() {
        var buf = [UInt8](repeating: 0, count: 64 << 10)
        while true {
            let n = read(masterFD, &buf, buf.count)
            if n > 0 {
                pending.append(contentsOf: buf[0..<n])
                if pending.count >= Self.maxPending { break }
            } else if n == 0 {
                finish(); return                      // EOF: çocuk kapandı
            } else {
                switch errno {
                case EINTR: continue
                case EAGAIN: break
                default: finish(); return             // EIO de buraya düşer
                }
                break
            }
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled, !pending.isEmpty else { return }
        flushScheduled = true
        ioQueue.asyncAfter(deadline: .now() + Self.flushInterval) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.flushNow()
        }
    }

    private func flushNow() {
        guard !pending.isEmpty else { return }
        let chunk = pending
        pending.removeAll(keepingCapacity: true)
        DispatchQueue.main.async { self.onOutput?(chunk) }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        flushNow()
        readSource?.cancel()

        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
        // WIFEXITED/WEXITSTATUS makroları Swift'e gelmiyor, elle açıyoruz.
        let signalled = status & 0o177
        let code = signalled == 0 ? (status >> 8) & 0xff : -signalled

        DispatchQueue.main.async { self.onExit?(code) }
    }

    // MARK: - Yazma / boyut

    func write(_ data: Data) {
        guard masterFD >= 0, !data.isEmpty else { return }
        let fd = masterFD
        ioQueue.async {
            data.withUnsafeBytes { raw in
                guard var p = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                var left = raw.count
                while left > 0 {
                    let n = Darwin.write(fd, p, left)
                    if n > 0 {
                        p += n; left -= n
                    } else if errno == EINTR || errno == EAGAIN {
                        usleep(500); continue
                    } else {
                        return
                    }
                }
            }
        }
    }

    /// Boyut zinciri: addon-fit ölçtü → burası → çekirdek SIGWINCH atar → TUI yeniden çizer.
    func resize(to size: Size) {
        guard masterFD >= 0 else { return }
        var ws = winsize(ws_row: size.rows, ws_col: size.cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    /// Nazik kapanış: SIGHUP, terminal kapandı demek.
    func hangUp() {
        guard pid > 0 else { return }
        Darwin.kill(pid, SIGHUP)
    }

    /// Son çare.
    func kill() {
        guard pid > 0 else { return }
        Darwin.kill(pid, SIGKILL)
    }
}
