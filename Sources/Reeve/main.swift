import AppKit
import SwiftUI

/// Uygulamanın omurgası: pencere, menü, araç çubuğu ve tüm katmanların kablolaması.
@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSToolbarDelegate {

    private let store = SessionStore()
    private let host = TerminalHost()
    private let registry = AgentRegistry()
    private let gitProbe = GitProbe()
    private let notifier = Notifier()
    private let hooks = HookBridge()
    private let processTree = ProcessTree()
    private let transcript = TranscriptTail()
    private let inspector = InspectorModel()
    private let drag = DragState()

    private var window: NSWindow!
    private var sheet: NSWindow?
    private var palette: NSWindow?
    // Somut tip: `AnyView` sarmalayıcısı SwiftUI'nin görünüm kimliğini siliyor
    // ve her atamada ağacı baştan kurduruyor.
    private var cardView: NSHostingView<PaneOverlay>!
    private var findView: NSHostingView<FindBar>!
    private var sidebarItem: NSSplitViewItem!
    private var sidebarSplitView: SidebarSplitView!
    private var expandedSidebarWidth = Theme.sidebarWidth
    private var filesItem: NSSplitViewItem!
    private var viewerItem: NSSplitViewItem!
    private let viewer = ViewerModel()

    /// Sağ üstteki `+N −M`. Yoklamada tazeleniyor ama her turda değil:
    /// `git diff --numstat` büyük repoda pahalı.
    private var gitSummary: (added: Int, removed: Int)?
    private var gitSummaryCwd: String?
    private var gitSummaryAt = Date.distantPast
    private weak var gitButton: NSButton?
    private weak var gitChip: NSView?
    private var inspectorItem: NSSplitViewItem!

    private var tier = SidebarTier.stored

    private let recentsKey = "RecentFolders"

    // MARK: - Yaşam döngüsü

    func applicationDidFinishLaunching(_ notification: Notification) {
        wire()
        buildMenu()
        buildWindow()
        host.load()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        registry.stop()
        hooks.stop()
        SessionRestore.save(store.sessions)
        // v1'de kalıcılık yok: uygulama kapanınca PTY'ler de kapanır (PLAN.md §8).
        for session in store.sessions where session.hasTerminal { session.pty.hangUp() }
    }

    // MARK: - Kablolama

    private func wire() {
        store.onCreate = { [weak self] session in self?.host.create(session.id) }
        store.onSelect = { [weak self] session in
            guard let self else { return }
            if session.hasTerminal { self.host.select(session.id) }
            self.refreshContent()
            self.refreshInspector()
        }
        store.onDispose = { [weak self] session in
            self?.host.dispose(session.id)
            self?.transcript.forget(session.id)
        }
        store.onLayout = { [weak self] ids in
            guard let self else { return }
            self.host.layout(ids)
            self.refreshContent()
        }

        // Panoya tıklamak klavye odağını o panele taşıyor.
        host.onFocusPane = { [weak self] id in
            guard let self, let pane = self.store.pane(of: id) else { return }
            self.store.focusPane(pane)
        }

        host.onReady = { [weak self] renderer in
            guard let self else { return }
            FileHandle.standardError.write(Data("reeve: köprü hazır · renderer: \(renderer)\n".utf8))
            if self.store.sessions.isEmpty { self.openInitialSession() }
            self.registry.start()
            self.notifier.start()
            self.hooks.start()
            self.registry.hooksActive = HookInstaller.isInstalled
        }

        // xterm örneği kuruldu ve ölçüldü — PTY tam o boyutla doğuyor,
        // böylece ilk çizimde bile TUI bozuk görünmüyor.
        host.onCreated = { [weak self] id, size in
            guard let self, let session = self.session(id) else { return }
            self.start(session, size: size)
        }

        host.onInput = { [weak self] id, data in
            self?.session(id)?.pty.write(data)
        }

        host.onResize = { [weak self] id, size in
            self?.session(id)?.pty.resize(to: size)
        }

        // Katman 1 — canlı durum, dışarıda açılan oturumlar, arka plan ajanları.
        registry.onPoll = { [weak self] records in
            guard let self else { return }
            self.store.apply(records)
            self.notifier.updateBadge(waiting: self.store.waiting.count)
            self.gitProbe.refresh(cwds: self.store.uniqueCwds)
            self.refreshGitSummary()
            self.processTree.refresh(roots: self.store.sessions.compactMap(\.pid))
            self.transcript.refresh(self.store.transcriptTargets)
            self.refreshContent()
        }
        store.onTransitions = { [weak self] transitions in
            self?.notifier.handle(transitions)
        }
        gitProbe.onUpdate = { [weak self] states in
            self?.store.applyGit(states)
        }
        processTree.onUpdate = { [weak self] trees in
            self?.store.applyChildren(trees)
        }
        processTree.onCwd = { [weak self] cwds in
            self?.store.applyCwds(cwds)
        }
        // Katman 3 - model, token, maliyet ve konusma adimlari.
        transcript.onUpdate = { [weak self] usages in
            self?.store.applyUsage(usages)
        }
        transcript.onTurns = { [weak self] turns in
            self?.store.applyTurns(turns)
        }
        // Katman 2 - hook olaylari anlik; yoklamanin gecikmesini beklemiyoruz.
        hooks.onEvent = { [weak self] event in
            self?.store.apply(event)
        }
        drag.onChange = { [weak self] in
            guard let self else { return }
            self.refreshContent()
        }
        notifier.onOpenSession = { [weak self] id in
            self?.store.select(id)
        }
    }

    private func makeOverlay() -> PaneOverlay {
        PaneOverlay(store: store,
                    drag: drag,
                    onAttach: { [weak self] in self?.attach($0) },
                    onResume: { [weak self] in self?.resume($0) },
                    onStop: { [weak self] in self?.stop($0) })
    }

    private func makeFindBar() -> FindBar {
        FindBar(onFind: { [weak self] query, forward in
                    self?.host.find(query, forward: forward)
                },
                onClose: { [weak self] in self?.closeFind() })
    }

    /// Terminali bizde olmayan oturum hangi paneldeyse, bilgi kartı o panelde çıkar.
    /// WKWebView hiç gizlenmiyor — boyutu değişmesin, gizli xterm'ler bozulmasın (D2).
    private func refreshContent() {
        guard let cardView else { return }
        cardView.rootView = makeOverlay()
        cardView.isHidden = false
    }

    // MARK: - Arka plan ajanları

    /// `claude attach <shortId>` — arka plan ajanını gerçek terminalde açar (UI.md D8).
    private func attach(_ agent: Session) {
        guard let session = SessionFactory.attach(to: agent) else { return }
        store.remove(agent)
        store.add(session)
    }

    /// Harici oturumun konuşmasını Reeve'de sürdürür.
    ///
    /// Oturum başka bir terminalde hâlâ çalışıyorsa `--resume` kopya açar; iki
    /// ajan aynı konuşmaya yazar. Bu yüzden canlıysa önce soruyoruz.
    private func resume(_ session: Session) {
        let live = session.status == .busy || session.status.isWaiting
        if live {
            let alert = NSAlert()
            alert.messageText = "Bu oturum başka bir terminalde çalışıyor"
            alert.informativeText = "Şimdi sürdürmek konuşmanın bir kopyasını açar; "
                + "iki ajan aynı geçmişe yazmış olur. Oturum boşa düşene kadar "
                + "beklemek daha güvenli."
            alert.addButton(withTitle: "Yine de aç")
            alert.addButton(withTitle: "Vazgeç")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let opened = SessionFactory.resume(external: session)
        store.remove(session)
        store.add(opened)
    }

    private func stop(_ agent: Session) {
        guard let shortID = agent.shortID ?? agent.reportedPID.map(String.init) else { return }
        runClaude(["stop", shortID])
    }

    private func runClaude(_ arguments: [String]) {
        guard let path = AgentRegistry.claudePath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func session(_ id: UUID) -> Session? {
        store.sessions.first { $0.id == id }
    }

    @objc func jumpToWaiting(_ sender: Any?) {
        store.selectFirstWaiting()
    }

    // MARK: - İnceleme paneli

    @objc func showGitDiff(_ sender: Any?) {
        guard let cwd = store.selected?.cwd else { return }
        viewer.showChanges(cwd: cwd, probe: gitProbe)
    }

    /// Yoklamaya takılı ama kısılmış: cwd değiştiyse hemen, değişmediyse
    /// en fazla dört saniyede bir.
    private func refreshGitSummary() {
        guard let cwd = store.selected?.cwd else {
            gitSummary = nil
            gitSummaryCwd = nil
            applyGitSummary()
            return
        }
        let stale = Date().timeIntervalSince(gitSummaryAt) > 4
        guard cwd != gitSummaryCwd || stale else { return }
        gitSummaryCwd = cwd
        gitSummaryAt = Date()
        gitProbe.changes(in: cwd) { [weak self] changes in
            guard let self, self.gitSummaryCwd == cwd else { return }
            let added = changes.reduce(0) { $0 + $1.added }
            let removed = changes.reduce(0) { $0 + $1.removed }
            self.gitSummary = (added == 0 && removed == 0) ? nil : (added, removed)
            self.applyGitSummary()
        }
    }

    private func applyGitSummary() {
        guard let gitButton else { return }
        guard let summary = gitSummary else {
            gitButton.attributedTitle = NSAttributedString(string: "")
            gitChip?.isHidden = true
            return
        }
        gitChip?.isHidden = false
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "+\(summary.added)",
                                       attributes: [.foregroundColor: NSColor(Theme.diffAdd)]))
        text.append(NSAttributedString(string: "  −\(summary.removed)",
                                       attributes: [.foregroundColor: NSColor(Theme.diffDel)]))
        gitButton.attributedTitle = text
    }

    @objc func toggleFiles(_ sender: Any?) {
        guard let filesItem else { return }
        filesItem.isCollapsed.toggle()
        UserDefaults.standard.set(!filesItem.isCollapsed, forKey: Self.filesVisibleKey)
        // Menüden ya da kestirmeden gelindiğinde düğme kendi durumunu bilmiyor.
        filesButton?.state = filesItem.isCollapsed ? .off : .on
    }

    @objc func toggleInspector(_ sender: Any?) {
        inspector.isVisible.toggle()
        inspectorItem.isCollapsed = !inspector.isVisible
        refreshInspector()
    }

    /// Panel kapalıyken git'e hiç dokunmuyoruz — `diff` büyük repoda pahalı.
    private func refreshInspector() {
        guard inspector.isVisible, let session = store.selected else {
            inspector.changes = []
            inspector.worktrees = []
            return
        }
        gitProbe.changes(in: session.cwd) { [weak self] changes in
            self?.inspector.changes = changes
        }
        gitProbe.worktrees(in: session.cwd) { [weak self] trees in
            // Tek worktree varsa o zaten repo'nun kendisi, göstermeye değmez.
            self?.inspector.worktrees = trees.count > 1 ? trees : []
        }
    }

    private func revealTranscript(_ session: Session) {
        guard let url = transcript.file(for: session.id) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Hook köprüsü

    @objc func toggleHooks(_ sender: Any?) {
        let installed = HookInstaller.isInstalled
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = installed ? "Hook köprüsü kaldırılsın mı?"
                                      : "Hook köprüsü kurulsun mu?"
        alert.informativeText = installed
            ? "~/.claude/settings.json içinden yalnızca Reeve'in eklediği girdiler "
              + "silinecek; kendi hook'larına dokunulmayacak. Yazmadan önce yedek alınır."
            : "Reeve, ~/.claude/settings.json dosyana yedi olay için hook ekleyecek. "
              + "Karşılığında sol panel hangi tool'un çalıştığını, alt-ajanları ve izin "
              + "isteklerini anlık gösterir.\n\nMevcut hook'ların korunur, dosyanın zaman "
              + "damgalı yedeği alınır ve bu menüden geri alınabilir."
        alert.addButton(withTitle: installed ? "Kaldır" : "Kur")
        alert.addButton(withTitle: "Vazgeç")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let outcome = installed ? HookInstaller.uninstall() : HookInstaller.install()
        registry.hooksActive = HookInstaller.isInstalled
        report(outcome)
    }

    private func report(_ outcome: HookInstaller.Outcome) {
        let done = NSAlert()
        switch outcome {
        case .installed(let backup):
            done.messageText = "Hook köprüsü kuruldu"
            done.informativeText = "Şu an açık olan Claude oturumları etkilenmez; "
                + "yeni açılanlarda anlık durum görünür."
                + (backup.map { "\n\nYedek: \($0.lastPathComponent)" } ?? "")
        case .removed(let backup):
            done.messageText = "Hook köprüsü kaldırıldı"
            done.informativeText = backup.map { "Yedek: \($0.lastPathComponent)" } ?? ""
        case .failed(let reason):
            done.alertStyle = .warning
            done.messageText = "Olmadı"
            done.informativeText = reason
        }
        done.runModal()
    }

    // MARK: - Sidebar kademesi

    @objc func cycleSidebar(_ sender: Any?) {
        applyTier(tier.next)
    }

    private func applyTier(_ next: SidebarTier) {
        if tier == .wide, let view = sidebarItem?.viewController.view {
            expandedSidebarWidth = max(view.frame.width, SidebarTier.minimumExpandedWidth)
        }
        tier = next
        SidebarTier.stored = next
        let width = next == .narrow ? next.width : expandedSidebarWidth
        sidebarSplitView.setPosition(SidebarTier.settledWidth(width), ofDividerAt: 0)
    }

    private func settleSidebar(at width: CGFloat) {
        let settled = SidebarTier.settledWidth(width)
        tier = SidebarTier.fitting(width: settled)
        SidebarTier.stored = tier
        if tier == .wide { expandedSidebarWidth = settled }
        sidebarSplitView.setPosition(settled, ofDividerAt: 0)
    }

    private func makeSidebar() -> SidebarView {
        SidebarView(store: store,
                    drag: drag,
                    onNew: { [weak self] in self?.newSession(nil) },
                    onAttach: { [weak self] in self?.attach($0) },
                    onResume: { [weak self] in self?.resume($0) },
                    onStop: { [weak self] in self?.stop($0) })
    }

    // MARK: - Panel sayısı

    /// İki panelde her terminal yarı genişlikte kalıyor; dar alanda Claude'un TUI'si
    /// bozulur. Eşiğin altında bölmeye izin verilmiyor (UI.md D9).
    private var canSplit: Bool {
        (window?.contentView?.bounds.width ?? 0) - (sidebarItem?.viewController.view.frame.width ?? tier.width) > 760
    }

    @objc func togglePanes(_ sender: Any?) {
        guard store.paneCount > 1 || canSplit else { NSSound.beep(); return }
        store.setPaneCount(store.paneCount == 1 ? 2 : 1)
    }

    // MARK: - ⌘K paleti

    @objc func showPalette(_ sender: Any?) {
        guard palette == nil else { dismissPalette(); return }
        let view = SessionPalette(store: store, onClose: { [weak self] in self?.dismissPalette() })
        let panel = NSPanel(contentViewController: NSHostingController(rootView: view))
        panel.styleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Önce boyutlansın: contentViewController'ın fitting size'ı yerleşim
        // tamamlanmadan sıfıra yakın geliyor, ona göre konumlamak paneli
        // pencerenin dışına atıyor.
        panel.layoutIfNeeded()
        panel.setContentSize(panel.contentViewController!.view.fittingSize)
        if let frame = window?.frame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                         y: frame.maxY - size.height - 90))
        }
        palette = panel
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    private func dismissPalette() {
        guard let palette else { return }
        window.removeChildWindow(palette)
        palette.orderOut(nil)
        self.palette = nil
        window.makeKeyAndOrderFront(nil)
        host.focus()
    }

    // MARK: - ⌘F

    @objc func toggleFind(_ sender: Any?) {
        guard let findView else { return }
        if findView.isHidden {
            findView.rootView = makeFindBar()
            findView.isHidden = false
        } else {
            closeFind()
        }
    }

    private func closeFind() {
        findView?.isHidden = true
        host.clearFind()
        host.focus()
    }

    private func start(_ session: Session, size: PtyProcess.Size) {
        // Harici/arka plan oturumlarında `launch` yok — onların PTY'si bizde değil.
        guard let launch = session.launch else { return }

        session.pty.onOutput = { [weak self, weak session] data in
            guard let self, let session else { return }
            self.host.feed(session.id, data)
            self.store.markOutput(for: session)
        }
        session.pty.onExit = { [weak session] code in
            session?.status = .exited(code)
        }

        do {
            try session.pty.start(executable: launch.executable,
                                  args: launch.args,
                                  cwd: session.cwd,
                                  env: launch.env,
                                  size: size)
            session.startedAt = Date()
        } catch {
            host.feed(session.id, Data("\r\n\u{1b}[31m\(error)\u{1b}[0m\r\n".utf8))
            session.status = .exited(-1)
        }
    }

    // MARK: - Oturum açma

    /// Finder ya da Dock'tan açılan bir uygulamanın çalışma dizini "/" olur;
    /// oturum için anlamsız bir başlangıç. Varsayılan her zaman ev dizini.
    private var defaultCwd: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func openInitialSession() {
        let cwd = defaultCwd
        open(cwd: cwd, template: .shell,
             name: SessionFactory.name(for: cwd, existing: store.sessions.map(\.name)))
    }

    private func open(cwd: String, template: Template, name: String) {
        store.add(SessionFactory.make(template: template, cwd: cwd, name: name))
        rememberFolder(cwd)
        DispatchQueue.main.async { self.host.focus() }
    }

    @objc func newSession(_ sender: Any?) {
        guard sheet == nil else { return }
        let cwd = store.selected?.cwd ?? defaultCwd
        let view = NewSessionSheet(
            cwd: cwd,
            name: SessionFactory.name(for: cwd, existing: store.sessions.map(\.name)),
            recents: recentFolders(),
            onCancel: { [weak self] in self?.dismissSheet() },
            onOpen: { [weak self] cwd, template, name in
                self?.dismissSheet()
                self?.open(cwd: cwd, template: template, name: name)
            })

        let panel = NSWindow(contentViewController: NSHostingController(rootView: view))
        panel.styleMask = [.titled, .fullSizeContentView]
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = Theme.nsSheetBG
        sheet = panel
        window.beginSheet(panel)
    }

    private func dismissSheet() {
        guard let sheet else { return }
        window.endSheet(sheet)
        self.sheet = nil
    }

    @objc func restorePrevious(_ sender: Any?) {
        let saved = SessionRestore.saved
        guard !saved.isEmpty else { NSSound.beep(); return }
        let open = Set(store.sessions.map(\.claudeSessionID.uuidString))
        var restored = 0
        for entry in saved where !open.contains(entry.claudeSessionID) {
            store.add(SessionFactory.resume(entry))
            restored += 1
        }
        if restored == 0 { NSSound.beep() }
    }

    @objc func closeSession(_ sender: Any?) {
        guard let session = store.selected else { return }
        store.close(session)
    }

    @objc func nextSession(_ sender: Any?) { store.selectNext(by: 1) }
    @objc func previousSession(_ sender: Any?) { store.selectNext(by: -1) }

    @objc func jumpToSession(_ sender: NSMenuItem) {
        store.select(index: sender.tag)
    }

    // MARK: - Son kullanılan klasörler

    private func recentFolders() -> [String] {
        var list = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        // Eski sürümler çalışma dizinini de biriktiriyordu, yani "/" listeye
        // yazılmış olabilir; kalıntıyı temizliyoruz.
        list.removeAll { $0 == "/" }
        let home = defaultCwd
        if !list.contains(home) { list.append(home) }
        return list
    }

    private func rememberFolder(_ path: String) {
        var list = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(8)), forKey: recentsKey)
    }

    // MARK: - Pencere

    private func buildWindow() {
        // Kasten `sidebarWithViewController` DEĞİL: o, macOS'un vibrancy'sini
        // dayatıyor ve mockup'ın düz #212127 yüzeyini bozuyor.
        let sidebarVC = NSHostingController(rootView: makeSidebar())
        let sidebar = NSSplitViewItem(viewController: sidebarVC)
        sidebar.minimumThickness = SidebarTier.narrow.width
        sidebar.maximumThickness = SidebarTier.maximumWidth
        sidebar.canCollapse = false
        sidebar.holdingPriority = .init(260)
        sidebarItem = sidebar

        // Üstte panel başlıkları, altta terminal. Harici oturum seçilince kart
        // terminalin üstüne serilir; ⌘F çubuğu da yerleşime katılmadan biner.
        let content = NSViewController()
        content.view = NSView()
        let headers = NSHostingView(rootView: PaneHeaderBar(store: store))
        cardView = NSHostingView(rootView: makeOverlay())
        findView = NSHostingView(rootView: makeFindBar())
        findView.isHidden = true

        for view in [headers, host.webView, cardView!, findView!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.view.addSubview(view)
        }
        NSLayoutConstraint.activate([
            headers.topAnchor.constraint(equalTo: content.view.topAnchor),
            headers.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            headers.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),

            host.webView.topAnchor.constraint(equalTo: headers.bottomAnchor),
            host.webView.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
            host.webView.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            host.webView.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),

            cardView.topAnchor.constraint(equalTo: headers.bottomAnchor),
            cardView.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
            cardView.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),

            findView.topAnchor.constraint(equalTo: headers.bottomAnchor, constant: 10),
            findView.trailingAnchor.constraint(equalTo: content.view.trailingAnchor, constant: -14),
        ])

        let inspectorVC = NSHostingController(rootView: InspectorView(
            store: store,
            model: inspector,
            onRevealTranscript: { [weak self] in self?.revealTranscript($0) },
            onClose: { [weak self] in self?.toggleInspector(nil) }))
        let inspectorSide = NSSplitViewItem(viewController: inspectorVC)
        inspectorSide.minimumThickness = 300
        inspectorSide.maximumThickness = 300
        inspectorSide.canCollapse = true
        inspectorSide.isCollapsed = true          // varsayilan kapali (UI.md §7)
        inspectorItem = inspectorSide

        let split = NSSplitViewController()
        let sidebarSplit = SidebarSplitView()
        sidebarSplit.isVertical = true
        sidebarSplit.dividerStyle = .thin
        sidebarSplit.onSidebarResizeEnded = { [weak self] width in
            self?.settleSidebar(at: width)
        }
        split.splitView = sidebarSplit
        sidebarSplitView = sidebarSplit
        split.addSplitViewItem(sidebar)

        // Dosya paneli sidebar'ın hemen sağında; varsayılan kapalı, tercih kalıcı.
        let filesVC = NSHostingController(rootView: FileTreeView(
            store: store,
            onOpenFile: { [weak self] url in self?.viewer.show(file: url) }))
        let files = NSSplitViewItem(viewController: filesVC)
        files.minimumThickness = 180
        files.maximumThickness = 420
        files.canCollapse = true
        files.holdingPriority = .init(259)
        files.isCollapsed = !UserDefaults.standard.bool(forKey: Self.filesVisibleKey)
        filesItem = files
        split.addSplitViewItem(files)

        let terminalItem = NSSplitViewItem(viewController: content)
        terminalItem.minimumThickness = 360
        split.addSplitViewItem(terminalItem)

        // Görüntüleyici terminalin sağında, inceleme panelinin solunda. İstek
        // üzerine açılıyor: dosya tıklandığında ya da git özetine basıldığında.
        let viewerVC = NSHostingController(rootView: ViewerPanel(model: viewer))
        let viewerSide = NSSplitViewItem(viewController: viewerVC)
        viewerSide.minimumThickness = 280
        viewerSide.maximumThickness = 680
        viewerSide.canCollapse = true
        viewerSide.isCollapsed = true
        viewerItem = viewerSide
        viewer.onVisibilityChange = { [weak self] visible in
            self?.viewerItem?.isCollapsed = !visible
        }
        split.addSplitViewItem(viewerSide)

        split.addSplitViewItem(inspectorSide)

        let root = NSViewController()
        root.view = NSView()
        root.view.wantsLayer = true
        root.view.layer?.backgroundColor = Theme.nsAppBG.cgColor
        root.addChild(split)

        let statusBar = StatusBarHostingView(store: store)
        for sub in [split.view, statusBar] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            root.view.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            split.view.topAnchor.constraint(equalTo: root.view.topAnchor),
            split.view.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: split.view.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),
        ])

        window = NSWindow(contentViewController: root)
        window.setContentSize(NSSize(width: 1180, height: 720))
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.title = "Reeve"
        window.titleVisibility = .hidden
        window.setFrameAutosaveName("ReeveMain")
        window.tabbingMode = .disallowed
        // Mockup'ın uygulama penceresi koyu; sistem açık temadayken de öyle kalıyor.
        // (UI.md §8'deki "sistemi takip et" kararı Faz 1.5'te yeniden ele alınacak.)
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.nsTitlebar
        window.toolbar = buildToolbar()
        // Varsayılan stil başlık çubuğunu iki katına çıkarıyor;
        // mockup'ın 40 px'lik çubuğu için sıkışık birleşik stil gerekiyor.
        window.toolbarStyle = .unifiedCompact
        window.center()
        window.contentView?.layoutSubtreeIfNeeded()
        sidebarSplitView.setPosition(tier.width, ofDividerAt: 0)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "ReeveMain")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    // MARK: - Araç çubuğu

    private static let filesVisibleKey = "FilesPanelVisible"

    /// Araç çubuğu simgeleri aynı görsel ağırlıkta dursun: yapılandırma verilmezse
    /// her glif kendi doğal boyutunda çiziliyor ve yoğun olanlar iri görünüyor.
    private static let toolbarSymbol = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

    /// Açık/kapalı durumunu gösteren düğme; durumu menüden de değişebildiği için
    /// referansı tutuyoruz.
    private weak var filesButton: NSButton?

    /// Düz `NSToolbarItem.image` ne hover ne de basılı durum çiziyor. Gerçek bir
    /// `NSButton` ikisini de bedavaya veriyor: `pushOnPushOff` açıkken kabarık
    /// zemin bırakıyor, kenarlık imleç üzerine gelince beliriyor.
    private func toolbarButton(_ image: NSImage?, toggle: Bool, action: Selector) -> NSButton {
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.setButtonType(toggle ? .pushOnPushOff : .momentaryPushIn)
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.imagePosition = .imageOnly
        // Şablon simge varsayılanda ikincil etiket renginde çiziliyor; bir tik açıyoruz.
        button.contentTintColor = NSColor(Theme.ink2)
        button.frame = NSRect(x: 0, y: 0, width: 30, height: 22)
        return button
    }

    /// İlk çözülen ad kullanılıyor: SF Symbols adları sürümle değişiyor, biri
    /// yoksa düğme simgesiz kalmasın.
    private static func toolbarImage(_ names: [String]) -> NSImage? {
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
                return image.withSymbolConfiguration(toolbarSymbol)
            }
        }
        return nil
    }

    private static let sidebarItemID = NSToolbarItem.Identifier("sidebarTier")

    private static let filesItemID = NSToolbarItem.Identifier("filesPanel")


    private static let gitItemID = NSToolbarItem.Identifier("gitSummary")

    private static let titleItemID = NSToolbarItem.Identifier("windowTitle")

    /// Sidebar düğmesi solda, panele bakan tarafta. Panel sayısı araç çubuğundan
    /// çıkarıldı: oturumu sidebar'dan terminale sürüklemek daha doğrudan.
    ///
    /// Pencere başlığı gizlenip araç çubuğuna taşındı; aksi halde macOS başlığı
    /// sola koyup bütün araç çubuğu öğelerini sağa itiyor.
    private var toolbarLayout: [NSToolbarItem.Identifier] {
        [Self.sidebarItemID, Self.filesItemID, Self.titleItemID, .flexibleSpace, Self.gitItemID]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarLayout
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarLayout
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case Self.sidebarItemID:
            let button = toolbarButton(Self.toolbarImage(["sidebar.left"]),
                                       toggle: false, action: #selector(cycleSidebar(_:)))
            button.toolTip = "Sidebar'ı daralt / genişlet (⌘S)"
            item.view = button
            item.label = "Sidebar"

        case Self.filesItemID:
            let button = toolbarButton(Self.toolbarImage(["wrench.adjustable", "wrench"]),
                                       toggle: true, action: #selector(toggleFiles(_:)))
            button.toolTip = "Dosya panelini aç / kapat (⌘⌥E)"
            button.state = (filesItem?.isCollapsed == false) ? .on : .off
            filesButton = button
            item.view = button
            item.label = "Dosyalar"

        case Self.gitItemID:
            let button = NSButton(title: "", target: self, action: #selector(showGitDiff(_:)))
            button.isBordered = false
            button.image = Self.toolbarImage(["plusminus"])
            button.imagePosition = .imageLeading
            button.contentTintColor = NSColor(Theme.ink2)
            button.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            button.toolTip = "Çalışma ağacındaki değişiklikler — tıkla, dosyaları sağda aç"
            gitButton = button

            // Koyu yuvarlak çip. Düğmenin kendi zemini yok (`isBordered = false`),
            // yoksa sistem bezeli çipin rengini bastırırdı.
            let chip = NSView()
            chip.wantsLayer = true
            chip.layer?.backgroundColor = NSColor(Theme.control).cgColor
            chip.layer?.cornerRadius = 6
            chip.translatesAutoresizingMaskIntoConstraints = false
            button.translatesAutoresizingMaskIntoConstraints = false
            chip.addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 8),
                button.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -8),
                button.topAnchor.constraint(equalTo: chip.topAnchor, constant: 3),
                button.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -3),
            ])
            item.view = chip
            gitChip = chip
            item.label = "Değişiklikler"
            applyGitSummary()

        case Self.titleItemID:
            let label = NSTextField(labelWithString: "Reeve")
            label.font = .systemFont(ofSize: 12.5, weight: .medium)
            label.textColor = NSColor(Theme.ink2)
            item.view = label
            item.label = "Reeve"

        default:
            return nil
        }
        return item
    }

    // MARK: - Menü

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Reeve Hakkında",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hook köprüsü…",
                        action: #selector(toggleHooks(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Reeve'i Gizle",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Reeve'den Çık",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Oturum")
        fileMenu.addItem(withTitle: "Yeni oturum…",
                         action: #selector(newSession(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Oturumu kapat",
                         action: #selector(closeSession(_:)), keyEquivalent: "w")
        fileMenu.addItem(.separator())
        let restore = NSMenuItem(title: "Önceki oturumları geri yükle",
                                 action: #selector(restorePrevious(_:)), keyEquivalent: "r")
        restore.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(restore)
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Düzen")
        editMenu.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Terminalde ara…",
                         action: #selector(toggleFind(_:)), keyEquivalent: "f")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Görünüm")
        viewMenu.addItem(withTitle: "Sidebar kademesi",
                         action: #selector(cycleSidebar(_:)), keyEquivalent: "s")
        let split = NSMenuItem(title: "Paneli böl / birleştir",
                               action: #selector(togglePanes(_:)), keyEquivalent: "d")
        viewMenu.addItem(split)
        let filesMenuItem = NSMenuItem(title: "Dosya paneli",
                                       action: #selector(toggleFiles(_:)), keyEquivalent: "e")
        filesMenuItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(filesMenuItem)
        let inspect = NSMenuItem(title: "İnceleme paneli",
                                 action: #selector(toggleInspector(_:)), keyEquivalent: "i")
        inspect.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(inspect)
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let goItem = NSMenuItem()
        let goMenu = NSMenu(title: "Git")
        goMenu.addItem(withTitle: "Oturum ara…",
                       action: #selector(showPalette(_:)), keyEquivalent: "k")
        goMenu.addItem(.separator())
        let next = NSMenuItem(title: "Sonraki oturum", action: #selector(nextSession(_:)), keyEquivalent: "]")
        next.keyEquivalentModifierMask = [.command, .shift]
        goMenu.addItem(next)
        let previous = NSMenuItem(title: "Önceki oturum", action: #selector(previousSession(_:)), keyEquivalent: "[")
        previous.keyEquivalentModifierMask = [.command, .shift]
        goMenu.addItem(previous)
        let waiting = NSMenuItem(title: "Dikkat bekleyene atla",
                                 action: #selector(jumpToWaiting(_:)), keyEquivalent: "a")
        waiting.keyEquivalentModifierMask = [.command, .shift]
        goMenu.addItem(waiting)
        goMenu.addItem(.separator())
        for index in 0..<9 {
            let item = NSMenuItem(title: "Oturum \(index + 1)",
                                  action: #selector(jumpToSession(_:)),
                                  keyEquivalent: "\(index + 1)")
            item.tag = index
            goMenu.addItem(item)
        }
        goItem.submenu = goMenu
        main.addItem(goItem)

        NSApp.mainMenu = main
    }
}

// Üst düzey kod ana iş parçacığında çalışıyor; izolasyonu derleyiciye söylüyoruz.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let controller = AppController()
    app.delegate = controller
    app.run()
}
