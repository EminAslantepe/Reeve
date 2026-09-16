import AppKit
import SwiftUI

/// `+` / ⌘N penceresi — mockup'ın "Yeni oturum" sheet'i.
///
/// Mockup'ta bir de **Model** açılır menüsü ve **Claude (arka plan)** seçeneği var.
/// İkisi de Faz 2'ye ait (model listesi ve `--bg`'nin PTY'siz yaşam döngüsü);
/// çalışmayan kontrol koymamak için şimdilik yoklar.
struct NewSessionSheet: View {
    @State var cwd: String
    @State var template: Template = .claude
    @State var name: String
    let recents: [String]
    let onCancel: () -> Void
    let onOpen: (String, Template, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Yeni oturum")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 16)

            field("Klasör") {
                HStack(spacing: 6) {
                    Menu {
                        ForEach(recents, id: \.self) { path in
                            Button(shorten(path)) { cwd = path; refreshName() }
                        }
                    } label: {
                        HStack {
                            Text(shorten(cwd))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.ink3)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(controlShape)
                    }
                    // .borderlessButton kendi ok işaretini solda çiziyor ve özel
                    // etiketin arka planını yutuyor; .button + .plain etiketi koruyor.
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)

                    Button("Gözat…") { browse() }
                        .buttonStyle(SheetButton(primary: false))
                }
            }

            field("Ne çalışsın?") {
                VStack(spacing: 1) {
                    ForEach(Template.allCases) { option in
                        choice(option)
                    }
                }
            }

            field("İsim") {
                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(controlShape)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("İptal", action: onCancel)
                    .buttonStyle(SheetButton(primary: false))
                    .keyboardShortcut(.cancelAction)
                Button { onOpen(cwd, template, trimmedName) } label: {
                    HStack(spacing: 6) {
                        Text("Aç")
                        Text("⏎").opacity(0.7).font(.system(size: 11))
                    }
                }
                .buttonStyle(SheetButton(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 15)
        .frame(width: 380)
        .background(Theme.sheetBG)
    }

    // MARK: - Parçalar

    private func field<Content: View>(_ label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink2)
            content()
        }
        .padding(.bottom, 14)
    }

    private func choice(_ option: Template) -> some View {
        let on = template == option
        return HStack(spacing: 9) {
            ZStack {
                Circle()
                    .strokeBorder(on ? Theme.primary : Theme.ink3, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                if on {
                    Circle().fill(Theme.primary).frame(width: 6, height: 6)
                }
            }
            Text(option.title)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text(option.hint)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(on ? Theme.choiceOn : .clear))
        .contentShape(Rectangle())
        .onTapGesture { template = option }
    }

    private var controlShape: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Theme.control)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.rule, lineWidth: 1))
    }

    // MARK: - Yardımcılar

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shorten(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func refreshName() {
        name = SessionFactory.name(for: cwd, existing: [])
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: cwd)
        if panel.runModal() == .OK, let url = panel.url {
            cwd = url.path
            refreshName()
        }
    }
}

private struct SheetButton: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: primary ? .medium : .regular))
            .foregroundStyle(primary ? Color.white : Theme.ink)
            .padding(.horizontal, 13)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(primary ? Theme.primary : Theme.button))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
