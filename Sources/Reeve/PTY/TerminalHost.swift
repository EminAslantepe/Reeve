import AppKit
import WebKit

/// Kaynakların nerede olduğunu çözer.
/// `.app` içinde `Contents/Resources`, `swift run` sırasında `Bundle.module`.
///
/// Not: SwiftPM'in ürettiği `Bundle.module`, bundle'ı `Bundle.main.bundleURL`in
/// **yanında** arıyor — `.app` için bu `Reeve.app/Reeve_Reeve.bundle` demek,
/// yani `Contents/` dışı. O yüzden paketlenmiş halde `Bundle.module`a hiç
/// dokunmuyoruz; bulunamazsa `fatalError` atacağı için sıra önemli.
enum Res {
    static let root: URL = {
        let fm = FileManager.default
        func holdsPage(_ url: URL) -> Bool {
            fm.fileExists(atPath: url.appendingPathComponent("terminal.html").path)
        }
        if let u = Bundle.main.resourceURL, holdsPage(u) { return u }
        if let u = Bundle.module.resourceURL {
            let nested = u.appendingPathComponent("Resources")
            if holdsPage(nested) { return nested }
            if holdsPage(u) { return u }
        }
        fatalError("terminal.html bulunamadı")
    }()

    static var page: URL { root.appendingPathComponent("terminal.html") }
}

/// **Tek** WKWebView, içinde N adet xterm örneği (UI.md D1).
///
/// Her oturum için ayrı WKWebView açmak oturum başına 60–80 MB demekti;
/// burada tek WebKit süreci var, oturum başına maliyet birkaç MB.
final class TerminalHost: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    let webView: WKWebView

    var onInput: ((UUID, Data) -> Void)?
    var onResize: ((UUID, PtyProcess.Size) -> Void)?
    /// xterm örneği kuruldu ve ölçüldü — PTY bu boyutla başlatılmalı.
    var onCreated: ((UUID, PtyProcess.Size) -> Void)?
    var onReady: ((String) -> Void)?
    /// Kullanıcı bir panoya tıkladı — klavye odağı o panele geçmeli.
    var onFocusPane: ((UUID) -> Void)?

    private var isReady = false
    private var queued: [String] = []
    private var backlog: [UUID: Data] = [:]

    override init() {
        let controller = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        for name in ["input", "resize", "created", "ready", "focusPane"] {
            controller.add(self, name: name)
        }
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.underPageBackgroundColor = NSColor(Theme.terminal)
        webView.setValue(false, forKey: "allowsLinkPreview")
    }

    func load() {
        webView.loadFileURL(Res.page, allowingReadAccessTo: Res.root)
    }

    // MARK: - Swift → JS

    func create(_ id: UUID) { run("reeveCreate('\(id.uuidString)')") }
    func select(_ id: UUID) { run("reeveSelect('\(id.uuidString)')") }
    func dispose(_ id: UUID) { backlog[id] = nil; run("reeveDispose('\(id.uuidString)')") }
    func focus() { run("reeveFocus()") }

    /// Hangi oturumun hangi panelde duracağı. Boş slot için `null` gider.
    func layout(_ ids: [UUID?]) {
        let list = ids.map { $0.map { "'\($0.uuidString)'" } ?? "null" }.joined(separator: ",")
        run("reeveLayout([\(list)])")
    }

    /// Sürükleme sırasında panolar yer açsın. `nil` boşluğu kapatıyor.
    func preview(gapAt index: Int?) {
        run("reevePreview(\(index.map(String.init) ?? "null"))")
    }

    /// Panel tavanındayken hedef paneli vurgula.
    func highlight(_ id: UUID?) {
        run("reeveHighlight(\(id.map { "'\($0.uuidString)'" } ?? "null"))")
    }

    func find(_ query: String, forward: Bool) {
        guard let escaped = jsString(query) else { return }
        run("reeveFind(\(escaped), \(forward))")
    }

    func clearFind() { run("reeveClearFind()") }

    private func jsString(_ text: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return String(json.dropFirst().dropLast())   // ["x"] → "x"
    }

    /// PTY byte'larını ilgili xterm örneğine yazar.
    /// Sayfa hazır değilse oturum bazında biriktirir — açılış çıktısı kaybolmasın.
    func feed(_ id: UUID, _ data: Data) {
        guard isReady else {
            backlog[id, default: Data()].append(data)
            return
        }
        // base64 alfabesi tek tırnak içinde güvenli.
        run("reeveWrite('\(id.uuidString)','\(data.base64EncodedString())')")
    }

    private func run(_ js: String) {
        guard isReady else { queued.append(js); return }
        webView.evaluateJavaScript(js)
    }

    // MARK: - JS → Swift

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "ready":
            isReady = true
            let renderer = (message.body as? [String: Any])?["renderer"] as? String ?? "?"
            let pending = queued
            queued.removeAll()
            for js in pending { webView.evaluateJavaScript(js) }
            onReady?(renderer)

        case "created":
            guard let (id, size) = parse(message.body) else { return }
            onCreated?(id, size)
            if let waiting = backlog.removeValue(forKey: id) { feed(id, waiting) }

        case "resize":
            guard let (id, size) = parse(message.body) else { return }
            onResize?(id, size)

        case "focusPane":
            if let body = message.body as? [String: Any],
               let id = (body["id"] as? String).flatMap(UUID.init(uuidString:)) {
                onFocusPane?(id)
            }

        case "input":
            guard let body = message.body as? [String: Any],
                  let id = (body["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let b64 = body["b64"] as? String,
                  let data = Data(base64Encoded: b64) else { return }
            onInput?(id, data)

        default:
            break
        }
    }

    private func parse(_ body: Any) -> (UUID, PtyProcess.Size)? {
        guard let dict = body as? [String: Any],
              let id = (dict["id"] as? String).flatMap(UUID.init(uuidString:)),
              let cols = dict["cols"] as? Int, let rows = dict["rows"] as? Int,
              cols > 0, rows > 0 else { return nil }
        return (id, .init(cols: UInt16(cols), rows: UInt16(rows)))
    }

    // MARK: - Ağa çıkış yok

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == "file" ? .allow : .cancel)
    }
}
