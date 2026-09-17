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
    var isFocused = false
    @State private var hovering = false

    private var isAlarm: Bool {
        if case .waiting = session.status { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(status: session.status, origin: session.origin)
                .frame(width: 16)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(session.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if session.hasUnseenOutput {
                        Circle()
                            .fill(Theme.busy)
                            .frame(width: 5, height: 5)
                            .padding(.leading, 6)
                    }
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(whenText)
                    }
                        .font(.system(size: 11, weight: isAlarm ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isAlarm ? Theme.wait : Theme.ink3)
                        .fixedSize()
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(detailText)
                        .font(.system(size: 12))
                        .foregroundStyle(metaColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 7)
        .padding(.top, 9)
        .padding(.bottom, 9)
        .background(background)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("\(session.name) · \(session.displayCwd)")
    }

    private var whenText: String {
        isAlarm ? "Bekliyor" : session.elapsed
    }

    private var detailText: String {
        switch session.status {
        case .busy, .waiting, .exited: return session.subtitle
        case .idle, .live:
            if session.activity != nil { return session.subtitle }
            let state: String
            switch session.origin {
            case .backgroundAgent: state = "Arka plan ajanı"
            case .external: state = "Harici oturum"
            case .center: state = session.kind == .shell ? "Terminal açık" : "Hazır"
            }
            return [session.usage?.model, state].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var metaColor: Color {
        switch session.status {
        case .waiting: return Theme.wait
        case .exited:  return Theme.error
        default:       return Theme.ink2
        }
    }

    /// Tek şekil, renkler ternary ile seçiliyor.
    ///
    /// Önceden `if/else` ile üç ayrı görünüm döndürüyordu; SwiftUI bunu
    /// `_ConditionalContent` olarak sarıyor ve dal değişince görünümü baştan
    /// kuruyor. Yani satır seçiliyken seçilmeze geçtiğinde renk **animasyonla
    /// değil, sıçrayarak** değişiyordu. Tek şekilde yapısal kimlik korunuyor.
    private var background: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(fillColor)
            .stroke(strokeColor, lineWidth: 1)
    }

    private var fillColor: Color {
        if isAlarm { return Theme.wait.opacity(0.11) }
        return isSelected ? Theme.selection : hovering ? Theme.choiceOn.opacity(0.55) : .clear
    }

    private var strokeColor: Color {
        isAlarm ? Theme.wait.opacity(0.26) : isFocused ? Theme.busy.opacity(0.4) : .clear
    }
}

/// Durum göstergesi. **Biçim de anlam taşıyor** — dolu nokta, halka, baklava.
/// Yalnızca renge yaslanan bir gösterge renk körü bir kullanıcıda çöker.
struct StatusDot: View {
    let status: Session.Status
    var origin: Session.Origin = .center

    var body: some View {
        switch status {
        case .waiting:
            // Dikkat her şeyin önünde: arka plan ajanı bile olsa turuncu nokta.
            filled(Theme.wait, halo: 0.20)
        case .busy:
            filled(origin == .backgroundAgent ? Theme.agent : Theme.busy, halo: 0.18)
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
