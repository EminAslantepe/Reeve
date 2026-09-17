import XCTest
@testable import Reeve

final class SessionRenameTests: XCTestCase {
    func testRenameSurvivesAgentPollingWithoutChangingSelection() async {
        await MainActor.run {
            let store = SessionStore()
            let session = Session(name: "old", cwd: "/tmp", kind: .claude,
                                  claudeSessionID: UUID(), launch: nil)
            store.add(session)
            XCTAssertTrue(store.rename(session, to: "  Arayüz  "))
            let records = AgentRecord.list(from: Data("""
            [{"pid": 1, "cwd": "/tmp", "kind": "interactive",
              "sessionId": "\(session.claudeSessionID)", "name": "old", "status": "busy"}]
            """.utf8))!
            store.apply(records)
            XCTAssertEqual(session.name, "Arayüz")
            XCTAssertEqual(session.status, .busy)
            XCTAssertEqual(store.selectedID, session.id)
            XCTAssertFalse(store.rename(session, to: " \n "))
            XCTAssertEqual(session.name, "Arayüz")
        }
    }

    func testSavedRenameIsRestoredAndOldSaveFormatStillDecodes() async throws {
        let saved = SavedSession(name: "UI", cwd: "/tmp", isClaude: true,
                                 claudeSessionID: UUID().uuidString, customName: "UI")
        let decoded = try JSONDecoder().decode(SavedSession.self, from: JSONEncoder().encode(saved))
        let old = try JSONDecoder().decode(SavedSession.self, from: Data("""
        {"name":"old","cwd":"/tmp","isClaude":true,"claudeSessionID":"\(UUID())"}
        """.utf8))
        XCTAssertNil(old.customName)
        await MainActor.run {
            let restored = SessionFactory.resume(decoded)
            XCTAssertEqual(restored.name, "UI")
            XCTAssertEqual(restored.customName, "UI")
        }
    }
}
