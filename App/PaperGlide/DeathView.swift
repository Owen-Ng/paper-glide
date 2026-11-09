import PaperGlideCore
import SwiftUI

struct DeathView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var cloud: CloudModel
    @State private var draft = ""

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: AppTheme.paper.opacity(0.22), location: 0),
                    .init(color: AppTheme.paper.opacity(0.34), location: 0.22),
                    .init(color: AppTheme.paper.opacity(0.90), location: 0.42),
                    .init(color: AppTheme.paper.opacity(1), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 16) {
                        Text("The glide is over")
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.center)
                        Text("\(model.score)")
                            .font(.system(size: 64, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                            .accessibilityIdentifier("deathScore")
                            .accessibilityLabel("Score \(model.score)")
                        if model.isNewBest {
                            Text("New best!")
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(AppTheme.coral, in: Capsule())
                                .accessibilityIdentifier("newBestLabel")
                        }
                        Text("Best \(model.bestScore)")
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(AppTheme.ink.opacity(0.8))
                            .accessibilityIdentifier("bestScoreLabel")
                            .accessibilityLabel("Best score \(model.bestScore)")
                        if let note = cloud.deathNote {
                            Text(note)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(AppTheme.ink.opacity(0.7))
                                .accessibilityIdentifier("deathSyncNote")
                        }
                        VStack(spacing: 12) {
                            Button(action: model.startRun) {
                                Text("Retry")
                                    .font(.system(.title3, design: .rounded).weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityIdentifier("retryButton")

                            ShareLink(
                                item: ShareText.message(score: model.score),
                                subject: Text("Paper Glide"),
                                message: Text(ShareText.message(score: model.score))
                            ) {
                                Text("Share")
                                    .font(.system(.title3, design: .rounded).weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .accessibilityIdentifier("shareButton")

                            Button(action: model.showHome) {
                                Text("Home")
                                    .font(.system(.title3, design: .rounded).weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .accessibilityIdentifier("homeButton")

                            Button("Leaderboard", action: model.showLeaderboard)
                                .buttonStyle(.bordered)
                                .font(.system(.body, design: .rounded))
                                .accessibilityIdentifier("deathLeaderboardButton")
                        }
                        .padding(.horizontal, 48)
                        .padding(.top, 8)
                        if cloud.snapshot.deathPromptVisible {
                            NamePromptCard(
                                draft: $draft,
                                error: cloud.snapshot.nameError,
                                showsLater: true,
                                onSave: { Task { await cloud.claim(draft) } },
                                onLater: cloud.dismissDeath
                            )
                            .padding(.horizontal, 32)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    .padding()
                }
            }
        }
    }
}
