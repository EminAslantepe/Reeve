import SwiftUI

struct RenameSessionSheet: View {
    @State var name: String
    let onCancel: () -> Void
    let onSave: (String) -> Void
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Oturumu yeniden adlandır")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            TextField("Oturum adı", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { if !trimmed.isEmpty { onSave(trimmed) } }
            HStack {
                Spacer()
                Button("Vazgeç", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Kaydet") { onSave(trimmed) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 340)
        .background(Theme.sheetBG)
        .onAppear { focused = true }
    }
}
