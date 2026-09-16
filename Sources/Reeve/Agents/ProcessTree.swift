import Darwin
import Foundation

/// Katman 4 — PTY'nin altındaki gerçek süreçler (PLAN.md §3).
/// Claude'un arka planda başlattığı işler (`npm run dev`, test runner) buradan çıkıyor.
///
/// Not: `proc_listchildpids` macOS'ta çocukları güvenilir biçimde vermiyor
/// (ölçüldü: iki `sleep` çocuğu olan bir kabuk için boş döndü). Bu yüzden tüm
/// pid listesi bir kez alınıp `ppid`'lerden ağaç kuruluyor — ~200 süreçte
/// milisaniyeler sürüyor.
struct ChildProcess: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let residentBytes: UInt64
    let depth: Int

    var memoryLabel: String {
        let mb = Double(residentBytes) / 1024 / 1024
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

final class ProcessTree {

    /// Ana kuyrukta: PTY kök pid'i → altındaki süreçler.
    var onUpdate: (([pid_t: [ChildProcess]]) -> Void)?

    private let queue = DispatchQueue(label: "io.reeve.proctree")
    private var last: [pid_t: [ChildProcess]] = [:]

    /// Gösterilmesi anlamsız ara katmanlar — kullanıcı `npm run dev` görmek istiyor,
    /// onu taşıyan kabuğu değil.
    private static let hidden: Set<String> = ["bash", "zsh", "sh", "login", "sleep"]

    func refresh(roots: [pid_t]) {
        guard !roots.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let all = Self.snapshot()
            var byParent: [pid_t: [Entry]] = [:]
            for entry in all { byParent[entry.ppid, default: []].append(entry) }

            var result: [pid_t: [ChildProcess]] = [:]
            for root in roots {
                var found: [ChildProcess] = []
                Self.walk(root, in: byParent, depth: 0, into: &found)
                if !found.isEmpty { result[root] = found }
            }
            guard result != self.last else { return }
            self.last = result
            DispatchQueue.main.async { self.onUpdate?(result) }
        }
    }

    // MARK: -

    private struct Entry {
        let pid: pid_t
        let ppid: pid_t
        let name: String
        let resident: UInt64
    }

    private static func walk(_ pid: pid_t,
                             in byParent: [pid_t: [Entry]],
                             depth: Int,
                             into out: inout [ChildProcess]) {
        guard depth < 6, out.count < 24 else { return }
        for child in (byParent[pid] ?? []).sorted(by: { $0.pid < $1.pid }) {
            let interesting = !hidden.contains(child.name)
            if interesting {
                out.append(ChildProcess(id: child.pid,
                                        name: child.name,
                                        residentBytes: child.resident,
                                        depth: depth))
            }
            // Gizlenen kabukların altına inmeye devam: asıl iş orada.
            walk(child.pid, in: byParent, depth: interesting ? depth + 1 : depth, into: &out)
        }
    }

    private static func snapshot() -> [Entry] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }

        var out: [Entry] = []
        out.reserveCapacity(Int(bytes) / MemoryLayout<pid_t>.size)
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size) where pid > 0 {
            var short = proc_bsdshortinfo()
            guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &short,
                               Int32(MemoryLayout<proc_bsdshortinfo>.size)) > 0 else { continue }
            let name = withUnsafeBytes(of: short.pbsi_comm) { raw -> String in
                guard let base = raw.baseAddress else { return "?" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
            var task = proc_taskinfo()
            let ok = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task,
                                  Int32(MemoryLayout<proc_taskinfo>.size)) > 0
            out.append(Entry(pid: pid,
                             ppid: pid_t(short.pbsi_ppid),
                             name: name,
                             resident: ok ? task.pti_resident_size : 0))
        }
        return out
    }
}
