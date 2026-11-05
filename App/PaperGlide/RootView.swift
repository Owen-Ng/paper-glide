import PaperGlideCore
import SwiftUI

struct RootView: View {
    @StateObject private var model: AppModel

    init(storage: GameStorage) {
        _model = StateObject(wrappedValue: AppModel(storage: storage))
    }

    var body: some View {
        Group {
            switch model.screen {
            case .start:
                StartView(bestScore: model.bestScore, onPlay: model.startRun)
            case .playing:
                PlayView(model: model)
            case .dead:
                DeathView(
                    score: model.score,
                    bestScore: model.bestScore,
                    isNewBest: model.isNewBest,
                    onRetry: model.startRun,
                    onHome: model.showHome
                )
            }
        }
        .preferredColorScheme(.light)
        .tint(AppTheme.coral)
    }
}
