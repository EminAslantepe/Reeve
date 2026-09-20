import SwiftUI

/// ⌘F — görünür terminallerde arama (addon-search).
/// Terminalin üstüne biniyor, yerleşime katılmıyor: her açılışta panoları yeniden
/// boyutlandırmak boşuna SIGWINCH zinciri tetiklerdi.
struct FindBar: View {
    let onFind: (String, Bool) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.ink3)
            TextField("terminalde ara", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
                .frame(width: 170)
                .focused($focused)
                .onSubmit { onFind(query, true) }
                .onKeyPress(.escape) { onClose(); return .handled }
            stepper("chevron.up") { onFind(query, false) }
            stepper("chevron.down") { onFind(query, true) }
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.paletteBG)
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.paletteBorder, lineWidth: Theme.hairline)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .onAppear { focused = true }
    }

    private func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.ink2)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(query.isEmpty)
    }
}
