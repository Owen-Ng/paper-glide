import Foundation

/// Username shape, leetspeak blocklist, and the copy for a rejected name.
///
/// The client lowercases as the player types and can reject a shape locally.
/// Taken names and the blocklist are the server's decision. `problem(_:)` is the
/// shared check the mock backend applies, and the SQL migration mirrors it.
public enum UsernameRules {
    public static let minimumLength = 3
    public static let maximumLength = 16
    public static let reserved = ["admin", "paperglide", "support", "moderator", "apple", "official"]

    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Length, leading letter, and the allowed character set. Not the blocklist.
    public static func shapeProblem(_ raw: String) -> UsernameRejection? {
        let name = normalize(raw)
        if name.count < minimumLength {
            return .tooShort
        }
        guard let first = name.first, isASCIILetter(first) else {
            return .mustStartWithLetter
        }
        if name.count > maximumLength || !name.allSatisfy(isAllowed) {
            return .invalid
        }
        return nil
    }

    /// Shape plus the reserved-word blocklist after leetspeak folding.
    public static func problem(_ raw: String) -> UsernameRejection? {
        if let shape = shapeProblem(raw) {
            return shape
        }
        if blocks(normalize(raw)) {
            return .unavailable
        }
        return nil
    }

    /// True when the folded name contains a reserved word.
    /// Digits fold both ways where a glyph is ambiguous (`1` is `i` or `l`).
    /// Underscores are removed before the scan so `adm_in` matches `admin`.
    public static func blocks(_ raw: String) -> Bool {
        let folded = Array(normalize(raw).filter { $0 != "_" })
        for word in reserved where contains(folded, word: Array(word)) {
            return true
        }
        return false
    }

    private static func contains(_ folded: [Character], word: [Character]) -> Bool {
        guard !word.isEmpty, folded.count >= word.count else { return false }
        let lastStart = folded.count - word.count
        for start in 0...lastStart {
            var matched = true
            for offset in 0..<word.count where !letter(word[offset], matches: folded[start + offset]) {
                matched = false
                break
            }
            if matched {
                return true
            }
        }
        return false
    }

    private static func letter(_ letter: Character, matches ch: Character) -> Bool {
        switch letter {
        case "a": return ch == "a" || ch == "4"
        case "b": return ch == "b" || ch == "8"
        case "e": return ch == "e" || ch == "3"
        case "g": return ch == "g" || ch == "6" || ch == "9"
        case "i": return ch == "i" || ch == "1"
        case "l": return ch == "l" || ch == "1"
        case "o": return ch == "o" || ch == "0"
        case "s": return ch == "s" || ch == "5"
        case "t": return ch == "t" || ch == "7"
        case "z": return ch == "z" || ch == "2"
        default: return ch == letter
        }
    }

    private static func isASCIILetter(_ ch: Character) -> Bool {
        guard let value = ch.asciiValue else { return false }
        return value >= 97 && value <= 122
    }

    private static func isAllowed(_ ch: Character) -> Bool {
        if ch == "_" { return true }
        guard let value = ch.asciiValue else { return false }
        let isLetter = value >= 97 && value <= 122
        let isDigit = value >= 48 && value <= 57
        return isLetter || isDigit
    }
}

public enum UsernameRejection: String, Equatable {
    case tooShort
    case mustStartWithLetter
    case invalid
    case taken
    case unavailable
}

public enum NameCopy {
    public static let helper = "pick a name. letters, numbers and _ only. you can't change it later."
    public static let tooShort = "at least 3 characters"
    public static let startWithLetter = "start with a letter"
    public static let taken = "that name's taken. try another"
    public static let unavailable = "that name isn't available. try another"
    public static let invalid = "that name won't work. try another"
    public static let offline = "you're offline. we'll check this name when you're back"
    public static let saveFailed = "couldn't save. try again"

    /// The player-facing sentence. None of these include the name they typed.
    public static func message(for rejection: UsernameRejection) -> String {
        switch rejection {
        case .tooShort: return tooShort
        case .mustStartWithLetter: return startWithLetter
        case .invalid: return invalid
        case .taken: return taken
        case .unavailable: return unavailable
        }
    }
}
