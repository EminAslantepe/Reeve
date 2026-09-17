import XCTest
@testable import Reeve

/// Reeve'in açmadığı oturumlar sidebar'a girmiyor: ne başka terminalde elle
/// açılmış olanlar ne de arka plan ajanları. Katman 1 yoklaması yalnızca kendi
/// oturumlarımızın durumunu tazeliyor.
final class SessionDiscoveryTests: XCTestCase {

    private func records(_ json: String) -> [AgentRecord] {
        AgentRecord.list(from: Data(json.utf8)) ?? []
    }

    @MainActor private func makeStore(ours id: UUID) -> SessionStore {
        let store = SessionStore()
        store.add(Session(name: "bizimki", cwd: "/tmp", kind: .claude,
                          claudeSessionID: id, launch: nil))
        return store
    }

    func testForeignRecordsAreNotAdopted() async {
        await MainActor.run {
            let ours = UUID()
            let store = makeStore(ours: ours)
            store.apply(records("""
            [{ "pid": 1, "cwd": "/tmp", "kind": "interactive",
               "sessionId": "\(ours.uuidString)", "name": "bizimki", "status": "idle" },
             { "pid": 2, "cwd": "/tmp", "kind": "interactive",
               "sessionId": "\(UUID().uuidString)", "name": "harici", "status": "idle" },
             { "id": "ab12cd34", "cwd": "/tmp", "kind": "background",
               "sessionId": "\(UUID().uuidString)", "name": "ajan", "state": "running" }]
            """))
            XCTAssertEqual(store.sessions.count, 1)
            XCTAssertEqual(store.sessions.first?.name, "bizimki")
        }
    }

    func testOurOwnSessionStillGetsItsStatusRefreshed() async {
        await MainActor.run {
            let ours = UUID()
            let store = makeStore(ours: ours)
            store.apply(records("""
            [{ "pid": 1, "cwd": "/tmp", "kind": "interactive",
               "sessionId": "\(ours.uuidString)", "name": "bizimki", "status": "busy" }]
            """))
            XCTAssertEqual(store.sessions.first?.status, .busy)
            XCTAssertEqual(store.sessions.first?.reportedPID, 1)
        }
    }
}
