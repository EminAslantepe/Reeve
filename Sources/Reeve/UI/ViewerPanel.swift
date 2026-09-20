import Observation
import SwiftUI

/// Ekranın sağındaki görüntüleyici. İki şey gösteriyor, ikisi de aynı yerde:
/// dosya ağacından tıklanan dosyanın içeriği ve seçili oturumun git farkı.
///
/// İnceleme panelinden (⌘⌥I) ayrı duruyor: o transcript'i okuyor, bu dosyayı.
@MainActor
@Observable
final class ViewerModel {

    enum Mode: Equatable {
        case empty
        case file(URL)
        /// Değişen dosyaların klasöre göre gruplandığı liste.
        case changes(cwd: String)
        /// Tek bir dosyanın farkı; listeden gelinir, geri dönülebilir.
        case fileDiff(cwd: String, path: String)

        /// Panel şu anda bu klasörün git değişikliklerini mi gösteriyor.
        func showsChanges(in cwd: String) -> Bool {
            switch self {
            case .changes(let current), .fileDiff(let current, _): return current == cwd
            case .empty, .file: return false
            }
        }
    }

    /// Bir klasör ve altındaki değişen dosyalar.
    struct ChangeGroup: Identifiable {
        let folder: String
        let files: [GitChange]
        var id: String { folder }
        var added: Int { files.reduce(0) { $0 + $1.added } }
        var removed: Int { files.reduce(0) { $0 + $1.removed } }
    }

    /// Bir satır ve nasıl renkleneceği.
    struct Line: Identifiable {
        enum Kind { case plain, added, removed, hunk, header }
        let id: Int
        let text: String
        let kind: Kind
    }

    /// Bu tavanın üstündeki dosya açılmıyor: paneli kilitlemesinin âlemi yok.
    static let maxFileBytes = 2_000_000

    private(set) var mode: Mode = .empty
    private(set) var title = ""
    private(set) var subtitle = ""
    private(set) var lines: [Line] = []
    private(set) var groups: [ChangeGroup] = []
    private(set) var notice: String?
    /// Vurgulanıp kaydırılacak satır (1 tabanlı). Terminalde `dosya.swift:73`
    /// tıklandığında doluyor.
    private(set) var highlight: Int?
    /// Her açılışta artıyor. Aynı dosyanın aynı satırı yeniden istendiğinde de
    /// görünümün kaydırmayı tetiklemesi gerekiyor; `highlight` tek başına
    /// değişmediği için sinyal olarak yetmiyor.
    private(set) var highlightToken = 0
    @ObservationIgnored private var probe: GitProbe?
    var isVisible = false

    @ObservationIgnored var onVisibilityChange: ((Bool) -> Void)?

    func show(file url: URL, line: Int? = nil) {
        mode = .file(url)
        title = url.lastPathComponent
        subtitle = url.deletingLastPathComponent().path
        load(url)
        highlight = (line ?? 0) > 0 ? line : nil
        highlightToken &+= 1
        reveal()
    }

    /// Araç çubuğundaki düğme: aynı klasörün değişiklikleri zaten ekrandaysa
    /// ikinci basış paneli kapatıyor.
    func toggleChanges(cwd: String, probe: GitProbe) {
        if isVisible, mode.showsChanges(in: cwd) {
            close()
        } else {
            showChanges(cwd: cwd, probe: probe)
        }
    }

    /// Değişen dosyaların klasöre göre gruplandığı liste — tek dev fark bloğu yerine.
    func showChanges(cwd: String, probe: GitProbe) {
        self.probe = probe
        mode = .changes(cwd: cwd)
        highlight = nil
        title = "Değişiklikler"
        subtitle = cwd
        lines = []
        groups = []
        notice = "okunuyor…"
        probe.changes(in: cwd) { [weak self] changes in
            guard let self, case .changes(let current) = self.mode, current == cwd else { return }
            self.apply(changes: changes)
        }
        reveal()
    }

    /// Listeden bir dosyaya girildiğinde yalnızca onun farkı.
    func showFileDiff(cwd: String, path: String) {
        guard let probe else { return }
        mode = .fileDiff(cwd: cwd, path: path)
        highlight = nil
        title = (path as NSString).lastPathComponent
        subtitle = path
        lines = []
        notice = "okunuyor…"
        probe.diff(in: cwd, path: path) { [weak self] raw in
            guard let self, case .fileDiff(let c, let p) = self.mode,
                  c == cwd, p == path else { return }
            self.apply(diff: raw)
        }
    }

    /// Dosya farkından listeye dönüş.
    func backToChanges() {
        guard case .fileDiff(let cwd, _) = mode, let probe else { return }
        showChanges(cwd: cwd, probe: probe)
    }

    private func apply(changes: [GitChange]) {
        notice = changes.isEmpty ? "Değişiklik yok." : nil
        var buckets: [String: [GitChange]] = [:]
        var order: [String] = []
        for change in changes {
            // Repo kökündeki dosyalar için klasör adı yok; başlık olarak "/" veriyoruz.
            let folder = (change.path as NSString).deletingLastPathComponent
            let key = folder.isEmpty ? "/" : folder
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(change)
        }
        groups = order.sorted().map { key in
            ChangeGroup(folder: key,
                        files: buckets[key]!.sorted { $0.name < $1.name })
        }
    }

    func close() {
        isVisible = false
        onVisibilityChange?(false)
    }

    private func reveal() {
        isVisible = true
        onVisibilityChange?(true)
    }

    // MARK: - Yükleme

    private func load(_ url: URL) {
        lines = []
        notice = nil

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int) ?? 0
        if size > Self.maxFileBytes {
            notice = "Dosya çok büyük (\(size / 1_000_000) MB) — açılmadı."
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            notice = "Dosya okunamadı."
            return
        }
        // İkili dosyayı metin diye basmak paneli çöple doldurur; NUL baytı
        // pratikte yeterli bir ayraç.
        if data.prefix(4096).contains(0) {
            notice = "İkili dosya — görüntülenmiyor."
            return
        }
        guard let text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else {
            notice = "Metin olarak çözülemedi."
            return
        }
        lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { Line(id: $0.offset, text: String($0.element), kind: .plain) }
    }

    private func apply(diff raw: String) {
        notice = nil
        guard !raw.isEmpty else {
            lines = []
            notice = "Değişiklik yok."
            return
        }
        lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in
                let text = String(line)
                let kind: Line.Kind
                // Sıra önemli: `+++` ve `---` başlık, `+`/`-` içerik.
                if text.hasPrefix("+++") || text.hasPrefix("---")
                    || text.hasPrefix("diff ") || text.hasPrefix("index ")
                    || text.hasPrefix("new file") || text.hasPrefix("deleted file") {
                    kind = .header
                } else if text.hasPrefix("@@") {
                    kind = .hunk
                } else if text.hasPrefix("+") {
                    kind = .added
                } else if text.hasPrefix("-") {
                    kind = .removed
                } else {
                    kind = .plain
                }
                return Line(id: index, text: text, kind: kind)
            }
    }
}

struct ViewerPanel: View {
    let model: ViewerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.ruleSoft)
            if case .changes = model.mode {
                if let notice = model.notice {
                    message(notice)
                } else {
                    changeList
                }
            } else if let notice = model.notice {
                message(notice)
            } else if model.lines.isEmpty {
                message("Bir dosya seçin")
            } else {
                content
            }
        }
        .background(Theme.sidebar)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if case .fileDiff = model.mode {
                PanelIconButton(symbol: "chevron.left", label: "Değişiklik listesine dön") {
                    model.backToChanges()
                }
            }
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title.isEmpty ? "Görüntüleyici" : model.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !model.subtitle.isEmpty {
                    Text(model.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            PanelIconButton(symbol: "xmark", label: "Paneli kapat") {
                model.close()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var icon: String {
        switch model.mode {
        case .changes, .fileDiff: return "plusminus"
        default:                  return "doc.text"
        }
    }

    /// Klasör başlığı, altında o klasördeki değişen dosyalar. Dosyaya tıklanınca
    /// yalnızca onun farkı açılıyor.
    private var changeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.groups) { group in
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.ink3)
                        Text(group.folder)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: 6)
                        counts(added: group.added, removed: group.removed, size: 10)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 3)

                    ForEach(group.files) { file in
                        ChangeRow(file: file) {
                            if case .changes(let cwd) = model.mode {
                                model.showFileDiff(cwd: cwd, path: file.path)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func counts(added: Int, removed: Int, size: CGFloat) -> some View {
        HStack(spacing: 5) {
            if added > 0 {
                Text("+\(added)")
                    .foregroundStyle(Theme.diffAdd)
            }
            if removed > 0 {
                Text("−\(removed)")
                    .foregroundStyle(Theme.diffDel)
            }
        }
        .font(.system(size: size, design: .monospaced))
        .monospacedDigit()
    }

    /// Kod satırları.
    ///
    /// İki eksenli `ScrollView` içeriğe **panel genişliğini** öneriyor, sonsuzu
    /// değil. Eskiden satırda hem metin hem `Spacer` esnekti; SwiftUI kalan
    /// genişliği ikiye bölüp kodu yarım alana sıkıştırıyor ve sardırıyordu.
    private var content: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.lines) { line in
                            row(line, width: geometry.size.width)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // `initial: true` panel zaten açıkken gelen dosyayı da kapsıyor.
                .onChange(of: model.highlightToken, initial: true) { _, _ in
                    // LazyVStack satırları daha kurulmadan kaydırmak boşa gidiyor;
                    // bir tur bekletiyoruz.
                    DispatchQueue.main.async { jump(proxy) }
                }
            }
        }
    }

    /// Tek satır. Metin `fixedSize` ile doğal genişliğinde duruyor — uzun satır
    /// sarmıyor, yatay kaydırma bunun için var. Satırın kendisi en az panel
    /// kadar geniş: vurgu ve fark renkleri sağ kenara kadar gidiyor.
    private func row(_ line: ViewerModel.Line, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text("\(line.id + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.ink3.opacity(0.7))
                .frame(width: 34, alignment: .trailing)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(color(for: line.kind))
                .fixedSize(horizontal: true, vertical: false)
                .textSelection(.enabled)
        }
        .padding(.trailing, 12)
        .padding(.vertical, 0.5)
        .frame(minWidth: width, alignment: .leading)
        .background(background(for: line))
        .id(line.id)
    }

    /// Vurgulu satırı ortaya getirir — üste yapıştırmak çevresini görünmez kılardı.
    private func jump(_ proxy: ScrollViewProxy) {
        guard let line = model.highlight, model.lines.indices.contains(line - 1) else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(line - 1, anchor: .center)
        }
    }

    private func color(for kind: ViewerModel.Line.Kind) -> Color {
        switch kind {
        case .added:   return Theme.diffAdd
        case .removed: return Theme.diffDel
        case .hunk:    return Theme.agent
        case .header:  return Theme.ink3
        case .plain:   return Theme.ink2
        }
    }

    private func background(for line: ViewerModel.Line) -> Color {
        if model.highlight == line.id + 1 { return Theme.primary.opacity(0.16) }
        switch line.kind {
        case .added:   return Theme.diffAdd.opacity(0.10)
        case .removed: return Theme.diffDel.opacity(0.10)
        default:       return .clear
        }
    }

    private func message(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ChangeRow: View {
    let file: GitChange
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: "doc")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.ink3)
                Text(file.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    if file.added > 0 {
                        Text("+\(file.added)").foregroundStyle(Theme.diffAdd)
                    }
                    if file.removed > 0 {
                        Text("−\(file.removed)").foregroundStyle(Theme.diffDel)
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .monospacedDigit()
            }
            .padding(.leading, 26)
            .padding(.trailing, 12)
            .padding(.vertical, 3.5)
            .contentShape(Rectangle())
            .background(hovering ? Theme.choiceOn.opacity(0.55) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(file.path)
    }
}
