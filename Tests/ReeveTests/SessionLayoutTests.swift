import XCTest
@testable import Reeve

final class SessionLayoutTests: XCTestCase {
    @MainActor private func makeStore(_ count: Int) -> (SessionStore, [Session]) {
        let store = SessionStore()
        let sessions = (0..<count).map { index in
            Session(name: "Session \(index)", cwd: "/tmp", kind: .shell,
                    claudeSessionID: UUID(), launch: nil)
        }
        for session in sessions { store.add(session) }
        return (store, sessions)
    }

    func testDraggingVisibleSessionMovesItWithoutLeavingAnEmptyPane() async {
        await MainActor.run {
            let (store, sessions) = makeStore(2)
            store.setPaneCount(2)
            store.select(sessions[0].id, in: 0)
            store.insert(sessions[0].id, at: 2)
            XCTAssertEqual(store.panes, [sessions[1].id, sessions[0].id])
            XCTAssertEqual(store.selectedID, sessions[0].id)
        }
    }

    func testDraggingOnlyVisibleSessionKeepsSinglePane() async {
        await MainActor.run {
            let (store, sessions) = makeStore(1)
            store.insert(sessions[0].id, at: 1)
            XCTAssertEqual(store.panes, [sessions[0].id])
        }
    }

    func testDropReusesEmptyPane() async {
        await MainActor.run {
            let (store, sessions) = makeStore(2)
            store.setPaneCount(2)
            store.select(nil, in: 1)
            let hidden = sessions.first { store.pane(of: $0.id) == nil }!
            store.insert(hidden.id, at: 0)
            XCTAssertEqual(store.paneCount, 2)
            XCTAssertFalse(store.panes.contains(nil))
            XCTAssertEqual(store.selectedID, hidden.id)
        }
    }

    func testClosingEarlierPanePreservesFocusedSession() async {
        await MainActor.run {
            let (store, _) = makeStore(3)
            store.setPaneCount(3)
            store.focusPane(1)
            let focused = store.selectedID
            store.closePane(0)
            XCTAssertEqual(store.selectedID, focused)
            XCTAssertEqual(store.activePane, 0)
        }
    }

    func testSelectingSameSessionDoesNotRebuildTerminalLayout() async {
        await MainActor.run {
            let (store, sessions) = makeStore(1)
            var layouts = 0
            store.onLayout = { _ in layouts += 1 }
            store.select(sessions[0].id)
            XCTAssertEqual(layouts, 0)
        }
    }

    func testUnknownDragDoesNotChangeLayout() async {
        await MainActor.run {
            let (store, _) = makeStore(1)
            let before = store.panes
            store.insert(UUID(), at: 0)
            XCTAssertEqual(store.panes, before)
        }
    }
}
