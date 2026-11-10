import Foundation

public struct BoardEntry: Codable, Equatable, Identifiable {
    public var rank: Int
    public var username: String
    public var score: Int
    public var isYou: Bool

    public var id: String { "\(rank)-\(username)" }

    public init(rank: Int, username: String, score: Int, isYou: Bool) {
        self.rank = rank
        self.username = username
        self.score = score
        self.isYou = isYou
    }
}

public struct LeaderboardPage: Codable, Equatable {
    public var entries: [BoardEntry]
    public var you: BoardEntry?
    public var fetchedAt: Date

    public init(entries: [BoardEntry], you: BoardEntry?, fetchedAt: Date) {
        self.entries = entries
        self.you = you
        self.fetchedAt = fetchedAt
    }

    public func marking(username: String?) -> LeaderboardPage {
        guard let username else {
            return LeaderboardPage(
                entries: entries.map { BoardEntry(rank: $0.rank, username: $0.username, score: $0.score, isYou: false) },
                you: nil,
                fetchedAt: fetchedAt
            )
        }
        let entries = entries.map { entry in
            BoardEntry(rank: entry.rank, username: entry.username, score: entry.score, isYou: entry.username == username)
        }
        let you: BoardEntry?
        if let existing = self.you, existing.username == username {
            you = BoardEntry(rank: existing.rank, username: existing.username, score: existing.score, isYou: true)
        } else if let mine = entries.first(where: { $0.username == username }) {
            you = mine
        } else {
            you = nil
        }
        return LeaderboardPage(entries: entries, you: you, fetchedAt: fetchedAt)
    }
}

public struct CachedBoard: Codable, Equatable {
    public var page: LeaderboardPage
    public var fetchedAt: Date

    public init(page: LeaderboardPage) {
        self.page = page
        self.fetchedAt = page.fetchedAt
    }
}

public struct RankedRun: Equatable {
    public var userID: String
    public var username: String
    public var score: Int
    public var playedAt: Date

    public init(userID: String, username: String, score: Int, playedAt: Date) {
        self.userID = userID
        self.username = username
        self.score = score
        self.playedAt = playedAt
    }
}

/// Best score per named player, competition rank, top 50.
/// The period filter is the late-run rule: a closed Toronto day or week drops off that board.
public enum LeaderboardMath {
    public static let pageSize = 50

    public static func page(runs: [RankedRun], period: BoardPeriod, at now: Date, viewerID: String?) -> LeaderboardPage {
        let open = runs.filter { RunRules.counts(period: period, playedAt: $0.playedAt, syncedAt: now) }
        var best: [String: RankedRun] = [:]
        for run in open {
            if let current = best[run.userID] {
                let betterScore = run.score > current.score
                let earlierTie = run.score == current.score && run.playedAt < current.playedAt
                if betterScore || earlierTie {
                    best[run.userID] = run
                }
            } else {
                best[run.userID] = run
            }
        }
        let ranked = best.values.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.playedAt != rhs.playedAt { return lhs.playedAt < rhs.playedAt }
            return lhs.username < rhs.username
        }
        func rank(of score: Int) -> Int {
            1 + ranked.filter { $0.score > score }.count
        }
        let entries = ranked.prefix(pageSize).map { run in
            BoardEntry(
                rank: rank(of: run.score),
                username: run.username,
                score: run.score,
                isYou: run.userID == viewerID
            )
        }
        let you = ranked.first { $0.userID == viewerID }.map { run in
            BoardEntry(rank: rank(of: run.score), username: run.username, score: run.score, isYou: true)
        }
        return LeaderboardPage(entries: Array(entries), you: you, fetchedAt: now)
    }
}
