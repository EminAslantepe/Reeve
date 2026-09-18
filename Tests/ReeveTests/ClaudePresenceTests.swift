import XCTest
@testable import Reeve

/// Claude simgesi şablondan değil, gerçekten çalışan süreçten geliyor.
/// Şablon `kind` hiç değişmiyordu: kabukta elle `claude` yazınca simge
/// gelmiyor, Claude'dan çıkıp kabuğa düşünce gitmiyordu.
@MainActor
final class ClaudePresenceTests: XCTestCase {

    private func record(pid: Int32, session: UUID, background: Bool = false) -> String {
        background
        ? """
          { "id": "ab12cd34", "cwd": "/tmp", "kind": "background",
            "sessionId": "\(session.uuidString)", "name": "ajan", "state": "running" }
          """
        : """
          { "pid": \(pid), "cwd": "/tmp", "kind": "interactive",
            "sessionId": "\(session.uuidString)", "name": "x", "status": "idle" }
          """
    }

    private func records(_ json: String) -> [AgentRecord] {
        AgentRecord.list(from: Data("[\(json)]".utf8)) ?? []
    }

    private func store(with session: Session) -> SessionStore {
        let store = SessionStore()
        store.add(session)
        return store
    }

    private func shellSession() -> Session {
        Session(name: "kabuk", cwd: "/tmp", kind: .shell,
                claudeSessionID: UUID(), launch: nil)
    }

    /// Kabuk oturumunda elle `claude` açıldı: çocuk pid canlı listede.
    func testClaudeStartedInsideAShellTurnsTheIconOn() {
        let session = shellSession()
        let store = store(with: session)
        store.apply(records(record(pid: 4242, session: UUID())))
        XCTAssertFalse(session.claudeIsLive, "süreç ağacı boşken canlı sayılmamalı")

        session.children = [ChildProcess(id: 4242, name: "node", residentBytes: 0, depth: 1)]
        store.applyChildren([:])
        XCTAssertTrue(session.claudeIsLive, "canlı pid çocuklar arasında, simge yanmalı")
    }

    /// Claude'dan çıkıldı: pid artık Katman 1'de yok.
    func testLeavingClaudeTurnsTheIconOff() {
        let session = shellSession()
        session.children = [ChildProcess(id: 4242, name: "node", residentBytes: 0, depth: 1)]
        let store = store(with: session)
        store.apply(records(record(pid: 4242, session: UUID())))
        XCTAssertTrue(session.claudeIsLive)

        store.apply([])
        XCTAssertFalse(session.claudeIsLive, "canlı pid kalmadı, simge sönmeli")
    }

    /// Arka plan ajanının terminal süreci yok; onun pid'i simgeyi yakmamalı.
    func testBackgroundAgentRecordsDoNotLightTheIcon() {
        let session = shellSession()
        session.children = [ChildProcess(id: 4242, name: "node", residentBytes: 0, depth: 1)]
        let store = store(with: session)
        store.apply(records(record(pid: 0, session: UUID(), background: true)))
        XCTAssertFalse(session.claudeIsLive)
    }
}
