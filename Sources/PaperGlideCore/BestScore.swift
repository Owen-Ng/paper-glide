/// Whether a finished run replaces the stored best.
public enum BestScore {
    /// Strictly greater than the stored best. A tie is not a record.
    /// A first run that scores 0 against a stored 0 is not a record.
    /// A first run that scores above 0 against a stored 0 is.
    public static func isNewRecord(score: Int, previousBest: Int) -> Bool {
        score > previousBest
    }
}
