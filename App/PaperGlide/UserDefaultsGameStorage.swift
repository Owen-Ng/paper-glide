import Foundation
import PaperGlideCore

/// Local best score and coach flag.
/// The app targets iOS 16, so this uses UserDefaults rather than SwiftData (iOS 17+).
final class UserDefaultsGameStorage: GameStorage {
    private let defaults: UserDefaults
    private let bestScoreKey = "paperGlide.bestScore"
    private let coachKey = "paperGlide.coachCompleted"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadBestScore() -> Int {
        defaults.integer(forKey: bestScoreKey)
    }

    func saveBestScore(_ score: Int) {
        defaults.set(score, forKey: bestScoreKey)
    }

    func loadCoachCompleted() -> Bool {
        defaults.bool(forKey: coachKey)
    }

    func saveCoachCompleted(_ completed: Bool) {
        defaults.set(completed, forKey: coachKey)
    }
}
