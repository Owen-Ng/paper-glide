import Foundation
import PaperGlideCore

/// Local best score and coach flag.
/// The app targets iOS 16, so this uses UserDefaults rather than SwiftData (iOS 17+).
final class UserDefaultsGameStorage: GameStorage {
    static let bestScoreKey = "paperGlide.bestScore"
    static let coachKey = "paperGlide.coachCompleted"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func clearPersistedProgress(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: bestScoreKey)
        defaults.removeObject(forKey: coachKey)
    }

    func loadBestScore() -> Int {
        defaults.integer(forKey: Self.bestScoreKey)
    }

    func saveBestScore(_ score: Int) {
        defaults.set(score, forKey: Self.bestScoreKey)
    }

    func loadCoachCompleted() -> Bool {
        defaults.bool(forKey: Self.coachKey)
    }

    func saveCoachCompleted(_ completed: Bool) {
        defaults.set(completed, forKey: Self.coachKey)
    }
}
