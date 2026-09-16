import SwiftUI

/// ⌘K oturum arama (UI.md §1.2 / D11).
///
/// Sidebar kapalıyken asıl gezinme yolu bu. Sıralama kuralı sabit:
/// **önce bekleyenler**, sonra eşleşme skoru, sonra son aktivite.
struct SessionPalette: View {
    let store: SessionStore
    let onClose: () -> Void

    @State private var query = ""
    @State private var cursor = 0
    @FocusState private var focused: Bool

    var body: some View {
        // Skorlama **bir kez** burada. Önceden `matches`, `waitingMatches`,
        // `otherMatches` ve `resultsHeight` ayrı ayrı `ranked`i çağırıyordu:
        // tek çizimde dokuz tam skorlama + sıralama, her tuş vuruşunda.
        let split = partition(ranked)
        return VStack(alignment: .leading, spacing: 0) {
            field
            Rectangle().fill(Theme.rule).frame(height: 1)
            results(split)
            Rectangle().fill(Theme.rule).frame(height: 1)
            footer
        }
        .background(Theme.paletteBG)
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.paletteBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .frame(width: 460)
        .onAppear { focused = true }
    }

    // MARK: - Parçalar

    private var field: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink3)
            TextField("oturum ara…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .onChange(of: query) { _, _ in cursor = 0 }
                .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape]) { press in
                    handle(press)
                }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func results(_ split: Split) -> some View {
        if split.waiting.isEmpty && split.other.isEmpty {
            Text("eşleşme yok")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.ink3)
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Not: `ForEach(x.enumerated())` doğrudan kullanmak macOS 15+
                    // istiyor (EnumeratedSequence'ın RandomAccessCollection uyumu
                    // yeni). Hedefimiz macOS 14, o yüzden Array(...) kalıyor.
                    if !split.waiting.isEmpty {
                        sectionLabel("Bekleyen")
                        ForEach(Array(split.waiting.enumerated()), id: \.element.id) { index, session in
                            row(session, index: index)
                        }
                    }
                    if !split.other.isEmpty {
                        sectionLabel("Tüm oturumlar")
                        ForEach(Array(split.other.enumerated()), id: \.element.id) { index, session in
                            row(session, index: split.waiting.count + index)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            // ScrollView'ün doğal yüksekliği yok; pencere içeriğine göre
            // boyutlandığı için burada açıkça vermek zorundayız.
            .frame(height: height(of: split))
        }
    }

    /// Satır ve başlık sayısından hesaplanıyor, 300'de tavan yapıyor.
    private func height(of split: Split) -> CGFloat {
        let rows = CGFloat(split.waiting.count + split.other.count) * 30
        let labels = CGFloat((split.waiting.isEmpty ? 0 : 1)
                           + (split.other.isEmpty ? 0 : 1)) * 25
        return min(300, rows + labels + 6)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .kerning(0.8)
            .foregroundStyle(Theme.ink3)
            .padding(.horizontal, 15)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    private func row(_ session: Session, index: Int) -> some View {
        HStack(spacing: 9) {
            StatusDot(status: session.status, origin: session.origin)
            Text(session.name)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 10)
            Text(detail(session))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(session.status.isWaiting ? Theme.wait : Theme.ink3)
                .lineLimit(1)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 7)
        .background(index == cursor ? Theme.paletteRowOn : .clear)
        .contentShape(Rectangle())
        .onTapGesture { open(session, secondPane: false) }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("⏎ aç")
            Text("⌥⏎ ikinci panelde aç")
            Text("⌘⇧A bekleyene")
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Theme.ink3)
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(Theme.paletteFoot)
    }

    // MARK: - Eşleştirme

    /// Sıralama kuralı sabit: önce bekleyenler, sonra eşleşme skoru.
    struct Split {
        var waiting: [Session] = []
        var other: [Session] = []
        var all: [Session] { waiting + other }
    }

    private func partition(_ sessions: [Session]) -> Split {
        var split = Split()
        for session in sessions {
            if session.status.isWaiting { split.waiting.append(session) }
            else { split.other.append(session) }
        }
        return split
    }

    private var ranked: [Session] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let scored = store.sessions.compactMap { session -> (Session, Int)? in
            guard !needle.isEmpty else { return (session, 0) }
            guard let score = Self.score(needle, in: haystack(session)) else { return nil }
            return (session, score)
        }
        return scored
            .sorted { left, right in
                if left.1 != right.1 { return left.1 > right.1 }
                return left.0.startedAt > right.0.startedAt
            }
            .map(\.0)
    }

    private func haystack(_ session: Session) -> String {
        var parts = [session.name, session.displayCwd]
        if let git = store.gitStates[session.cwd] { parts.append(git.branch) }
        return parts.joined(separator: " ").lowercased()
    }

    private func detail(_ session: Session) -> String {
        if case .waiting(let what) = session.status { return what }
        var parts = [session.folderName]
        if let git = store.gitStates[session.cwd] { parts.append(git.branch) }
        parts.append(session.elapsed)
        return parts.joined(separator: " · ")
    }

    /// Alt dizi eşleşmesi: ardışık harfler daha çok puan, baştan başlayan en çok.
    static func score(_ needle: String, in haystack: String) -> Int? {
        var total = 0
        var streak = 0
        var index = haystack.startIndex
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return nil }
            streak = (found == index) ? streak + 1 : 0
            total += 1 + streak * 2
            if found == haystack.startIndex { total += 5 }
            index = haystack.index(after: found)
        }
        return total
    }

    // MARK: - Klavye

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .escape:
            onClose()
        case .upArrow:
            cursor = max(0, cursor - 1)
        case .downArrow:
            cursor = min(partition(ranked).all.count - 1, cursor + 1)
        case .return:
            let all = partition(ranked).all
            guard all.indices.contains(cursor) else { return .handled }
            open(all[cursor], secondPane: press.modifiers.contains(.option))
        default:
            return .ignored
        }
        return .handled
    }

    private func open(_ session: Session, secondPane: Bool) {
        if secondPane {
            store.sendToSecondPane(session.id)
        } else {
            store.select(session.id)
        }
        onClose()
    }
}
