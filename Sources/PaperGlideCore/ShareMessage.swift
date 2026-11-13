import Foundation

/// Text shared from the death screen. Pure: the same score and username always
/// produce the same string, and the caller passes the values it has at tap time.
public enum ShareMessage {
    public static let subject = "Paper Glide"

    /// `username` is the claimed name, or nil when the player has not claimed one.
    /// Blank text counts as no name. The score is this run's integer score.
    public static func text(score: Int, username: String?) -> String {
        let name = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty {
            return "I scored \(score) in Paper Glide"
        }
        return "I scored \(score) in Paper Glide as \(name)"
    }
}
