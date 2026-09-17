import AppKit
import Observation
import SwiftUI

/// Sidebar'dan sürüklenen oturumu takip eder ve nereye bırakılacağını canlı tutar.
@MainActor
@Observable
final class DragState {
    private(set) var sessionID: Session.ID?
    struct RowTarget: Equatable {
        let id: Session.ID
        let placement: SessionStore.RowPlacement
    }
    /// İmlecin bulunduğu satır ve satırın üst/alt yarısı.
    private(set) var rowTarget: RowTarget?

    var isActive: Bool { sessionID != nil }

    /// Bırakma katmanı AppKit tarafında bir `NSHostingView` içinde yaşıyor ve o
    /// sınırda `@Observable` değişimi görünüme yansımıyor (ölçüldü: katman ancak
    /// elle yeniden kurulunca güncelleniyordu). Bu yüzden değişim açıkça haber
    /// veriliyor.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var local: Any?
    @ObservationIgnored private var global: Any?
    @ObservationIgnored private var watchdog: Timer?
    @ObservationIgnored private var pendingEnd: DispatchWorkItem?

    func begin(_ id: Session.ID) {
        guard sessionID != id else { return }
        pendingEnd?.cancel()
        pendingEnd = nil
        sessionID = id
        rowTarget = nil
        startWatching()
        onChange?()
    }

    func hover(row: Session.ID, placement: SessionStore.RowPlacement) {
        guard isActive else { return }
        let target = RowTarget(id: row, placement: placement)
        if rowTarget != target { rowTarget = target }
    }

    func leave(row: Session.ID) {
        if rowTarget?.id == row { rowTarget = nil }
    }

    // Mouse-up, bırakma temsilcisinden önce gelebilir. Kaynak kimliğini o
    // sırada silmek geçerli bırakmayı iptal edip kartı eski yerine uçurur.
    func scheduleEnd() {
        guard isActive, pendingEnd == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.end() }
        pendingEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func end() {
        guard sessionID != nil else { return }
        sessionID = nil
        rowTarget = nil
        pendingEnd?.cancel()
        pendingEnd = nil
        stopWatching()
        onChange?()
    }

    // MARK: - Sürüklemenin bittiğini anlamak

    /// SwiftUI iptal edilen sürükleme için geri çağrı vermiyor.
    ///
    /// `addGlobalMonitorForEvents` tek başına yetmiyordu: o monitör yalnızca
    /// **başka** uygulamalara giden olayları görüyor, fare kendi penceremizde
    /// bırakıldığında hiç tetiklenmiyor — bırakma bölgeleri ekranda kalıyordu.
    /// Bu yüzden asıl güvence `NSEvent.pressedMouseButtons` yoklaması; monitörler
    /// yalnızca tepkiyi hızlandırıyor.
    private func startWatching() {
        guard watchdog == nil else { return }
        let finish: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.scheduleEnd() }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            finish(); return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in finish() }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons == 0 else { return }
                self?.scheduleEnd()
            }
        }
        watchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopWatching() {
        watchdog?.invalidate()
        watchdog = nil
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
        local = nil
        global = nil
    }
}
