import XCTest
@testable import Reeve

final class SessionReorderTests: XCTestCase {
    @MainActor private func fixture() -> (SessionStore, [Session]) {
        let store = SessionStore()
        let rows = (0..<3).map {
            Session(name: "Session \($0)", cwd: "/tmp/project", kind: .shell,
                    claudeSessionID: UUID(), launch: nil)
        }
        rows.forEach { store.add($0) }
        return (store, rows)
    }

    func testFirstRowCanBeDroppedBelowLastWithoutChangingTerminalLayout() async {
        await MainActor.run {
            let (store, rows) = fixture()
            let panes = store.panes
            let selected = store.selectedID
            var layoutCalls = 0
            store.onLayout = { _ in layoutCalls += 1 }
            let placement = SessionReorderDelegate.placement(at: 55, height: 60)
            XCTAssertTrue(store.move(rows[0].id, relativeTo: rows[2].id, placement: placement))
            XCTAssertEqual(store.sessions.map(\.id), [rows[1].id, rows[2].id, rows[0].id])
            XCTAssertEqual(store.panes, panes)
            XCTAssertEqual(store.selectedID, selected)
            XCTAssertEqual(layoutCalls, 0)
        }
    }

    func testLastRowCanStillBeDroppedAboveFirst() async {
        await MainActor.run {
            let (store, rows) = fixture()
            let placement = SessionReorderDelegate.placement(at: 5, height: 60)
            XCTAssertTrue(store.move(rows[2].id, relativeTo: rows[0].id, placement: placement))
            XCTAssertEqual(store.sessions.map(\.id), [rows[2].id, rows[0].id, rows[1].id])
        }
    }

    func testMovingDownOnePositionAndBackDoesNotSkipARow() async {
        await MainActor.run {
            let (store, rows) = fixture()
            store.move(rows[0].id, relativeTo: rows[1].id, placement: .after)
            XCTAssertEqual(store.sessions.map(\.id), [rows[1].id, rows[0].id, rows[2].id])
            store.move(rows[0].id, relativeTo: rows[1].id, placement: .before)
            XCTAssertEqual(store.sessions.map(\.id), rows.map(\.id))
        }
    }

    func testNoOpAndInvalidDropsPreserveOrder() async {
        await MainActor.run {
            let (store, rows) = fixture()
            XCTAssertFalse(store.move(rows[1].id, relativeTo: rows[0].id, placement: .after))
            XCTAssertFalse(store.move(rows[0].id, relativeTo: rows[0].id, placement: .after))
            XCTAssertFalse(store.move(rows[0].id, relativeTo: UUID(), placement: .before))
            XCTAssertFalse(store.move(UUID(), relativeTo: rows[0].id, placement: .after))
            XCTAssertEqual(store.sessions.map(\.id), rows.map(\.id))
        }
    }

    func testDifferentFolderOrWaitingSectionIsNotAReorderTarget() async {
        await MainActor.run {
            let (store, rows) = fixture()
            rows[1].cwd = "/tmp/other"
            rows[2].status = .waiting("Onay")
            XCTAssertFalse(store.move(rows[0].id, relativeTo: rows[1].id, placement: .after))
            XCTAssertFalse(store.move(rows[0].id, relativeTo: rows[2].id, placement: .before))
            XCTAssertEqual(store.sessions.map(\.id), rows.map(\.id))
        }
    }

    func testMouseUpKeepsSourceAvailableForDropAndOldExitKeepsCurrentTarget() async {
        await MainActor.run {
            let drag = DragState()
            let source = UUID(), oldTarget = UUID(), newTarget = UUID()
            drag.begin(source)
            defer { drag.end() }
            drag.hover(row: oldTarget, placement: .before)
            drag.hover(row: newTarget, placement: .after)
            drag.leave(row: oldTarget)
            XCTAssertEqual(drag.rowTarget?.id, newTarget)
            XCTAssertEqual(drag.rowTarget?.placement, .after)
            drag.scheduleEnd()
            XCTAssertEqual(drag.sessionID, source)
        }
    }
}
