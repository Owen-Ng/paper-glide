import PaperGlideCore
import SwiftUI

struct LeaderboardView: View {
    @ObservedObject var cloud: CloudModel
    var localBest: Int
    var onBack: () -> Void
    @State private var draft = ""

    var body: some View {
        let presentation = cloud.presentation(localBest: localBest)
        VStack(spacing: 12) {
            HStack {
                Button("Back") {
                    cloud.analytics.record(page: "leaderboard", control: "back")
                    onBack()
                }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("leaderboardBackButton")
                Spacer()
                Text("Leaderboard")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Color.clear.frame(width: 64, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Picker("Board", selection: periodSelection) {
                Text("Today").tag(BoardPeriod.daily)
                Text("This week").tag(BoardPeriod.weekly)
                Text("All time").tag(BoardPeriod.allTime)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("boardPicker")
            .padding(.horizontal, 16)

            if let caption = presentation.caption {
                Text(caption)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("boardCaption")
            }

            board(presentation)
        }
        .background(AppTheme.paper.ignoresSafeArea())
        .onChange(of: cloud.period) { _ in
            Task { await cloud.refreshSelected() }
        }
        .onDisappear {
            cloud.analytics.flushSoon()
        }
    }

    /// The segmented control writes here only when the player picks a different board.
    private var periodSelection: Binding<BoardPeriod> {
        Binding(
            get: { cloud.period },
            set: { newValue in
                guard newValue != cloud.period else { return }
                cloud.analytics.record(page: "leaderboard", control: ClickMap.leaderboardPeriod(newValue))
                cloud.period = newValue
            }
        )
    }

    @ViewBuilder
    private func board(_ presentation: BoardPresentation) -> some View {
        let list = List {
            if !presentation.banners.isEmpty {
                Section {
                    ForEach(presentation.banners, id: \.self) { banner in
                        Button(banner) {
                            cloud.analytics.record(page: "leaderboard", control: "other")
                            Task { await cloud.retry() }
                        }
                        .font(.system(.footnote, design: .rounded))
                        .accessibilityIdentifier(bannerIdentifier(banner))
                    }
                }
            }
            if presentation.showSkeleton {
                Section {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.ink.opacity(0.08))
                            .frame(height: 18)
                    }
                }
                .accessibilityIdentifier("leaderboardSkeleton")
            } else if presentation.showOfflineEmpty {
                Section {
                    Text(BoardCopy.offlineEmpty)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("boardOffline")
                    if let localBestLine = presentation.localBestLine {
                        Text(localBestLine)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(AppTheme.ink.opacity(0.8))
                            .accessibilityIdentifier("boardLocalBest")
                    }
                }
            } else {
                Section {
                    ForEach(presentation.entries) { entry in
                        Button {
                            cloud.analytics.record(page: "leaderboard", control: "other")
                        } label: {
                            HStack {
                                Text("#\(entry.rank)")
                                    .foregroundStyle(AppTheme.ink.opacity(0.65))
                                Text(entry.username)
                                    .foregroundStyle(AppTheme.ink)
                                if entry.isYou {
                                    Text("you")
                                        .font(.system(.caption, design: .rounded).weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.coral.opacity(0.18), in: Capsule())
                                }
                                Spacer()
                                Text("\(entry.score)")
                                    .foregroundStyle(AppTheme.ink)
                            }
                            .font(.system(.body, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(entry.isYou ? "boardYouRow" : "boardRow")
                    }
                    if let title = presentation.emptyTitle {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .accessibilityIdentifier("boardEmpty")
                            if let detail = presentation.emptyDetail {
                                Text(detail)
                                    .foregroundStyle(AppTheme.ink.opacity(0.7))
                            }
                        }
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    }
                }
            }
            if cloud.snapshot.username == nil {
                Section {
                    NamePromptCard(
                        draft: $draft,
                        error: cloud.snapshot.nameError,
                        showsLater: false,
                        onSave: {
                            cloud.analytics.record(page: "leaderboard", control: "other")
                            Task { await cloud.claim(draft) }
                        },
                        onLater: {}
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .modifier(LeaderboardScrollCounter {
            cloud.analytics.record(page: "leaderboard", control: "scroll")
        })

        VStack(spacing: 0) {
            if presentation.canPullToRefresh {
                list.refreshable { await cloud.refreshSelected() }
            } else {
                list
            }
            if let pinned = pinnedYou(presentation) {
                Divider()
                HStack {
                    Text(pinned.line)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text("\(pinned.score)")
                        .foregroundStyle(AppTheme.ink)
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(AppTheme.paper)
                .accessibilityIdentifier(presentation.outsideLine == nil ? "boardYouFooter" : "boardOutsideYou")
                .accessibilityLabel(pinned.line)
            }
        }
    }

    /// The player's rank stays on screen. Outside the top 50 this is "#128 — you".
    private func pinnedYou(_ presentation: BoardPresentation) -> (line: String, score: Int)? {
        if let line = presentation.outsideLine, let score = presentation.outsideScore {
            return (line, score)
        }
        if let you = presentation.entries.first(where: \.isYou) {
            return (BoardCopy.outside(rank: you.rank), you.score)
        }
        return nil
    }

    private func bannerIdentifier(_ banner: String) -> String {
        if banner == BoardCopy.syncRetry { return "boardSyncRetry" }
        if banner == BoardCopy.loadFailed { return "boardRetryButton" }
        return "boardBanner"
    }
}

/// One user drag is one scroll. Deceleration is a later phase of the same gesture, so it is not counted again.
private struct LeaderboardScrollCounter: ViewModifier {
    var onScroll: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { oldPhase, newPhase in
                if newPhase == .interacting, oldPhase != .interacting {
                    onScroll()
                }
            }
        } else {
            content.background(ScrollDragStart(onBegan: onScroll))
        }
    }
}

/// iOS 16 and 17 have no scroll-phase callback. The list's pan recognizer enters `.began`
/// once when the finger starts a drag, and deceleration after the finger lifts does not start it again.
private struct ScrollDragStart: UIViewRepresentable {
    var onBegan: () -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.onBegan = onBegan
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.onBegan = onBegan
    }

    final class Probe: UIView {
        var onBegan: () -> Void = {}
        private weak var scrollView: UIScrollView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
        }

        private func attachIfNeeded() {
            guard scrollView == nil, let found = enclosingScrollView() else { return }
            scrollView = found
            found.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
        }

        @objc private func pan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                onBegan()
            }
        }

        private func enclosingScrollView() -> UIScrollView? {
            var node: UIView? = superview
            var steps = 0
            while let current = node, steps < 10 {
                if let match = largestScrollView(in: current), match.bounds.height > 120 {
                    return match
                }
                node = current.superview
                steps += 1
            }
            return nil
        }

        private func largestScrollView(in root: UIView) -> UIScrollView? {
            var best: UIScrollView?
            var stack = [root]
            var seen = 0
            while let view = stack.popLast(), seen < 80 {
                seen += 1
                if let scroll = view as? UIScrollView {
                    if (best?.bounds.height ?? 0) < scroll.bounds.height {
                        best = scroll
                    }
                }
                stack.append(contentsOf: view.subviews)
            }
            return best
        }

        deinit {
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(pan(_:)))
        }
    }
}
