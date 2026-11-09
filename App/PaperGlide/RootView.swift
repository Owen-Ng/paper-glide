import PaperGlideCore
import SwiftUI

struct RootView: View {
    @StateObject private var model: AppModel
    @ObservedObject var cloud: CloudModel

    init(storage: GameStorage, cloud: CloudModel) {
        _model = StateObject(wrappedValue: AppModel(storage: storage))
        self.cloud = cloud
    }

    var body: some View {
        ZStack {
            switch model.screen {
            case .start:
                StartView(model: model, cloud: cloud)
            case .playing, .dead:
                PlayView(model: model)
            }
            if model.screen == .dead {
                DeathView(model: model, cloud: cloud)
            }
            if model.showingLeaderboard {
                LeaderboardView(cloud: cloud, localBest: model.bestScore, onBack: model.hideLeaderboard)
            }
        }
        .preferredColorScheme(.light)
        .tint(AppTheme.coral)
        .task {
            model.onRunFinished = { score, duration, isNewBest in
                Task { await cloud.record(score: score, duration: duration, isNewBest: isNewBest) }
            }
            await cloud.start()
        }
    }
}
