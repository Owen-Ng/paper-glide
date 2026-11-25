import SwiftUI

/// Start-screen confirmation. Cancel is the default. Delete is coral.
/// While the request runs, both buttons stay disabled and the status reads "Deleting...".
struct DeleteDataDialog: View {
    var deleting: Bool
    var onCancel: () -> Void
    var onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    if !deleting { onCancel() }
                }
            VStack(alignment: .leading, spacing: 14) {
                Text("Delete your data?")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityIdentifier("deleteTitle")
                Text("This removes your name, scores and reports from Paper Glide's servers and resets this device. Your name becomes free for anyone to take. This can't be undone.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("deleteBody")
                if deleting {
                    Text("Deleting...")
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.7))
                        .accessibilityIdentifier("deleteProgress")
                }
                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .disabled(deleting)
                        .accessibilityIdentifier("deleteCancel")
                    Button("Delete", action: onDelete)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.coral)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .disabled(deleting)
                        .accessibilityIdentifier("deleteConfirm")
                }
            }
            .padding(20)
            .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 28)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("deleteDialog")
        }
    }
}
