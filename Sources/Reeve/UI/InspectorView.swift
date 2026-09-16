import AppKit
import Observation
import SwiftUI

/// İnceleme panelinin istek üzerine doldurulan verisi.
/// `git diff` büyük repolarda pahalı; düzenli yoklamaya sokulmadı, panel
/// açıkken ve seçim değiştikçe tazeleniyor.
@MainActor
@Observable
final class InspectorModel {
    var changes: [GitChange] = []
    var worktrees: [Worktree] = []
    var isVisible = false
}

/// ⌘⌥I — terminalin sağına yapışan dar panel (UI.md §7).
/// Dört bölüm: kullanım · değişiklikler · alt-ajanlar ve süreçler · transcript.
struct InspectorView: View {
    let store: SessionStore
    let model: InspectorModel
    let onRevealTranscript: (Session) -> Void
    let onClose: () -> Void

    private var session: Session? { store.selected }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.rule)
            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        usage(session)
                        changes()
                        activity(session)
                        transcript(session)
                    }
                    .padding(.bottom, 14)
                }
            } else {
                Spacer()
                Text("oturum seçili değil")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.ink3)
                Spacer()
            }
        }
        .frame(width: 300)
        .background(Theme.sidebar)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.rule).frame(width: 1)
        }
    }

    // MARK: - Başlık

    private var header: some View {
        HStack(spacing: 6) {
            Text("İNCELE")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.75)
                .foregroundStyle(Theme.ink3)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
            .help("Paneli kapat (⌘⌥I)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Bölümler

    @ViewBuilder
    private func usage(_ session: Session) -> some View {
        Section("Kullanım") {
            if let usage = session.usage {
                pair("Model", usage.model ?? "—")
                pair("Token", usage.tokenLabel)
                pair("Maliyet", usage.costLabel)
                if usage.cacheReadTokens > 0 {
                    pair("Cache okuma", Self.compact(usage.cacheReadTokens), dim: true)
                }
                if usage.thinkingTokens > 0 {
                    pair("Düşünme", Self.compact(usage.thinkingTokens), dim: true)
                }
                if usage.durationMS > 0 {
                    pair("Süre", Self.duration(usage.durationMS), dim: true)
                }
            } else {
                note(session.kind == .claude
                     ? "transcript henüz yazılmadı"
                     : "shell oturumunda kullanım yok")
            }
        }
    }

    @ViewBuilder
    private func changes() -> some View {
        Section("Değişiklikler") {
            if model.changes.isEmpty {
                note("commit'lenmemiş değişiklik yok")
            } else {
                ForEach(model.changes.prefix(14)) { change in
                    HStack(spacing: 8) {
                        Text(change.name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: 6)
                        Text("+\(change.added)")
                            .foregroundStyle(Color(hex: 0x6FCF97))
                        Text("−\(change.removed)")
                            .foregroundStyle(Theme.wait)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
            }
            if !model.worktrees.isEmpty {
                ForEach(model.worktrees) { tree in
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.ink3)
                        Text(tree.branch ?? tree.name)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .help(tree.path)
                }
            }
        }
    }

    @ViewBuilder
    private func activity(_ session: Session) -> some View {
        if !session.subagents.isEmpty || !session.children.isEmpty {
            Section("Alt-ajanlar ve süreçler") {
                ForEach(session.subagents) { agent in
                    line(icon: "gearshape", text: agent.name, value: agent.elapsed,
                         dim: agent.finishedAt != nil)
                }
                ForEach(session.children) { child in
                    line(icon: "chevron.right.square", text: child.name,
                         value: child.memoryLabel, dim: false)
                }
            }
        }
    }

    @ViewBuilder
    private func transcript(_ session: Session) -> some View {
        Section("Transcript") {
            if session.turns.isEmpty {
                note("kayıt yok")
            } else {
                ForEach(session.turns.suffix(12).reversed()) { turn in
                    HStack(alignment: .top, spacing: 7) {
                        Text(marker(turn.kind))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(color(turn.kind))
                            .frame(width: 10, alignment: .leading)
                        Text(turn.text)
                            .font(.system(size: 10.5))
                            .foregroundStyle(turn.kind == .tool ? Theme.ink3 : Theme.ink2)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                }
                Button("Transcript dosyasını göster") { onRevealTranscript(session) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.busy)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - Parçalar

    private func marker(_ kind: Turn.Kind) -> String {
        switch kind {
        case .user: return "›"
        case .assistant: return "⏺"
        case .tool: return "⚙"
        }
    }

    private func color(_ kind: Turn.Kind) -> Color {
        switch kind {
        case .user: return Theme.busy
        case .assistant: return Color(hex: 0x6FCF97)
        case .tool: return Theme.ink3
        }
    }

    private func pair(_ key: String, _ value: String, dim: Bool = false) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(dim ? Theme.ink3 : Theme.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private func line(icon: String, text: String, value: String, dim: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(Theme.ink3)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .opacity(dim ? 0.55 : 1)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Theme.ink3)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
    }

    private static func compact(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }

    private static func duration(_ ms: Int) -> String {
        let seconds = ms / 1000
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)dk" }
        return String(format: "%.1fsa", Double(seconds) / 3600)
    }
}

/// Panelin başlıklı bölümü.
private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.7)
                    .foregroundStyle(Theme.ink3)
                Rectangle().fill(Theme.ruleSoft).frame(height: 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 6)
            content
        }
    }
}
