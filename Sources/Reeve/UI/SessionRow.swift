import SwiftUI

/// Sol paneldeki oturum satırı.
/// Mockup'taki ızgara: `16px | 1fr | auto`, nokta iki satırı kaplayıp üste hizalı.
///
/// ```
/// ● center-9f                12m     ← nokta · isim · süre
///   Opus 5 · Edit(...)               ← meta, mono
/// ```
struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    /// Store'un sayacı; değişmesi satırı yeniden kurdurup `elapsed`i tazeliyor.
    let tick: Int

    private var isAlarm: Bool {
        if case .waiting = session.status { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(status: session.status, origin: session.origin)
                .frame(width: 16)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(session.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if session.hasUnseenOutput {
                        Circle()
                            .fill(Theme.busy)
                            .frame(width: 5, height: 5)
                            .padding(.leading, 6)
                    }
                    Spacer(minLength: 8)
                    Text(whenText)
                        .font(.system(size: isAlarm ? 10 : 11,
                                      weight: isAlarm ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isAlarm ? Theme.wait : Theme.ink3)
                        .fixedSize()
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(session.subtitle)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(metaColor)
                        .lineLimit(1)
                        // Yolda anlamlı olan son klasör, mesajda ilk kelimeler.
                        .truncationMode(showsPath ? .head : .tail)
                    // Maliyet/token sağ alt köşede — mockup'ın ayırdığı hücre.
                    if let cost = session.costLabel {
                        Spacer(minLength: 4)
                        Text(cost)
                            .font(.system(size: 10.5, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink3)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 7)
        .padding(.top, 5)
        .padding(.bottom, 6)
        .background(background)
        .contentShape(Rectangle())
        .help("\(session.name) · \(session.displayCwd)")
    }

    private var whenText: String {
        isAlarm ? "BEKLİYOR" : session.elapsed
    }

    /// İkinci satır bir yol mu, yoksa cümle mi?
    private var showsPath: Bool {
        switch session.status {
        case .idle, .live: return session.origin != .backgroundAgent
        default:           return false
        }
    }

    private var metaColor: Color {
        switch session.status {
        case .waiting: return Theme.wait
        case .exited:  return Theme.error
        default:       return Theme.ink2
        }
    }

    @ViewBuilder
    private var background: some View {
        if isAlarm {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.wait.opacity(0.11))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.wait.opacity(0.26), lineWidth: 1))
        } else if isSelected {
            RoundedRectangle(cornerRadius: 6).fill(Theme.selection)
        }
    }
}

/// Durum göstergesi. **Biçim de anlam taşıyor** — dolu nokta, halka, baklava.
/// Yalnızca renge yaslanan bir gösterge renk körü bir kullanıcıda çöker.
struct StatusDot: View {
    let status: Session.Status
    var origin: Session.Origin = .center
    @State private var pulsing = false

    var body: some View {
        switch status {
        case .waiting:
            // Dikkat her şeyin önünde: arka plan ajanı bile olsa turuncu nokta.
            filled(Theme.wait, halo: 0.20)
        case .busy:
            filled(origin == .backgroundAgent ? Theme.agent : Theme.busy, halo: 0.18)
                .scaleEffect(pulsing ? 1.0 : 0.94)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                           value: pulsing)
                .onAppear { pulsing = true }
        case .exited:
            Circle()                                   // dolu, halosuz
                .fill(Theme.error)
                .frame(width: 9, height: 9)
        case .idle, .live:
            if origin == .backgroundAgent {
                Rectangle()                            // baklava
                    .fill(Theme.agent)
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(45))
            } else {
                Circle()                               // halka
                    .strokeBorder(Theme.idle, lineWidth: 1.5)
                    .frame(width: 9, height: 9)
            }
        }
    }

    private func filled(_ color: Color, halo: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .background(
                Circle().fill(color.opacity(halo)).frame(width: 15, height: 15))
    }
}
