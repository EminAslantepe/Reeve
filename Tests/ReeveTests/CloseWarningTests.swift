import XCTest
@testable import Reeve

/// Kapatma onayı iki şeyi söylemek zorunda: çalışan bir şey var mı, ve
/// kapatmanın ne yaptığı (SIGHUP — SIGKILL değil).
@MainActor
final class CloseWarningTests: XCTestCase {

    private func session(status: Session.Status = .idle,
                         origin: Session.Origin = .center,
                         children: [ChildProcess] = []) -> Session {
        let session = Session(name: "s", cwd: "/tmp", kind: .claude,
                              origin: origin, claudeSessionID: UUID(), launch: nil)
        session.status = status
        session.children = children
        return session
    }

    func testBusySessionWarnsThatWorkWillBeInterrupted() {
        let text = SidebarView.closeWarning(for: session(status: .busy))
        XCTAssertTrue(text.contains("çalışıyor"))
        XCTAssertTrue(text.contains("yarıda kesilecek"))
    }

    func testWaitingSessionIsCalledOutSeparately() {
        let text = SidebarView.closeWarning(for: session(status: .waiting("izin")))
        XCTAssertTrue(text.contains("izin bekliyor"))
    }

    func testChildProcessesAreNamedWhenSessionIsNotBusy() {
        let kids = [ChildProcess(id: 1, name: "node", residentBytes: 0, depth: 1),
                    ChildProcess(id: 2, name: "swift", residentBytes: 0, depth: 1)]
        let text = SidebarView.closeWarning(for: session(children: kids))
        XCTAssertTrue(text.contains("node"))
        XCTAssertTrue(text.contains("swift"))
    }

    /// Kapatmanın gerçekte ne yaptığı yazılmalı: SIGHUP, SIGKILL değil.
    func testTerminalSessionSaysSighupNotKill() {
        let text = SidebarView.closeWarning(for: session())
        XCTAssertTrue(text.contains("SIGHUP"))
        XCTAssertFalse(text.contains("SIGKILL"))
    }

    /// PTY'si bizde olmayan oturumda sinyal yok, sadece listeden kalkıyor.
    func testSessionWithoutTerminalOnlyLeavesTheList() {
        let text = SidebarView.closeWarning(for: session(origin: .external))
        XCTAssertFalse(text.contains("SIGHUP"))
        XCTAssertTrue(text.contains("listeden kaldırılacak"))
    }
}
