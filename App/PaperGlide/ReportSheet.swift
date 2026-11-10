import PaperGlideCore
import SwiftUI

struct ReportSheet: View {
    var onClose: () -> Void
    var onSend: (String, String) async -> ReportSendResult
    var onFinished: (ReportSendResult) -> Void

    @State private var category: String?
    @State private var text = ""
    @State private var sending = false
    @State private var confirmDiscard = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { requestClose() }
            ScrollView {
                card
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
            }
        }
        .accessibilityIdentifier("reportSheet")
        .alert(ReportCopy.discardTitle, isPresented: $confirmDiscard) {
            Button(ReportCopy.discard, role: .destructive, action: onClose)
            Button(ReportCopy.keepWriting, role: .cancel) {}
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(AppTheme.ink.opacity(0.2))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
            Text(ReportCopy.title)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .accessibilityIdentifier("reportTitle")
            Text(ReportCopy.line)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reportLine")
            VStack(spacing: 8) {
                ForEach(ReportCategory.allCases, id: \.rawValue) { item in
                    Button {
                        category = item.rawValue
                    } label: {
                        HStack {
                            Text(item.rawValue)
                                .font(.system(.body, design: .rounded))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            if category == item.rawValue {
                                Image(systemName: "checkmark")
                            }
                        }
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            category == item.rawValue ? AppTheme.coral.opacity(0.16) : Color.white,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.ink.opacity(category == item.rawValue ? 0.28 : 0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(sending)
                    .accessibilityIdentifier("reportCategory-\(item.rawValue)")
                }
            }
            VStack(alignment: .trailing, spacing: 4) {
                TextField(ReportCopy.placeholder, text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(.body, design: .rounded))
                    .padding(10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.ink.opacity(0.15), lineWidth: 1)
                    )
                    .disabled(sending)
                    .accessibilityIdentifier("reportText")
                    .onChange(of: text) { value in
                        let clamped = ReportDraftRules.clamped(value)
                        if clamped != value {
                            text = clamped
                        }
                    }
                if ReportDraftRules.showsCounter(text) {
                    Text(ReportDraftRules.counter(text))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(AppTheme.ink.opacity(0.55))
                        .accessibilityIdentifier("reportCounter")
                }
            }
            Text(ReportCopy.smallPrint)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reportSmallPrint")
            HStack {
                Button(ReportCopy.cancel, action: requestClose)
                    .font(.system(.body, design: .rounded))
                    .disabled(sending)
                    .accessibilityIdentifier("reportCancel")
                Spacer()
                Button(action: { Task { await send() } }) {
                    if sending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(ReportCopy.send)
                    }
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .buttonStyle(.borderedProminent)
                .disabled(!ReportDraftRules.sendEnabled(category: category) || sending)
                .accessibilityIdentifier("reportSend")
            }
        }
        .padding(18)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.ink.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .offset(y: dragOffset)
        .gesture(
            DragGesture().onChanged { value in
                guard !sending else { return }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !sending else { return }
                if value.translation.height > 80 {
                    requestClose()
                }
                dragOffset = 0
            }
        )
    }

    private func requestClose() {
        guard !sending else { return }
        if ReportDraftRules.shouldConfirmDiscard(text: text) {
            confirmDiscard = true
        } else {
            onClose()
        }
    }

    private func send() async {
        guard let category, ReportDraftRules.sendEnabled(category: category), !sending else { return }
        sending = true
        let result = await onSend(category, text)
        onFinished(result)
    }
}
