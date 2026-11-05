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
    @Published var showCoach = false

    init(storage: GameStorage) {
        self.storage = storage
        let session = GameSession(config: .standard, storage: storage, seed: 1)
        self.session = session
        let scene = PaperGlideScene(session: session)
        self.scene = scene
        bestScore = session.snapshot.bestScore
        showCoach = session.snapshot.showCoach
        scene.onSnapshot = { [weak self] snapshot in
            self?.consume(snapshot)
        }
    }

    func startRun() {
        session.reset(seed: randomSeed())
        score = 0
        bestScore = session.snapshot.bestScore
        showCoach = session.snapshot.showCoach
        screen = .playing
    }

    func showHome() {
        bestScore = storage.loadBestScore()
        screen = .start
    }

    func consume(_ snapshot: GameSnapshot) {
        score = snapshot.score
        bestScore = snapshot.bestScore
        showCoach = snapshot.showCoach
        if snapshot.phase == .dead, screen == .playing {
            screen = .dead
        }
    }

    private func randomSeed() -> UInt64 {
        var generator = SystemRandomNumberGenerator()
        let seed = generator.next()
        return seed == 0 ? 1 : seed
    }
}
