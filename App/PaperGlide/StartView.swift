import SwiftUI

struct StartView: View {
    let bestScore: Int
    let onPlay: () -> Void

    var body: some View {
        ZStack {
            background
            VStack(spacing: 22) {
                Spacer()
                mark
                Text("Paper Glide")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("Glide a paper plane through open windows.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Text("Best score \(bestScore)")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityIdentifier("startBestScore")
                    .accessibilityLabel("Best score \(bestScore)")
                Button(action: onPlay) {
                    Text("Play")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("playButton")
                .padding(.horizontal, 48)
                .padding(.top, 8)
                VStack(spacing: 10) {
                    Button("Leaderboard — coming soon") {}
                        .disabled(true)
                    Button("Report — coming soon") {}
                        .disabled(true)
                }
                .buttonStyle(.bordered)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 48)
                Spacer()
            }
        }
    }

    private var background: some View {
        LinearGradient(colors: [AppTheme.skyTop, AppTheme.skyBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var mark: some View {
        HStack(spacing: 18) {
            WindowGlyph()
                .fill(AppTheme.coral.opacity(0.9), style: FillStyle(eoFill: true))
                .frame(width: 54, height: 78)
            PaperPlaneGlyph()
                .fill(AppTheme.paper)
                .overlay(PaperPlaneGlyph().stroke(AppTheme.ink.opacity(0.45), lineWidth: 1.5))
                .frame(width: 86, height: 36)
        }
        .accessibilityHidden(true)
    }
}

struct PaperPlaneGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.94, y: rect.height * 0.50))
        path.addLine(to: CGPoint(x: rect.width * 0.06, y: rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.width * 0.30, y: rect.height * 0.50))
        path.addLine(to: CGPoint(x: rect.width * 0.06, y: rect.height * 0.84))
        path.closeSubpath()
        return path
    }
}

struct WindowGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: 8, height: 8))
        let opening = rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.30)
        path.addRoundedRect(in: opening, cornerSize: CGSize(width: 4, height: 4))
        return path
    }
}
