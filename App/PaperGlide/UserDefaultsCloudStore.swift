import Foundation
import PaperGlideCore

/// Runs, the claimed name, and cached boards. Session tokens are not stored here.
final class UserDefaultsCloudStore: CloudStore {
    static let runsKey = "paperGlide.runs"
    static let usernameKey = "paperGlide.username"
    static let userIDKey = "paperGlide.userID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func boardKey(_ period: BoardPeriod) -> String {
        "paperGlide.board.\(period.rawValue)"
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: runsKey)
        defaults.removeObject(forKey: usernameKey)
        defaults.removeObject(forKey: userIDKey)
        for period in BoardPeriod.allCases {
            defaults.removeObject(forKey: boardKey(period))
        }
    }

    func loadRuns() -> [StoredRun] {
        decode([StoredRun].self, key: Self.runsKey) ?? []
    }

    func saveRuns(_ runs: [StoredRun]) {
        encode(runs, key: Self.runsKey)
    }

    func loadUsername() -> String? {
        defaults.string(forKey: Self.usernameKey)
    }

    func saveUsername(_ username: String?) {
        if let username {
            defaults.set(username, forKey: Self.usernameKey)
        } else {
            defaults.removeObject(forKey: Self.usernameKey)
        }
    }

    func loadUserID() -> String? {
        defaults.string(forKey: Self.userIDKey)
    }

    func saveUserID(_ userID: String?) {
        if let userID {
            defaults.set(userID, forKey: Self.userIDKey)
        } else {
            defaults.removeObject(forKey: Self.userIDKey)
        }
    }

    func loadBoard(_ period: BoardPeriod) -> CachedBoard? {
        decode(CachedBoard.self, key: Self.boardKey(period))
    }

    func saveBoard(_ board: CachedBoard?, period: BoardPeriod) {
        if let board {
            encode(board, key: Self.boardKey(period))
        } else {
            defaults.removeObject(forKey: Self.boardKey(period))
        }
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
