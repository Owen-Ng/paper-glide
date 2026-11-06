import Foundation
import PaperGlideCore
import SwiftUI

final class AppModel: ObservableObject {
    enum Screen {
        case start
        case playing
        case dead
    }

    let storage: GameStorage
    let session: GameSession
    let scene: PaperGlideScene

    @Published var screen: Screen = .start
    @Published var score = 0
    @Published var bestScore = 0
    @Published var isNewBest = false
    @Published var showCoach = false
    @Published var planeY: Double = 0
    @Published var guidedTargetY: Double = 0
    @Published var flightAdvice = "coast"

    init(storage: GameStorage) {
        self.storage = storage
        let session = GameSession(config: .standard, storage: storage, seed: 1)
        self.session = session
        let scene = PaperGlideScene(session: session)
        self.scene = scene
        bestScore = session.snapshot.bestScore
        showCoach = session.snapshot.showCoach
        refreshFlightReadout(session.snapshot)
        scene.onSnapshot = { [weak self] snapshot in
            self?.consume(snapshot)
        }
    }

    func startRun() {
        session.reset(seed: LaunchOptions.seed ?? randomSeed())
        score = 0
        bestScore = session.snapshot.bestScore
        isNewBest = false
        showCoach = session.snapshot.showCoach
        refreshFlightReadout(session.snapshot)
        screen = .playing
    }

    func showHome() {
        bestScore = storage.loadBestScore()
        isNewBest = false
        screen = .start
    }

    /// Test hook. The first coach tap ends the run at a chosen score. Physics does not run.
    func recordScriptedGlideTap() {
        let coachWasShowing = session.snapshot.showCoach
        session.tap()
        if coachWasShowing, let score = LaunchOptions.scriptedEndScore {
            session.endRun(withScore: score)
        }
        consume(session.snapshot)
    }

    /// One real impulse, then `guidedStride` seconds of the real simulation.
    func guidedTap() {
        advanceGuidedStride(tap: true)
    }

    /// `guidedStride` seconds of the real simulation with no impulse, so gravity can pull the plane down.
    func guidedCoast() {
        advanceGuidedStride(tap: false)
    }

    func consume(_ snapshot: GameSnapshot) {
        score = snapshot.score
        bestScore = snapshot.bestScore
        isNewBest = snapshot.isNewBest
        showCoach = snapshot.showCoach
        refreshFlightReadout(snapshot)
        if snapshot.phase == .dead, screen == .playing {
            screen = .dead
        }
    }

    private func advanceGuidedStride(tap: Bool) {
        guard let stride = LaunchOptions.guidedStride else { return }
        GlidePilot.advance(session, stride: stride, tap: tap)
        consume(session.snapshot)
    }

    private func refreshFlightReadout(_ snapshot: GameSnapshot) {
        planeY = snapshot.plane.y
        guidedTargetY = GlidePilot.upcomingGapCenter(
            plane: snapshot.plane,
            obstacles: snapshot.obstacles,
            fallback: session.config.planeStartY
        )
        flightAdvice = GlidePilot.shouldTap(
            snapshot: snapshot,
            fallbackTarget: session.config.planeStartY
        ) ? "tap" : "coast"
    }

    private func randomSeed() -> UInt64 {
        var generator = SystemRandomNumberGenerator()
        let seed = generator.next()
        return seed == 0 ? 1 : seed
    }
}
