/// Persistence seam for the local best score and the one-time coach flag.
/// The iOS app stores these in UserDefaults. Tests use `InMemoryGameStorage`.
public protocol GameStorage: AnyObject {
    func loadBestScore() -> Int
    func saveBestScore(_ score: Int)
    func loadCoachCompleted() -> Bool
    func saveCoachCompleted(_ completed: Bool)
}

public final class InMemoryGameStorage: GameStorage {
    private var bestScore: Int
    private var coachCompleted: Bool

    public init(bestScore: Int = 0, coachCompleted: Bool = false) {
        self.bestScore = bestScore
        self.coachCompleted = coachCompleted
    }

    public func loadBestScore() -> Int {
        bestScore
    }

    public func saveBestScore(_ score: Int) {
        bestScore = score
    }

    public func loadCoachCompleted() -> Bool {
        coachCompleted
    }

    public func saveCoachCompleted(_ completed: Bool) {
        coachCompleted = completed
    }
}
