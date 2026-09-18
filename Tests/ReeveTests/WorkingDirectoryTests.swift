import XCTest
@testable import Reeve

/// Gösterilen dizin kabuğun gerçek çalışma dizini olmalı, açılış dizini değil.
@MainActor
final class WorkingDirectoryTests: XCTestCase {

    private func session() -> Session {
        Session(name: "s", cwd: "/tmp/acilis", kind: .shell,
                claudeSessionID: UUID(), launch: nil)
    }

    func testCurrentCwdFallsBackToLaunchDirectoryUntilTheShellReports() {
        let session = session()
        XCTAssertEqual(session.currentCwd, "/tmp/acilis")
        session.liveCwd = "/tmp/sonra"
        XCTAssertEqual(session.currentCwd, "/tmp/sonra")
    }

    /// Gruplama açılış dizinine bakmaya devam etmeli: `cd` yapınca satırlar
    /// gruplar arasında zıplamasın.
    func testGroupingStaysOnTheLaunchDirectory() {
        let store = SessionStore()
        let session = session()
        store.add(session)
        session.liveCwd = "/tmp/bambaska"
        XCTAssertEqual(store.groups.map(\.cwd), ["/tmp/acilis"])
    }

    func testTildeShortensHomeButNotLookalikePaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(Session.tilde(home), "~")
        XCTAssertEqual(Session.tilde(home + "/Desktop"), "~/Desktop")
        // "<home>x" ev dizini DEĞİL; kısaltılmamalı.
        XCTAssertEqual(Session.tilde(home + "x"), home + "x")
    }

    /// Kendi süreçlerimizin dizinini çekirdekten okuyabiliyor muyuz.
    func testWorkingDirectoryIsReadableForOurOwnProcess() {
        let path = ProcessTree.workingDirectory(of: getpid())
        XCTAssertNotNil(path)
        XCTAssertTrue(path?.hasPrefix("/") == true)
    }
}
