import AppKit
import Observation
import SwiftUI

/// Sidebar'ın hemen sağındaki dosya paneli: seçili oturumun çalışma dizini ve
/// altındakiler.
///
/// Kök, seçili oturumun `cwd`'sini izliyor — oturum değişince panel de değişiyor.
/// Alt dizinler **açıldıklarında** okunuyor; `.git`, `.build`, `node_modules`
/// gibi ağır klasörler kapalı durdukları sürece hiç taranmıyor.
@MainActor
@Observable
final class FileTreeModel {

    struct Entry: Identifiable, Hashable {
        let url: URL
        let isDirectory: Bool
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    /// Tek seferde okunan azami girdi. Devasa bir klasör paneli kilitlemesin;
    /// listeleme ana iş parçacığında ve senkron (tipik dizinde mikrosaniyeler).
    static let pageLimit = 500

    private(set) var root: URL?
    private(set) var children: [URL: [Entry]] = [:]
    /// Okunmuş ama `pageLimit` yüzünden kesilmiş dizinlerdeki artan sayısı.
    private(set) var truncated: [URL: Int] = [:]
    private(set) var expanded: Set<URL> = []

    func setRoot(_ path: String?) {
        let next = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard next != root else { return }
        root = next
        children.removeAll()
        truncated.removeAll()
        expanded.removeAll()
        if let next { load(next) }
    }

    func entries(of url: URL) -> [Entry] { children[url] ?? [] }

    func isExpanded(_ url: URL) -> Bool { expanded.contains(url) }

    func toggle(_ entry: Entry) {
        guard entry.isDirectory else { return }
        if expanded.remove(entry.url) == nil {
            expanded.insert(entry.url)
            load(entry.url)
        }
    }

    /// Diskteki değişiklikleri izlemiyoruz; tazeleme elle. Açık dizinler
    /// yeniden okunuyor, kapalı olanlara dokunulmuyor.
    func reload() {
        let open = expanded
        children.removeAll()
        truncated.removeAll()
        if let root { load(root) }
        for url in open { load(url) }
    }

    private func load(_ url: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else {
            children[url] = []
            return
        }
        var found: [Entry] = []
        for name in names where name != ".DS_Store" {
            let child = url.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDir) else { continue }
            found.append(Entry(url: child, isDirectory: isDir.boolValue))
        }
        // Klasörler önce, sonra ada göre — Finder'ın ve çoğu editörün sırası.
        found.sort {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        if found.count > Self.pageLimit {
            truncated[url] = found.count - Self.pageLimit
            found = Array(found.prefix(Self.pageLimit))
        } else {
            truncated[url] = nil
        }
        children[url] = found
    }
}

struct FileTreeView: View {
    let store: SessionStore
    /// Dosyaya tıklanınca sağdaki görüntüleyiciye veriliyor; klasörler yerinde açılıyor.
    let onOpenFile: (URL) -> Void
    @State private var model = FileTreeModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.ruleSoft)
            if model.root == nil {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        FileTreeBranch(parent: model.root!, depth: 0,
                                       model: model, onOpenFile: onOpenFile)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Theme.sidebar)
        .onAppear { model.setRoot(store.selected?.cwd) }
        .onChange(of: store.selected?.cwd) { _, cwd in model.setRoot(cwd) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
            Text(model.root.map { $0.lastPathComponent } ?? "Dosyalar")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
            .help("Yeniden oku")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .help(model.root?.path ?? "")
    }

    private var empty: some View {
        VStack {
            Spacer()
            Text("Bir oturum seçin")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink3)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Bir dizinin çocukları. Ayrı tip: SwiftUI'de özyineleme için gövdenin
/// kendisini çağırabilen bir görünüm gerekiyor.
private struct FileTreeBranch: View {
    let parent: URL
    let depth: Int
    let model: FileTreeModel
    let onOpenFile: (URL) -> Void

    var body: some View {
        ForEach(model.entries(of: parent)) { entry in
            FileTreeRow(entry: entry, depth: depth, model: model, onOpenFile: onOpenFile)
            if entry.isDirectory, model.isExpanded(entry.url) {
                FileTreeBranch(parent: entry.url, depth: depth + 1,
                               model: model, onOpenFile: onOpenFile)
            }
        }
        if let extra = model.truncated[parent] {
            Text("… \(extra) girdi daha")
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
                .padding(.leading, CGFloat(depth) * 13 + 26)
                .padding(.vertical, 3)
        }
    }
}

private struct FileTreeRow: View {
    let entry: FileTreeModel.Entry
    let depth: Int
    let model: FileTreeModel
    let onOpenFile: (URL) -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            if entry.isDirectory { model.toggle(entry) } else { onOpenFile(entry.url) }
        } label: {
            HStack(spacing: 5) {
                // Dosyalarda da yer tutuyor ki adlar aynı hizada başlasın.
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .rotationEffect(.degrees(model.isExpanded(entry.url) ? 90 : 0))
                    .opacity(entry.isDirectory ? 1 : 0)
                    .frame(width: 9)
                Image(systemName: entry.isDirectory ? "folder" : "doc")
                    .font(.system(size: 10.5))
                    .foregroundStyle(entry.isDirectory ? Theme.agent : Theme.ink3)
                    .frame(width: 13)
                Text(entry.name)
                    .font(.system(size: 12))
                    .foregroundStyle(entry.isDirectory ? Theme.ink : Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 13 + 10)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(hovering ? Theme.choiceOn.opacity(0.55) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entry.url.path)
    }
}
