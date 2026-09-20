import SwiftUI

/// İkon ve toplamların tamamı aynı tıklama alanına ait.
struct GitSummaryButton: View {
    let added: Int
    let removed: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plusminus")
                    .font(.system(size: 13))
                HStack(spacing: 7) {
                    Text("+\(added)").foregroundStyle(Theme.diffAdd)
                    Text("−\(removed)").foregroundStyle(Theme.diffDel)
                }
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelControlStyle(backgroundInset: 3, minimumWidth: 128))
        .fixedSize()
        .accessibilityLabel("Git değişiklikleri: \(added) eklenen, \(removed) silinen satır")
        .help("Çalışma ağacındaki değişiklikleri aç / kapat")
    }
}

struct PanelIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelControlStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct PanelControlStyle: ButtonStyle {
    var backgroundInset: CGFloat = 0
    var minimumWidth: CGFloat? = nil
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovering ? Theme.ink : Theme.ink2)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Theme.button
                          : hovering ? Theme.selection : .clear)
                    .padding(backgroundInset)
            }
            .frame(minWidth: minimumWidth)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
