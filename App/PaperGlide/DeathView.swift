import PaperGlideCore
import SwiftUI

struct DeathView: View {
    let score: Int
    let bestScore: Int
    let isNewBest: Bool
    let onRetry: () -> Void
    let onHome: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [AppTheme.skyTop, AppTheme.skyBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text("The glide is over")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                Text("\(score)")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityIdentifier("deathScore")
                    .accessibilityLabel("Score \(score)")
                if isNewBest {
                    Text("New best!")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(AppTheme.coral, in: Capsule())
                        .accessibilityIdentifier("newBestLabel")
                }
                Text("Best \(bestScore)")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.8))
                    .accessibilityIdentifier("bestScoreLabel")
                    .accessibilityLabel("Best score \(bestScore)")
                VStack(spacing: 12) {
                    Button(action: onRetry) {
                        Text("Retry")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("retryButton")

                    ShareLink(
                        item: ShareText.message(score: score),
                        subject: Text("Paper Glide"),
                        message: Text(ShareText.message(score: score))
                    ) {
                        Text("Share")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("shareButton")

                    Button(action: onHome) {
                        Text("Home")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("homeButton")
                }
                .padding(.horizontal, 48)
                .padding(.top, 8)
            }
            .padding()
        }
    }
}
