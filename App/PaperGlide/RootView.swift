import PaperGlideCore
import SwiftUI

struct RootView: View {
    @StateObject private var model: AppModel
    @ObservedObject var cloud: CloudModel
    @Environment(\.scenePhase) private var scenePhase

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
            #if DEBUG
            if LaunchOptions.analyticsReadout {
                AnalyticsQueueReadout(analytics: cloud.analytics)
            }
            #endif
        }
        .preferredColorScheme(.light)
        .tint(AppTheme.coral)
        .task {
            model.onRunFinished = { score, duration, isNewBest in
                Task { await cloud.record(score: score, duration: duration, isNewBest: isNewBest) }
            }
            await cloud.start()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .inactive:
                cloud.analytics.markInactive()
            case .background:
                cloud.analytics.enteredBackground()
            case .active:
                cloud.analytics.enteredForeground()
            @unknown default:
                break
            }
        }
    }
}

#if DEBUG
private struct AnalyticsQueueReadout: View {
    @ObservedObject var analytics: AnalyticsCenter

    var body: some View {
        let label = analytics.leaderboardQueueLabel()
        Text(label)
            .font(.system(size: 1))
            .opacity(0.01)
            .frame(width: 4, height: 4)
            .accessibilityIdentifier("analyticsQueue")
            .accessibilityLabel(label)
    }
}
#endif
