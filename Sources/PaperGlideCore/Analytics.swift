import Foundation

/// Locked click names. Start, playing, and leaderboard only.
public enum ClickMap {
    public static let start = ["play", "leaderboard", "report", "other"]
    public static let playing = ["flap"]
    public static let leaderboard = ["Today", "This week", "All time", "back", "other", "scroll"]
    public static let pages = ["start", "playing", "leaderboard"]

    public static func leaderboardPeriod(_ period: BoardPeriod) -> String {
        switch period {
        case .daily: return "Today"
        case .weekly: return "This week"
        case .allTime: return "All time"
        }
    }
}

public struct TapPoint: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct TapRect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(_ point: TapPoint) -> Bool {
        point.x >= x && point.y >= y && point.x < x + width && point.y < y + height
    }
}

/// Classifies a tap from control frames. One tap, one control. Text is never included.
public enum ClickHit {
    public static func startControl(at point: TapPoint, play: TapRect, leaderboard: TapRect, report: TapRect) -> String {
        if play.contains(point) { return "play" }
        if leaderboard.contains(point) { return "leaderboard" }
        if report.contains(point) { return "report" }
        return "other"
    }

    /// `isDrag` is one scroll gesture. A drag that starts outside the list is not a scroll click.
    public static func leaderboardControl(
        at point: TapPoint,
        back: TapRect,
        picker: TapRect,
        list: TapRect,
        isDrag: Bool
    ) -> String? {
        if isDrag {
            return list.contains(point) ? "scroll" : nil
        }
        if back.contains(point) { return "back" }
        if picker.width > 0, picker.contains(point) {
            let third = picker.width / 3
            let index = min(2, max(0, Int((point.x - picker.x) / third)))
            return ClickMap.leaderboard[index]
        }
        return "other"
    }

    /// Nil when a named control owns the tap. Otherwise one "other" click.
    public static func backgroundControl(at point: TapPoint, owned: [TapRect]) -> String? {
        if owned.contains(where: { $0.contains(point) }) { return nil }
        return "other"
    }
}

public enum ReportCategory: String, CaseIterable, Codable, Equatable {
    case crashed = "The game crashed or froze"
    case looks = "Something looks wrong"
    case leaderboard = "Leaderboard or my name"
    case idea = "I have an idea"
    case other = "Something else"
}

public enum ReportCopy {
    public static let title = "Report a problem"
    public static let line = "tell us what went wrong. we'll read every one."
    public static let placeholder = "what happened? (optional)"
    public static let smallPrint = "we'll include your app version and device model. no other info."
    public static let send = "Send"
    public static let cancel = "Cancel"
    public static let discardTitle = "discard this report?"
    public static let discard = "Discard"
    public static let keepWriting = "Keep writing"
    public static let thanks = "thanks. we got it"
    public static let saved = "saved. we'll send it when you're back online"
    public static let button = "Report a problem"

    public static var surface: [String] {
        [
            title, line, placeholder, smallPrint, send, cancel,
            discardTitle, discard, keepWriting, thanks, saved, button
        ] + ReportCategory.allCases.map(\.rawValue)
    }
}

public enum ReportDraftRules {
    public static let limit = 500
    public static let counterFrom = 400
    public static let sendTimeout: TimeInterval = 5

    public static func clamped(_ text: String) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit))
    }

    public static func showsCounter(_ text: String) -> Bool {
        text.count >= counterFrom
    }

    public static func counter(_ text: String) -> String {
        "\(min(text.count, limit))/\(limit)"
    }

    public static func sendEnabled(category: String?) -> Bool {
        guard let category else { return false }
        return ReportCategory(rawValue: category) != nil
    }

    /// Typed text asks before closing. A category alone does not.
    public static func shouldConfirmDiscard(text: String) -> Bool {
        !text.isEmpty
    }
}

public struct AnalyticsContext: Codable, Equatable {
    public var appVersion: String
    public var iosVersion: String
    public var deviceModel: String

    public init(appVersion: String, iosVersion: String, deviceModel: String) {
        self.appVersion = appVersion
        self.iosVersion = iosVersion
        self.deviceModel = deviceModel
    }
}

public enum AnalyticsKind: String, Codable, Equatable {
    case sessionStart = "session_start"
    case click
    case crash
    case report
}

public struct QueuedEvent: Codable, Equatable, Identifiable {
    public var id: String
    public var kind: AnalyticsKind
    public var occurredAt: Date
    public var sessionID: String?
    public var page: String?
    public var control: String?
    public var count: Int?
    public var category: String?
    /// Report body only. Click events leave this nil.
    public var text: String?
    public var context: AnalyticsContext?
    public var crashKind: String?
    public var crashSummary: String?
    public var crashDetails: String?

    public init(
        id: String,
        kind: AnalyticsKind,
        occurredAt: Date,
        sessionID: String? = nil,
        page: String? = nil,
        control: String? = nil,
        count: Int? = nil,
        category: String? = nil,
        text: String? = nil,
        context: AnalyticsContext? = nil,
        crashKind: String? = nil,
        crashSummary: String? = nil,
        crashDetails: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.sessionID = sessionID
        self.page = page
        self.control = control
        self.count = count
        self.category = category
        self.text = text
        self.context = context
        self.crashKind = crashKind
        self.crashSummary = crashSummary
        self.crashDetails = crashDetails
    }
}

public enum SessionExit: String, Codable, Equatable {
    case active
    case inactive
    case background
    case terminated
}

public struct ExitRecord: Codable, Equatable {
    public var sessionID: String
    public var state: SessionExit
    public var startedAt: Date
    /// When the session left the foreground. Used for the 30-minute resume rule.
    public var backgroundedAt: Date?
    public var context: AnalyticsContext

    public init(
        sessionID: String,
        state: SessionExit,
        startedAt: Date,
        backgroundedAt: Date? = nil,
        context: AnalyticsContext
    ) {
        self.sessionID = sessionID
        self.state = state
        self.startedAt = startedAt
        self.backgroundedAt = backgroundedAt
        self.context = context
    }
}

public struct PendingUnclean: Codable, Equatable {
    public var sessionID: String
    public var startedAt: Date

    public init(sessionID: String, startedAt: Date) {
        self.sessionID = sessionID
        self.startedAt = startedAt
    }
}

public struct InflightBatch: Codable, Equatable {
    public var id: String
    public var events: [QueuedEvent]

    public init(id: String, events: [QueuedEvent]) {
        self.id = id
        self.events = events
    }
}

public struct AnalyticsDiskState: Codable, Equatable {
    public var pending: [QueuedEvent]
    public var inflight: InflightBatch?
    public var exit: ExitRecord?
    public var sessionID: String?
    public var pendingUnclean: PendingUnclean?
    public var deliveredCrashIDs: [String]
    public var lastTimerAt: Date?

    public init(
        pending: [QueuedEvent] = [],
        inflight: InflightBatch? = nil,
        exit: ExitRecord? = nil,
        sessionID: String? = nil,
        pendingUnclean: PendingUnclean? = nil,
        deliveredCrashIDs: [String] = [],
        lastTimerAt: Date? = nil
    ) {
        self.pending = pending
        self.inflight = inflight
        self.exit = exit
        self.sessionID = sessionID
        self.pendingUnclean = pendingUnclean
        self.deliveredCrashIDs = deliveredCrashIDs
        self.lastTimerAt = lastTimerAt
    }

    public static let empty = AnalyticsDiskState()
}

/// Foreground kill with no background or terminate mark is an unclean exit.
/// User kill and background termination are not crashes.
public enum StableHash {
    public static func fnv(_ text: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }
}

public enum CrashExit {
    public static func countsAsCrash(_ state: SessionExit?) -> Bool {
        state == .active
    }
}

public enum LaunchClassification: Equatable {
    case clean
    case unclean(sessionID: String)
}

public enum AnalyticsAck: Equatable {
    case stored
    case duplicate
}

public enum AnalyticsTransportError: Error, Equatable {
    case unreachable
    case unauthorized
    case badResponse
}

public protocol AnalyticsTransport: AnyObject {
    func submitBatch(id: String, events: [QueuedEvent], accessToken: String) async throws -> AnalyticsAck
}

public protocol AnalyticsStateStore: AnyObject {
    func load() -> AnalyticsDiskState
    func save(_ state: AnalyticsDiskState)
}

public final class MemoryAnalyticsStore: AnalyticsStateStore {
    public var state: AnalyticsDiskState

    public init(state: AnalyticsDiskState = .empty) {
        self.state = state
    }

    public func load() -> AnalyticsDiskState { state }

    public func save(_ state: AnalyticsDiskState) { self.state = state }
}

public final class FileAnalyticsStore: AnalyticsStateStore {
    private let url: URL

    public init(directory: URL) {
        let folder = directory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("analytics-queue.json")
    }

    public func load() -> AnalyticsDiskState {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AnalyticsDiskState.self, from: data)) ?? .empty
    }

    public func save(_ state: AnalyticsDiskState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// In-memory click totals. `increment` does not allocate events, touch disk, or schedule work.
public final class ClickCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    public init() {}

    public func increment(page: String, control: String) {
        let key = page + "\u{1}" + control
        lock.lock()
        counts[key, default: 0] += 1
        lock.unlock()
    }

    public func total(page: String, control: String) -> Int {
        let key = page + "\u{1}" + control
        lock.lock()
        defer { lock.unlock() }
        return counts[key, default: 0]
    }

    public func drain() -> [(page: String, control: String, count: Int)] {
        lock.lock()
        let snapshot = counts
        counts.removeAll(keepingCapacity: true)
        lock.unlock()
        return snapshot.map { key, count in
            let parts = key.split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
            let page = parts.first.map(String.init) ?? ""
            let control = parts.count > 1 ? String(parts[1]) : ""
            return (page, control, count)
        }.sorted { lhs, rhs in
            if lhs.page == rhs.page { return lhs.control < rhs.control }
            return lhs.page < rhs.page
        }
    }
}

public enum ReportSendResult: Equatable {
    case sent
    case savedOffline
}

public enum AnalyticsFlushReason {
    case threshold
    case timer
    case background
    case manual
}

/// Disk-backed batch queue. The server dedupes a retried batch by its id.
public final class AnalyticsClient: @unchecked Sendable {
    public static let batchSize = 50
    public static let flushInterval: TimeInterval = 60
    public static let uncleanAttachWindow: TimeInterval = 3 * 24 * 60 * 60
    /// A return to the foreground after this long in the background starts a new session.
    public static let newSessionAfterBackground: TimeInterval = 30 * 60

    public let counters = ClickCounters()
    private let store: AnalyticsStateStore
    private let transport: AnalyticsTransport
    private let token: () async -> String?
    private let makeID: () -> String
    private let lock = NSLock()
    private var state: AnalyticsDiskState
    private var context: AnalyticsContext
    private var launched = false
    private var flushing = false

    public init(
        store: AnalyticsStateStore,
        transport: AnalyticsTransport,
        context: AnalyticsContext = AnalyticsContext(appVersion: "0", iosVersion: "0", deviceModel: "test"),
        token: @escaping () async -> String? = { "test-token" },
        makeID: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.store = store
        self.transport = transport
        self.token = token
        self.makeID = makeID
        self.context = context
        state = store.load()
    }

    public var queuedEventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return state.pending.count + (state.inflight?.events.count ?? 0)
    }

    public var inflightBatchID: String? {
        lock.lock()
        defer { lock.unlock() }
        return state.inflight?.id
    }

    /// One in-memory increment. Safe on the tap path.
    public func recordClick(page: String, control: String) {
        counters.increment(page: page, control: control)
    }

    /// In-memory clicks plus any already drained into the disk queue.
    public func queuedClickCount(page: String, control: String) -> Int {
        let memory = counters.total(page: page, control: control)
        lock.lock()
        defer { lock.unlock() }
        let stored = state.pending + (state.inflight?.events ?? [])
        let queued = stored.reduce(0) { partial, event in
            guard event.kind == .click, event.page == page, event.control == control else { return partial }
            return partial + (event.count ?? 0)
        }
        return memory + queued
    }

    @discardableResult
    public func beginLaunch(at date: Date, context: AnalyticsContext? = nil) -> LaunchClassification {
        lock.lock()
        defer { lock.unlock() }
        if launched {
            return .clean
        }
        launched = true
        if let context {
            self.context = context
        }
        var classification = LaunchClassification.clean
        if CrashExit.countsAsCrash(state.exit?.state), let exit = state.exit {
            let event = QueuedEvent(
                id: makeID(),
                kind: .crash,
                occurredAt: date,
                sessionID: exit.sessionID,
                context: exit.context,
                crashKind: "unclean_exit",
                crashSummary: "unclean exit",
                crashDetails: nil
            )
            state.pending.append(event)
            state.pendingUnclean = PendingUnclean(sessionID: exit.sessionID, startedAt: exit.startedAt)
            classification = .unclean(sessionID: exit.sessionID)
        } else if let pending = state.pendingUnclean, date.timeIntervalSince(pending.startedAt) > Self.uncleanAttachWindow {
            state.pendingUnclean = nil
        }
        let sessionID = makeID()
        let active = ExitRecord(sessionID: sessionID, state: .active, startedAt: date, backgroundedAt: nil, context: self.context)
        state.sessionID = sessionID
        state.exit = active
        state.pending.append(QueuedEvent(
            id: makeID(),
            kind: .sessionStart,
            occurredAt: date,
            sessionID: sessionID,
            context: self.context
        ))
        if state.lastTimerAt == nil {
            state.lastTimerAt = date
        }
        persistLocked()
        return classification
    }

    /// MetricKit details attach to an unclean session. A clean background or terminate drops them.
    @discardableResult
    public func noteMetricKit(diagnosticID: String, summary: String, details: String, at date: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !diagnosticID.isEmpty else { return false }
        if state.deliveredCrashIDs.contains(diagnosticID) { return false }
        guard let pending = state.pendingUnclean else { return false }
        guard date.timeIntervalSince(pending.startedAt) <= Self.uncleanAttachWindow else {
            state.pendingUnclean = nil
            persistLocked()
            return false
        }
        state.deliveredCrashIDs.append(diagnosticID)
        if state.deliveredCrashIDs.count > 40 {
            state.deliveredCrashIDs.removeFirst(state.deliveredCrashIDs.count - 40)
        }
        state.pending.append(QueuedEvent(
            id: makeID(),
            kind: .crash,
            occurredAt: date,
            sessionID: pending.sessionID,
            context: state.exit?.context ?? context,
            crashKind: "metrickit",
            crashSummary: String(summary.prefix(300)),
            crashDetails: String(details.prefix(4000))
        ))
        persistLocked()
        return true
    }

    public func enteredForeground(at date: Date) {
        lock.lock()
        defer { lock.unlock() }
        guard var exit = state.exit else { return }
        let leftAt = exit.backgroundedAt
        let wasAway = exit.state == .inactive || exit.state == .background
        if wasAway, let leftAt, date.timeIntervalSince(leftAt) >= Self.newSessionAfterBackground {
            let sessionID = makeID()
            state.sessionID = sessionID
            state.exit = ExitRecord(
                sessionID: sessionID,
                state: .active,
                startedAt: date,
                backgroundedAt: nil,
                context: context
            )
            state.pending.append(QueuedEvent(
                id: makeID(),
                kind: .sessionStart,
                occurredAt: date,
                sessionID: sessionID,
                context: context
            ))
            persistLocked()
            return
        }
        exit.state = .active
        exit.backgroundedAt = nil
        state.exit = exit
        persistLocked()
    }

    /// Synchronous. App switcher and an inactive scene are not crashes, and clicks are already on disk.
    public func markInactive(at date: Date) {
        lock.lock()
        defer { lock.unlock() }
        drainClicksLocked()
        guard var exit = state.exit, exit.state == .active else {
            persistLocked()
            return
        }
        exit.state = .inactive
        exit.backgroundedAt = date
        state.exit = exit
        persistLocked()
    }

    /// Synchronous. Call this before any background flush so a force-quit cannot drop the clicks.
    public func markBackground(at date: Date) {
        lock.lock()
        defer { lock.unlock() }
        drainClicksLocked()
        guard var exit = state.exit else {
            persistLocked()
            return
        }
        exit.state = .background
        if exit.backgroundedAt == nil {
            exit.backgroundedAt = date
        }
        state.exit = exit
        persistLocked()
    }

    public func markTerminated() {
        lock.lock()
        defer { lock.unlock() }
        drainClicksLocked()
        guard var exit = state.exit else {
            persistLocked()
            return
        }
        exit.state = .terminated
        if exit.backgroundedAt == nil {
            exit.backgroundedAt = Date()
        }
        state.exit = exit
        persistLocked()
    }

    public func enteredBackground(at date: Date) async {
        markBackground(at: date)
        await flush(reason: .background)
    }

    public func willTerminate() async {
        markTerminated()
        await flush(reason: .background)
    }

    public func flushIfDue(at date: Date) async {
        let due: Bool = withLock {
            let start = state.lastTimerAt ?? date
            return date.timeIntervalSince(start) >= Self.flushInterval
        }
        guard due else { return }
        await flush(reason: .timer)
        withLock {
            state.lastTimerAt = date
            persistLocked()
        }
    }

    public func flushNow() async {
        await flush(reason: .manual)
    }

    /// Persists the report before any network call. A timeout or failure leaves it queued once.
    public func sendReport(category: String, text: String, at date: Date = Date(), timeout: TimeInterval = ReportDraftRules.sendTimeout) async -> ReportSendResult {
        let reportID = makeID()
        let sessionID = withLock { state.sessionID }
        let event = QueuedEvent(
            id: reportID,
            kind: .report,
            occurredAt: date,
            sessionID: sessionID,
            category: category,
            text: ReportDraftRules.clamped(text),
            context: context
        )
        withLock {
            state.pending.append(event)
            persistLocked()
        }
        let send = Task { await self.flush(reason: .manual) }
        let timedOut = await Self.waitFor(send, timeout: timeout)
        if timedOut {
            return .savedOffline
        }
        let stillQueued = withLock {
            state.pending.contains { $0.id == reportID } || (state.inflight?.events.contains { $0.id == reportID } ?? false)
        }
        return stillQueued ? .savedOffline : .sent
    }

    public func absorb(_ event: QueuedEvent) async {
        withLock {
            state.pending.append(event)
            persistLocked()
        }
        let count = withLock { state.pending.count + (state.inflight == nil ? 0 : Self.batchSize) }
        if count >= Self.batchSize {
            await flush(reason: .threshold)
        }
    }

    private func flush(reason: AnalyticsFlushReason) async {
        while true {
            let started: Bool = withLock {
                if flushing { return false }
                flushing = true
                return true
            }
            if started { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        defer { withLock { flushing = false } }

        while true {
            let batch = nextBatch(reason: reason)
            guard let batch else { return }
            let access = await token()
            guard let access, !access.isEmpty else { return }
            do {
                let ack = try await transport.submitBatch(id: batch.id, events: batch.events, accessToken: access)
                switch ack {
                case .stored, .duplicate:
                    withLock {
                        if state.inflight?.id == batch.id {
                            state.inflight = nil
                            persistLocked()
                        }
                    }
                }
            } catch {
                return
            }
            if reason == .threshold {
                let more = withLock { state.pending.count >= Self.batchSize }
                if !more { return }
            }
        }
    }

    private func nextBatch(reason: AnalyticsFlushReason) -> InflightBatch? {
        lock.lock()
        defer { lock.unlock() }
        if state.inflight == nil {
            drainClicksLocked()
            guard !state.pending.isEmpty else {
                persistLocked()
                return nil
            }
            if reason == .threshold && state.pending.count < Self.batchSize {
                return nil
            }
            let take = Array(state.pending.prefix(Self.batchSize))
            state.pending.removeFirst(take.count)
            state.inflight = InflightBatch(id: makeID(), events: take)
            persistLocked()
        }
        return state.inflight
    }

    private func drainClicksLocked() {
        for item in counters.drain() where item.count > 0 {
            guard ClickMap.pages.contains(item.page) else { continue }
            let allowed: [String]
            switch item.page {
            case "start": allowed = ClickMap.start
            case "playing": allowed = ClickMap.playing
            case "leaderboard": allowed = ClickMap.leaderboard
            default: allowed = []
            }
            guard allowed.contains(item.control) else { continue }
            state.pending.append(QueuedEvent(
                id: makeID(),
                kind: .click,
                occurredAt: Date(),
                sessionID: state.sessionID,
                page: item.page,
                control: item.control,
                count: item.count,
                context: context
            ))
        }
    }

    private func persistLocked() {
        store.save(state)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func waitFor(_ task: Task<Void, Never>, timeout: TimeInterval) async -> Bool {
        let nanos = UInt64((max(0, timeout) * 1_000_000_000).rounded())
        let gate = ResumeOnce()
        return await withCheckedContinuation { continuation in
            Task {
                await task.value
                gate.resume(continuation, returning: false)
            }
            Task {
                try? await Task.sleep(nanoseconds: nanos)
                gate.resume(continuation, returning: true)
            }
        }
    }
}

/// Resumes a continuation on the first call. The slower path becomes a no-op.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<Bool, Never>, returning value: Bool) {
        lock.lock()
        let first = !resumed
        resumed = true
        lock.unlock()
        if first {
            continuation.resume(returning: value)
        }
    }
}
