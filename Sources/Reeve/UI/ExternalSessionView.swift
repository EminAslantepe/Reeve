import AppKit
import SwiftUI

/// Terminali bizde olmayan oturumun paneli (UI.md §4).
///
/// **Neden canlı terminal yok:** bir PTY'yi onu yaratan süreç sahiplenir.
/// iTerm'de açılmış bir oturumun terminali iTerm'in içinde; başka bir sürecin
/// PTY'sine sonradan bağlanmak mümkün değil.
///
/// **Ama konuşma görünüyor.** Transcript JSONL'i zaten okuyoruz (Katman 3), bu
/// yüzden panel boş bir "gösteremiyoruz" kartı değil, salt-okunur bir konuşma
/// okuyucusu. Yoklama döngüsüyle birlikte tazeleniyor.
struct ExternalSessionView: View {
    let session: Session
    let tick: Int
    /// İki-üç panelde alan daralıyor; üst bilgi kısalıyor.
    var compact = false
    let onAttach: (Session) -> Void
    let onResume: (Session) -> Void
    let onStop: (Session) -> Void

    private var isBackground: Bool { session.origin == .backgroundAgent }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.ruleSoft).frame(height: Theme.hairline)
            if session.turns.isEmpty {
                empty
            } else {
                conversation
            }
            Rectangle().fill(Theme.ruleSoft).frame(height: Theme.hairline)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.terminal)
    }

    // MARK: - Başlık

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                StatusDot(status: session.status, origin: session.origin)
                Text(session.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let usage = session.usage {
                    Text([usage.model, "\(usage.tokenLabel) token", usage.costLabel]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                Text(isBackground ? "arka plan ajanı" : "salt okunur")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.control))
                Text(detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.control)
    }

    private var detail: String {
        var parts = [session.displayCwd]
        if let pid = session.pid { parts.append("pid \(pid)") }
        if !compact, let shortID = session.shortID { parts.append(shortID) }
        parts.append("\(session.elapsed) önce")
        return parts.joined(separator: " · ")
    }

    // MARK: - Konuşma

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.turns) { turn in
                        TranscriptTurnRow(turn: turn)
                            .id(turn.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onAppear { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: session.turns.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottom, anchor: .bottom)
                }
            }
        }
    }

    private static let bottom = "transcript-bottom"

    private var empty: some View {
        VStack(spacing: 6) {
            Spacer()
            Text(session.kind == .claude ? "transcript henüz yazılmadı"
                                         : "bu oturumun kaydı yok")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.ink3)
            Text("terminali gösteremiyoruz — PTY bu uygulamada değil")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.ink3.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Eylemler

    private var actions: some View {
        HStack(spacing: 8) {
            if isBackground {
                Button("Terminalde aç") { onAttach(session) }
                    .buttonStyle(CardButton(primary: true))
                Button("Durdur") { onStop(session) }
                    .buttonStyle(CardButton(primary: false))
            } else {
                // Terminali devralamıyoruz ama konuşmayı kimliğinden açabiliyoruz.
                Button("Reeve'de devam et") { onResume(session) }
                    .buttonStyle(CardButton(primary: true))
                    .help("claude --resume ile konuşmayı bu pencerede sürdürür")
            }
            Spacer()
            Text(session.status.isWaiting || session.status == .busy
                 ? "başka bir terminalde çalışıyor"
                 : "boşta")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.control)
    }
}

/// Transcript'ten tek bir konuşma adımı.
struct TranscriptTurnRow: View {
    let turn: Turn

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(marker)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 12, alignment: .leading)
            Text(turn.text)
                .font(.system(size: 11.5, design: turn.kind == .tool ? .monospaced : .default))
                .foregroundStyle(turn.kind == .tool ? Theme.ink3 : Theme.ink2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var marker: String {
        switch turn.kind {
        case .user: return "›"
        case .assistant: return "⏺"
        case .tool: return "⚙"
        }
    }

    private var color: Color {
        switch turn.kind {
        case .user: return Theme.busy
        case .assistant: return Color(hex: 0x6FCF97)
        case .tool: return Theme.ink3
        }
    }
}

struct CardButton: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: primary ? .medium : .regular))
            .foregroundStyle(primary ? Theme.appBG : Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(primary ? Theme.primary : Theme.button))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
