import SwiftUI

/// Seçili oturumun kullanımı her genişlikte okunabilir kalır.
struct StatusBarView: View {
    let store: SessionStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                location
                Spacer(minLength: 12)
                usage
                summary
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack { location; Spacer(minLength: 8); summary }
                ScrollView(.horizontal, showsIndicators: false) { usage }
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .foregroundStyle(Theme.ink2)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.statusbar)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }

    private var location: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
            Text(store.selected?.displayCwd ?? "Bir oturum seçin")
                .lineLimit(1)
                .truncationMode(.middle)
            if let selected = store.selected, let git = store.gitStates[selected.cwd] {
                Label(git.branch, systemImage: "arrow.triangle.branch")
                    .lineLimit(1)
                    .help("\(git.dirty) değiştirilmiş dosya · \(git.ahead) gönderilmemiş commit")
            }
        }
        .help(store.selected?.cwd ?? "")
    }

    private var usage: some View {
        HStack(spacing: 16) {
            if let usage = store.selected?.usage {
                if let model = usage.model { metric("Model", model) }
                metric("Token", usage.tokenLabel)
                metric("Maliyet", usage.costLabel)
            } else if let selected = store.selected {
                Label(selected.kind == .claude ? "Kullanım bekleniyor" : "Terminal oturumu",
                      systemImage: selected.kind == .claude ? "chart.bar" : "terminal")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(Theme.ink2)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: some View {
        Text(store.paneCount > 1
             ? "\(store.paneCount) panel · \(store.sessions.count) oturum"
             : "\(store.sessions.count) oturum")
            .fixedSize()
    }
}
