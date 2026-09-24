import AppKit
import XCTest
@testable import Reeve

final class TerminalBackgroundTests: XCTestCase {
    @MainActor
    func testInitialFrameCanBePreparedBeforeWindowIsVisible() async {
        _ = NSApplication.shared
        let host = TerminalHost()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host.webView
        let prepared = expectation(description: "Terminal rendered offscreen")
        let id = UUID()
        host.onReady = { _ in
            host.create(id)
            host.layout([id])
            host.select(id)
        }
        host.prepareForDisplay { result in
            XCTAssertFalse(window.isVisible)
            switch result {
            case .success(let image):
                XCTAssertGreaterThan(image.size.width, 0)
                XCTAssertGreaterThan(image.size.height, 0)
                if let data = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: data),
                   let color = bitmap.colorAt(x: bitmap.pixelsWide / 2,
                                              y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB) {
                    XCTAssertEqual(color.redComponent, 11.0 / 255, accuracy: 0.01)
                    XCTAssertEqual(color.greenComponent, 11.0 / 255, accuracy: 0.01)
                    XCTAssertEqual(color.blueComponent, 11.0 / 255, accuracy: 0.01)
                    XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
                } else { XCTFail("İlk görüntü okunamadı") }
            case .failure(let error):
                XCTFail("İlk görüntü üretilemedi: \(error)")
            }
            host.webView.evaluateJavaScript("document.querySelector('.pane').dataset.active") { value, error in
                XCTAssertNil(error)
                XCTAssertEqual(value as? String, "1", "İlk görüntü terminal yerleşimini beklemeli")
                prepared.fulfill()
            }
        }
        host.load()
        await fulfillment(of: [prepared], timeout: 15)
        window.orderOut(nil)
    }

    func testNativeBackgroundSurvivesWebKitLayerUpdates() async {
        await MainActor.run {
            _ = NSApplication.shared
            let host = TerminalHost()
            let view = host.webView
            view.appearance = NSAppearance(named: .darkAqua)
            view.wantsLayer = true
            let expected = NSColor(Theme.terminal).usingColorSpace(.sRGB)!

            // Panel kapandığında WebKit'in mevcut içeriği henüz büyümemiştir;
            // açığa çıkan yerel katman gri controlBackgroundColor olmamalı.
            for width: CGFloat in [942, 1114, 942, 1114] {
                view.setFrameSize(NSSize(width: width, height: 670))
                view.updateLayer()
                guard let cgColor = view.layer?.backgroundColor,
                      let actual = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
                    return XCTFail("Terminalin yerel arka planı yok")
                }
                XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.001)
                XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.001)
                XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.001)
                XCTAssertEqual(actual.alphaComponent, 1, accuracy: 0.001)
            }
        }
    }
}
