import AppKit
import SwiftUI

/// Reeve'in açmadığı oturuma tıklanınca terminalin yerine çıkan kart (UI.md §4).
///
/// Neden kart: `claude agents --json` bu oturumları görüyor ama PTY'leri bizde
/// değil, ekranlarını çizemeyiz. Boş terminal göstermek yerine ne olduğunu söylüyoruz.
struct ExternalSessionCard: View {
    let session: Session
    let tick: Int
    /// İki panelde alan yarıya iniyor; kart daralıyor.
    var compact = false
    let onAttach: (Session) -> Void
    let onStop: (Session) -> Void

    private var isBackground: Bool { session.origin == .backgroundAgent }

    var body: some View {
        VStack {
            Spacer()
            card
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.terminal)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusDot(status: session.status, origin: session.origin)
                    Text(session.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Text(isBackground
                     ? "Arka plan ajanı — terminali `claude attach` ile açılabilir."
                     : "Bu oturum Reeve dışında açıldı — terminalini gösteremiyoruz.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Rectangle().fill(Theme.ruleSoft).frame(height: 1)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                row("Klasör", session.displayCwd)
                if let pid = session.pid { row("PID", "\(pid)") }
                if let shortID = session.shortID { row("Kısa id", shortID) }
                if !compact {
                    row("Oturum", String(session.claudeSessionID.uuidString.prefix(18)).lowercased())
                }
                row("Durum", statusText, warn: session.status.isWaiting)
                row("Başlangıç", "\(session.elapsed) önce")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)

            // Eylemler yalnızca arka plan ajanlarında anlamlı: `claude attach` ve
            // `claude stop` kısa id istiyor, harici interaktif oturumda o id yok.
            // Onu durdurmanın tek yolu pid'e sinyal atmak olurdu — kullanıcının
            // iTerm'deki oturumunu Reeve'den öldürmek istemeyiz.
            if isBackground {
                Rectangle().fill(Theme.ruleSoft).frame(height: 1)
                HStack(spacing: 8) {
                    Button("Terminalde aç") { onAttach(session) }
                        .buttonStyle(CardButton(primary: true))
                    Button("Durdur") { onStop(session) }
                        .buttonStyle(CardButton(primary: false))
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .frame(width: compact ? 300 : 420)
        .background(Theme.appBG)
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private var statusText: String {
        switch session.status {
        case .waiting(let what): return what
        case .busy:              return "busy"
        case .idle:              return "idle"
        case .live:              return "çalışıyor"
        case .exited(let code):  return "exit \(code)"
        }
    }

    private func row(_ key: String, _ value: String, warn: Bool = false) -> some View {
        GridRow {
            Text(key)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(warn ? Theme.wait : Theme.ink)
                .textSelection(.enabled)
        }
    }
}

private struct CardButton: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: primary ? .medium : .regular))
            .foregroundStyle(primary ? Color.white : Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(primary ? Theme.primary : Theme.button))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
