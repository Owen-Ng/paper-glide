import PaperGlideCore
import SwiftUI

struct NamePromptCard: View {
    @Binding var draft: String
    var error: String?
    var showsLater: Bool
    var onSave: () -> Void
    var onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NameCopy.helper)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("nameHelper")
            TextField("name", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.asciiCapable)
                .font(.system(.body, design: .rounded))
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.ink.opacity(0.15), lineWidth: 1)
                )
                .accessibilityIdentifier("nameField")
                .onChange(of: draft) { value in
                    let lowered = value.lowercased()
                    if lowered != value {
                        draft = lowered
                    }
                }
            if let error {
                Text(error)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(AppTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nameError")
            }
            HStack(spacing: 10) {
                Button("save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("nameSaveButton")
                if showsLater {
                    Button("later", action: onLater)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("nameLaterButton")
                }
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
        }
        .padding(14)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.ink.opacity(0.08), lineWidth: 1)
        )
    }
}
