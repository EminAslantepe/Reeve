import AppKit
import Observation
import SwiftUI

/// Sidebar'dan sürüklenen oturumu takip eder ve nereye bırakılacağını canlı tutar.
@MainActor
@Observable
final class DragState {
    private(set) var sessionID: Session.ID?
    /// Panellerin arasında açılacak boşluğun yeri. `nil` = terminal alanı dışında.
    private(set) var insertion: Int?
    /// Sidebar'da satırın hangi satırın önüne gireceği.
    private(set) var beforeRow: Session.ID?

    var isActive: Bool { sessionID != nil }

    /// Bırakma katmanı AppKit tarafında bir `NSHostingView` içinde yaşıyor ve o
    /// sınırda `@Observable` değişimi görünüme yansımıyor (ölçüldü: katman ancak
    /// elle yeniden kurulunca güncelleniyordu). Bu yüzden değişim açıkça haber
    /// veriliyor.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var local: Any?
    @ObservationIgnored private var global: Any?
    @ObservationIgnored private var watchdog: Timer?

    func begin(_ id: Session.ID) {
        guard sessionID != id else { return }
        sessionID = id
        insertion = nil
        beforeRow = nil
        startWatching()
        onChange?()
    }

    func hover(insertion index: Int?) {
        guard insertion != index else { return }
        insertion = index
        onChange?()
    }

    func hover(before row: Session.ID?) {
        guard beforeRow != row else { return }
        beforeRow = row
        onChange?()
    }

    func end() {
        guard sessionID != nil else { return }
        sessionID = nil
        insertion = nil
        beforeRow = nil
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
            Task { @MainActor in self?.end() }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            finish(); return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in finish() }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons == 0 else { return }
                self?.end()
            }
        }
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
