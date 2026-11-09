import Foundation

public enum BoardCopy {
    public static let noScoreToday = "no score today yet"
    public static let noScoreWeek = "no score this week yet"
    public static let beFirst = "no scores yet today. be the first"
    public static let pickName = "pick a name to join the board"
    public static let syncing = "syncing..."
    public static let dailyReset = "resets at midnight, toronto time"
    public static let weeklyReset = "resets monday at midnight, toronto time"
    public static let chipPending = "not synced. we'll keep trying"
    public static let deathPending = "saved, will sync"
    public static let syncRetry = "couldn't sync your scores. retry"
    public static let offlineEmpty = "you're offline. the board will load when you're back online."
    public static let loadFailed = "couldn't load the board. Retry"

    public static func offlineCache(_ time: String) -> String {
        "offline. showing scores from \(time)"
    }

    public static func outside(rank: Int) -> String {
        "#\(rank) — you"
    }

    public static func localBest(_ score: Int) -> String {
        "local best \(score)"
    }

    public static func caption(for period: BoardPeriod) -> String? {
        switch period {
        case .daily: return dailyReset
        case .weekly: return weeklyReset
        case .allTime: return nil
        }
    }
}

public enum BoardTimeFormat {
    public static func string(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

public struct BoardPresentation: Equatable {
    public var showSkeleton: Bool
    public var entries: [BoardEntry]
    public var outsideLine: String?
    public var outsideScore: Int?
    public var emptyTitle: String?
    public var emptyDetail: String?
    public var banners: [String]
    public var showOfflineEmpty: Bool
    public var localBestLine: String?
    public var caption: String?
    public var canPullToRefresh: Bool

    public init(
        showSkeleton: Bool = false,
        entries: [BoardEntry] = [],
        outsideLine: String? = nil,
        outsideScore: Int? = nil,
        emptyTitle: String? = nil,
        emptyDetail: String? = nil,
        banners: [String] = [],
        showOfflineEmpty: Bool = false,
        localBestLine: String? = nil,
        caption: String? = nil,
        canPullToRefresh: Bool = false
    ) {
        self.showSkeleton = showSkeleton
        self.entries = entries
        self.outsideLine = outsideLine
        self.outsideScore = outsideScore
        self.emptyTitle = emptyTitle
        self.emptyDetail = emptyDetail
        self.banners = banners
        self.showOfflineEmpty = showOfflineEmpty
        self.localBestLine = localBestLine
        self.caption = caption
        self.canPullToRefresh = canPullToRefresh
    }
}

public enum BoardPresenter {
    public static func present(
        period: BoardPeriod,
        cached: CachedBoard?,
        loading: Bool,
        online: Bool,
        loadFailed: Bool,
        syncFailed: Bool,
        username: String?,
        localBest: Int,
        cacheTimeText: String?
    ) -> BoardPresentation {
        var banners: [String] = []
        if syncFailed {
            banners.append(BoardCopy.syncRetry)
        }
        let caption = BoardCopy.caption(for: period)

        guard let cached else {
            if !online {
                return BoardPresentation(
                    banners: banners,
                    showOfflineEmpty: true,
                    localBestLine: BoardCopy.localBest(localBest),
                    caption: caption,
                    canPullToRefresh: false
                )
            }
            if loading || !loadFailed {
                return BoardPresentation(showSkeleton: true, caption: caption, canPullToRefresh: true)
            }
            banners.append(BoardCopy.loadFailed)
            return BoardPresentation(banners: banners, caption: caption, canPullToRefresh: true)
        }

        if !online, let cacheTimeText {
            banners.insert(BoardCopy.offlineCache(cacheTimeText), at: 0)
        } else if loadFailed {
            banners.append(BoardCopy.loadFailed)
        }

        let entries = cached.page.entries
        var outsideLine: String?
        var outsideScore: Int?
        if let you = cached.page.you, !entries.contains(where: { $0.username == you.username }) {
            outsideLine = BoardCopy.outside(rank: you.rank)
            outsideScore = you.score
        }

        var emptyTitle: String?
        var emptyDetail: String?
        if entries.isEmpty {
            if username == nil {
                emptyTitle = BoardCopy.pickName
            } else if loading {
                emptyTitle = BoardCopy.syncing
            } else {
                switch period {
                case .daily:
                    emptyTitle = BoardCopy.noScoreToday
                    emptyDetail = BoardCopy.beFirst
                case .weekly:
                    emptyTitle = BoardCopy.noScoreWeek
                case .allTime:
                    emptyTitle = nil
                }
            }
        }

        return BoardPresentation(
            entries: entries,
            outsideLine: outsideLine,
            outsideScore: outsideScore,
            emptyTitle: emptyTitle,
            emptyDetail: emptyDetail,
            banners: banners,
            caption: caption,
            canPullToRefresh: online
        )
    }
}
