import XCTest
@testable import Reeve

/// `claude agents --json --all` çıktısı iki farklı kayıt şekli taşıyor:
/// etkileşimli oturumda `pid` + `status`, arka plan ajanında `id` + `state`.
/// İkincisi alanları zorunlu sanan çözücüyü düşürüyordu ve `try?` bütün diziyi
/// attığı için Katman 1 tamamen susuyordu — dışarıda açılan oturumlar dahil.
final class AgentRecordTests: XCTestCase {
    private let interactive = """
    { "pid": 33527, "cwd": "/tmp", "kind": "interactive", "startedAt": 1789607127563,
      "sessionId": "4A76DE36-DEE0-4083-AFE3-A2F0ECFF91E6", "name": "deneme1", "status": "idle" }
    """
    private let background = """
    { "id": "e8e488e8", "cwd": "/tmp", "kind": "background", "startedAt": 1789606772073,
      "sessionId": "E8E488E8-7608-4E62-B14E-8936F9B84875", "name": "ajan", "state": "done" }
    """

    private func list(_ json: String) -> [AgentRecord]? {
        AgentRecord.list(from: Data(json.utf8))
    }

    func testBackgroundRecordWithoutPidDoesNotDropTheWholeList() {
        let records = list("[\(interactive), \(background)]")
        XCTAssertEqual(records?.count, 2)
        XCTAssertEqual(records?.first?.name, "deneme1")
        XCTAssertEqual(records?.last?.pid, nil)
        XCTAssertTrue(records?.last?.isBackground == true)
    }

    func testUnknownRecordShapeIsSkippedWithoutLosingSiblings() {
        let records = list("[\(interactive), { \"beklenmedik\": true }]")
        XCTAssertEqual(records?.count, 1)
        XCTAssertEqual(records?.first?.name, "deneme1")
    }

    func testOutputThatIsNotAnArraySkipsTheRound() {
        XCTAssertNil(list("{ \"error\": \"nope\" }"))
        XCTAssertEqual(list("[]")?.count, 0)
    }

    /// Biten arka plan ajanı `.exited` olmamalı: `apply` ölmüş oturumun kaydını
    /// tüketmeden atlıyor, o kayıt her turda yeniden eklenirdi.
    func testFinishedBackgroundAgentIsNotMarkedOver() {
        let record = list("[\(background)]")?.first
        XCTAssertEqual(record?.mappedStatus, .idle)
        XCTAssertFalse(record?.mappedStatus.isOver == true)
    }
}
