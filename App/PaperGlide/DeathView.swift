import PaperGlideCore
import SwiftUI

struct DeathView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var cloud: CloudModel
    @State private var draft = ""

    /// Rebuilt whenever the run score or the claimed name changes, so a name
    /// saved on this screen is what Share sends.
    private var shareText: String {
        ShareMessage.text(score: model.score, username: cloud.snapshot.username)
    }

    var body: some View {
        GeometryReader { geo in
            let tight = geo.size.height < 700
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

                VStack(spacing: tight ? 10 : 16) {
                    scoreBlock(tight: tight)
                        .fixedSize(horizontal: false, vertical: true)
                    actionCluster(tight: tight)
                        .fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        VStack(spacing: tight ? 10 : 16) {
                            if let note = cloud.deathNote {
                                Text(note)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(AppTheme.ink.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityIdentifier("deathSyncNote")
                            }
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
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, tight ? 8 : 16)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        }
    }

    private func scoreBlock(tight: Bool) -> some View {
        VStack(spacing: tight ? 8 : 16) {
            Text("The glide is over")
                .font(.system(tight ? .title : .largeTitle, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(model.score)")
                .font(.system(size: tight ? 52 : 64, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .accessibilityIdentifier("deathScore")
                .accessibilityLabel("Score \(model.score)")
            if model.isNewBest {
                Text("New best!")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, tight ? 4 : 6)
                    .background(AppTheme.coral, in: Capsule())
                    .accessibilityIdentifier("newBestLabel")
            }
            Text("Best \(model.bestScore)")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.8))
                .accessibilityIdentifier("bestScoreLabel")
                .accessibilityLabel("Best score \(model.bestScore)")
        }
    }

    private func actionCluster(tight: Bool) -> some View {
        VStack(spacing: 12) {
            Button(action: model.startRun) {
                Text("Retry")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, tight ? 2 : 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("retryButton")

            ShareLink(
                item: shareText,
                subject: Text(ShareMessage.subject),
                message: Text(shareText)
            ) {
                Text("Share")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, tight ? 2 : 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("shareButton")
            .id(shareText)

            Button(action: model.showHome) {
                Text("Home")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, tight ? 2 : 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("homeButton")

            Button("Leaderboard", action: model.showLeaderboard)
                .buttonStyle(.bordered)
                .font(.system(.body, design: .rounded))
                .accessibilityIdentifier("deathLeaderboardButton")
        }
        .padding(.horizontal, tight ? 24 : 48)
    }
}
