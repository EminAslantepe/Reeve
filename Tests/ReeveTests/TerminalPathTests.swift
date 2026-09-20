import XCTest
@testable import Reeve

/// Terminalde geçen metnin hangi durumda tıklanabilir bir dosyaya döndüğü.
final class TerminalPathTests: XCTestCase {

    private var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "reeve-path-" + UUID().uuidString
        let fm = FileManager.default
        try fm.createDirectory(atPath: root + "/alt", withIntermediateDirectories: true)
        fm.createFile(atPath: root + "/alt/dosya.swift", contents: Data("x".utf8))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    func testRelativePathResolvesAgainstTheGivenDirectory() {
        let url = TerminalPath.resolve("alt/dosya.swift", in: root)
        XCTAssertEqual(url?.lastPathComponent, "dosya.swift")
    }

    /// Aynı metin başka bir dizinde çözülmemeli: link oturumun bulunduğu yere
    /// göre anlam kazanıyor.
    func testTheSameTextIsNotAFileFromAnotherDirectory() {
        XCTAssertNil(TerminalPath.resolve("alt/dosya.swift", in: root + "/alt"))
    }

    func testAbsolutePathIgnoresTheWorkingDirectory() {
        XCTAssertNotNil(TerminalPath.resolve(root + "/alt/dosya.swift", in: "/bambaska"))
    }

    func testDotSegmentsAreFolded() {
        XCTAssertNotNil(TerminalPath.resolve("./alt/../alt/dosya.swift", in: root))
    }

    /// Terminalde dosya adına benzeyen bol metin geçiyor; karşılığı yoksa link
    /// de olmamalı.
    func testTextThatMerelyLooksLikeAFileIsRejected() {
        XCTAssertNil(TerminalPath.resolve("1.5", in: root))
        XCTAssertNil(TerminalPath.resolve("yok/olmayan.swift", in: root))
        XCTAssertNil(TerminalPath.resolve("", in: root))
    }

    /// Görüntüleyici dosya gösteriyor; klasör açmanın karşılığı yok.
    func testDirectoriesAreNotLinks() {
        XCTAssertNil(TerminalPath.resolve("alt", in: root))
    }

    /// Dizini bilmediğimiz oturumda göreli yol çözülemez — ev dizinine düşüp
    /// yanlış dosyayı açmaktansa link hiç çizilmesin.
    func testRelativePathNeedsAWorkingDirectory() {
        XCTAssertNil(TerminalPath.resolve("alt/dosya.swift", in: nil))
    }

    // MARK: - Repo içinde ada göre arama

    /// Ekrandaki asıl şikâyet: Claude "main.swift" yazıyor, dosya aslında
    /// `Sources/Reeve/main.swift`. Çalışma dizinine göre çözülemiyor.
    private var index: FileIndex {
        FileIndex(root: "/repo", byName: [
            "main.swift":  ["Sources/Reeve/main.swift"],
            "Theme.swift": ["Sources/Reeve/UI/Theme.swift"],
            "README.md":   ["README.md", "Design/README.md"],
        ])
    }

    func testBareFileNameFindsTheOnlyMatchInTheRepo() {
        XCTAssertEqual(TerminalPath.locate("main.swift", in: index)?.path,
                       "/repo/Sources/Reeve/main.swift")
    }

    /// İki dosya aynı adı taşıyorsa hangisinin kastedildiği bilinmiyor; yanlış
    /// dosyayı açmaktansa link hiç çizilmesin.
    func testAmbiguousNameIsNotLinked() {
        XCTAssertNil(TerminalPath.locate("README.md", in: index))
    }

    func testPartialPathIsMatchedFromTheRight() {
        XCTAssertEqual(TerminalPath.locate("UI/Theme.swift", in: index)?.path,
                       "/repo/Sources/Reeve/UI/Theme.swift")
        XCTAssertEqual(TerminalPath.locate("./Sources/Reeve/UI/Theme.swift", in: index)?.path,
                       "/repo/Sources/Reeve/UI/Theme.swift")
    }

    /// Ad tutuyor ama yol parçası tutmuyor: kastedilen başka bir dosya.
    func testPartialPathMustAgreeWithTheRealLocation() {
        XCTAssertNil(TerminalPath.locate("Model/Theme.swift", in: index))
    }

    func testUnknownNameIsNotLinked() {
        XCTAssertNil(TerminalPath.locate("1.5", in: index))
        XCTAssertNil(TerminalPath.locate("olmayan.swift", in: index))
    }

    /// Tam yollar ilk adımda zaten çözülüyor; burada ele alınmamalılar.
    func testAbsoluteAndTildePathsAreLeftToDirectResolution() {
        XCTAssertNil(TerminalPath.locate("/başka/main.swift", in: index))
        XCTAssertNil(TerminalPath.locate("~/main.swift", in: index))
    }

    func testTildeExpandsToHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let probe = home + "/.reeve-path-test"
        FileManager.default.createFile(atPath: probe, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(atPath: probe) }

        XCTAssertEqual(TerminalPath.resolve("~/.reeve-path-test", in: "/bambaska")?.path,
                       (probe as NSString).standardizingPath)
    }
}
