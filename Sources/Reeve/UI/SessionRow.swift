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
    var isHovered = false
    /// Açıkken adın yerinde bir metin alanı beliriyor — ayrı bir sayfa açılmıyor.
    var isEditing = false
    var onCommitName: ((String) -> Void)?
    var onCancelEdit: (() -> Void)?

    @State private var draft = ""
    @State private var cancelled = false
    @FocusState private var editorFocused: Bool

    private var isAlarm: Bool {
        if case .waiting = session.status { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SessionLeadingIcon(session: session)
                .frame(width: 18)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if isEditing {
                        TextField("", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .focused($editorFocused)
                            .onAppear {
                                draft = session.name
                                cancelled = false
                                editorFocused = true
                            }
                            .onSubmit { editorFocused = false }
                            .onExitCommand {
                                cancelled = true
                                editorFocused = false
                            }
                            // Odak kaybı tek çıkış kapısı: Enter da Esc de önce odayı
                            // bırakıyor, böylece iki kez işlenmiyor.
                            .onChange(of: editorFocused) { _, focused in
                                guard !focused else { return }
                                if cancelled { onCancelEdit?() } else { onCommitName?(draft) }
                            }
                    } else {
                        Text(session.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
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
                        .frame(width: 46, alignment: .trailing)
                        .opacity(isHovered ? 0 : 1)
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
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(background)
        .contentShape(Rectangle())
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
            .strokeBorder(strokeColor, lineWidth: Theme.hairline)
    }

    private var fillColor: Color {
        if isAlarm { return Theme.wait.opacity(0.11) }
        return isSelected ? Theme.selection : isHovered ? Theme.choiceOn : .clear
    }

    private var strokeColor: Color {
        isAlarm ? Theme.wait.opacity(0.26)
            : isFocused ? Theme.focusRule
            : isHovered ? Theme.rule : .clear
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
