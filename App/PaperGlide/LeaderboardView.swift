import PaperGlideCore
import SwiftUI

struct LeaderboardView: View {
    @ObservedObject var cloud: CloudModel
    var localBest: Int
    var onBack: () -> Void
    @State private var draft = ""
    @State private var pickerWidth: CGFloat = 1
    @State private var scrollClicks = 0

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

            Picker("Board", selection: $cloud.period) {
                Text("Today").tag(BoardPeriod.daily)
                Text("This week").tag(BoardPeriod.weekly)
                Text("All time").tag(BoardPeriod.allTime)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("boardPicker")
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ControlFrameKey.self,
                        value: ["picker": geo.frame(in: .named("board-clicks"))]
                    )
                }
            )
            .onPreferenceChange(ControlFrameKey.self) { frames in
                pickerWidth = frames["picker"]?.width ?? pickerWidth
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                let width = pickerWidth
                guard width > 0 else { return }
                let index = min(2, max(0, Int(value.location.x / (width / 3))))
                cloud.analytics.record(page: "leaderboard", control: ClickMap.leaderboard[index])
            })
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
        .coordinateSpace(name: "board-clicks")
        .onChange(of: cloud.period) { _ in
            Task { await cloud.refreshSelected() }
        }
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
                        .accessibilityIdentifier(entry.isYou ? "boardYouRow" : "boardRow")
                        .simultaneousGesture(TapGesture().onEnded {
                            cloud.analytics.record(page: "leaderboard", control: "other")
                        })
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
                        onSave: { Task { await cloud.claim(draft) } },
                        onLater: {}
                    )
                    .simultaneousGesture(TapGesture().onEnded {
                        cloud.analytics.record(page: "leaderboard", control: "other")
                    })
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { _ in
                scrollClicks += 1
                cloud.analytics.record(page: "leaderboard", control: "scroll")
            }
        )
        .overlay(alignment: .bottomLeading) {
            Text("scroll=\(scrollClicks)")
                .font(.system(size: 1))
                .opacity(0.01)
                .frame(width: 4, height: 4)
                .accessibilityIdentifier("leaderboardScrollCount")
                .accessibilityLabel("scroll=\(scrollClicks)")
        }

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
