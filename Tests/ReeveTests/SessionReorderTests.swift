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

    func testLiveReorderHappensBeforeReleaseAndDoesNotOscillate() async {
        await MainActor.run {
            let (store, rows) = fixture()
            let drag = DragState()
            drag.begin(rows[0].id, store: store)
            drag.preview(over: rows[1], y: 20, height: 60)
            XCTAssertEqual(store.sessions.map(\.id), rows.map(\.id))
            drag.preview(over: rows[1], y: 40, height: 60)
            XCTAssertEqual(store.sessions.map(\.id), [rows[1].id, rows[0].id, rows[2].id])
            drag.preview(over: rows[1], y: 40, height: 60)
            XCTAssertEqual(store.sessions.map(\.id), [rows[1].id, rows[0].id, rows[2].id])
            XCTAssertEqual(drag.sessionID, rows[0].id)
            XCTAssertTrue(drag.canDrop(on: rows[0])) // Taşınmış boş kutuya bırakma geçerli.
            drag.acceptSidebarDrop()
            drag.end(accepted: true)
            XCTAssertEqual(store.sessions.map(\.id), [rows[1].id, rows[0].id, rows[2].id])
            XCTAssertFalse(drag.isActive)
        }
    }

    func testLiveReorderMovesUpAndCanReverseDirection() async {
        await MainActor.run {
            let (store, rows) = fixture()
            let drag = DragState()
            drag.begin(rows[2].id, store: store)
            drag.preview(over: rows[1], y: 10, height: 60)
            XCTAssertEqual(store.sessions.map(\.id), [rows[0].id, rows[2].id, rows[1].id])
            drag.preview(over: rows[1], y: 50, height: 60)
            XCTAssertEqual(store.sessions.map(\.id), rows.map(\.id))
            drag.end()
        }
    }

    func testCancelledDragRestoresOrderButPreservesSessionsAddedDuringDrag() async {
        await MainActor.run {
            let (store, rows) = fixture()
            let drag = DragState()
            drag.begin(rows[0].id, store: store)
            drag.preview(over: rows[2], y: 55, height: 60)
            let added = Session(name: "New", cwd: "/tmp/project", kind: .shell,
                                claudeSessionID: UUID(), launch: nil)
            store.add(added)
            drag.end()
            XCTAssertEqual(store.sessions.map(\.id), rows.map(\.id) + [added.id])
        }
    }

    func testTerminalDropDoesNotCommitTemporarySidebarOrder() async {
        await MainActor.run {
            let (store, rows) = fixture()
            let drag = DragState()
            drag.begin(rows[0].id, store: store)
            drag.preview(over: rows[2], y: 55, height: 60)
            store.insert(rows[0].id, at: 0)
            let panes = store.panes
            drag.end(accepted: true)
            XCTAssertEqual(store.sessions.map(\.id), rows.map(\.id))
            XCTAssertEqual(store.panes, panes)
        }
    }
}
