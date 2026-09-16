import SwiftUI

/// Alt şerit. Mockup'ta model/token/maliyet de var — onlar Faz 4'te
/// transcript katmanından gelecek, uydurma değer basılmıyor.
struct StatusBarView: View {
    let store: SessionStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                if index > 0 { separator }
                Text(field)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(Theme.ink3)
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.statusbar)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }

    private var fields: [String] {
        var out: [String] = []
        guard let selected = store.selected else {
            return ["\(store.sessions.count) oturum"]
        }
        out.append(selected.displayCwd)

        if let git = store.gitStates[selected.cwd] {
            var badge = git.branch
            if git.dirty > 0 { badge += " ●\(git.dirty)" }
            if git.ahead > 0 { badge += " ↑\(git.ahead)" }
            out.append(badge)
        }
        // Model, token ve maliyet transcript'ten geliyor; yoksa hiç yazılmıyor —
        // uydurma değer basmaktansa alanı boş bırakmak daha dürüst.
        if let usage = selected.usage {
            if let model = usage.model { out.append(model) }
            if usage.billableTokens > 0 { out.append("\(usage.tokenLabel) token") }
            if usage.costUSD > 0 { out.append(usage.costLabel) }
        } else if let pid = selected.pid {
            out.append("pid \(pid)")
        }

        if store.paneCount > 1 { out.append("\(store.paneCount) panel") }
        out.append("\(store.sessions.count) oturum")
        return out
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(Theme.rule)
            .padding(.horizontal, 6)
    }
}
