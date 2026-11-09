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
                Button("Back", action: onBack)
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
                Text("Daily").tag(BoardPeriod.daily)
                Text("Weekly").tag(BoardPeriod.weekly)
                Text("All-time").tag(BoardPeriod.allTime)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("boardPicker")

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
    }

    @ViewBuilder
    private func board(_ presentation: BoardPresentation) -> some View {
        let list = List {
            if !presentation.banners.isEmpty {
                Section {
                    ForEach(presentation.banners, id: \.self) { banner in
                        Button(banner) {
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
                    }
                    if let outside = presentation.outsideLine {
                        HStack {
                            Text(outside)
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            if let score = presentation.outsideScore {
                                Text("\(score)")
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .accessibilityIdentifier("boardOutsideYou")
                        .accessibilityLabel(outside)
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
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)

        if presentation.canPullToRefresh {
            list.refreshable { await cloud.refreshSelected() }
        } else {
            list
        }
    }

    private func bannerIdentifier(_ banner: String) -> String {
        if banner == BoardCopy.syncRetry { return "boardSyncRetry" }
        if banner == BoardCopy.loadFailed { return "boardRetryButton" }
        return "boardBanner"
    }
}
