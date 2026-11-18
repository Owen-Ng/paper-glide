import PaperGlideCore
import SwiftUI

struct StartView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var cloud: CloudModel
    @State private var draft = ""
    @State private var showReport = false
    @State private var toast: String?
    @State private var ownedFrames: [String: CGRect] = [:]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                MorningStill()
                ScrollView {
                    VStack(spacing: 22) {
                        Spacer(minLength: 12)
                        mark
                        Text("Paper Glide")
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("Glide a paper plane through open windows.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(AppTheme.ink.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Text("Best score \(model.bestScore)")
                            .font(.system(.title3, design: .rounded).weight(.medium))
                            .foregroundStyle(AppTheme.ink)
                            .accessibilityIdentifier("startBestScore")
                            .accessibilityLabel("Best score \(model.bestScore)")
                        if let chip = cloud.chipText {
                            Button(chip) {
                                cloud.analytics.record(page: "start", control: "other")
                                Task { await cloud.retry() }
                            }
                            .buttonStyle(.bordered)
                            .font(.system(.footnote, design: .rounded))
                            .disabled(cloud.busy)
                            .accessibilityIdentifier("syncChip")
                            .controlFrame("chip")
                        }
                        Button(action: {
                            cloud.analytics.record(page: "start", control: "play")
                            model.startRun()
                        }) {
                            Text("Play")
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("playButton")
                        .controlFrame("play")
                        .padding(.horizontal, 48)
                        .padding(.top, 8)
                        VStack(spacing: 10) {
                            Button("Leaderboard") {
                                cloud.analytics.record(page: "start", control: "leaderboard")
                                model.showLeaderboard()
                            }
                            .accessibilityIdentifier("leaderboardButton")
                            .controlFrame("leaderboard")
                            Button("Report a problem") {
                                cloud.analytics.record(page: "start", control: "report")
                                showReport = true
                            }
                            .accessibilityIdentifier("reportButton")
                            .controlFrame("report")
                        }
                        .buttonStyle(.bordered)
                        .font(.system(.body, design: .rounded))
                        .padding(.horizontal, 48)
                        if cloud.snapshot.showsLaunchPrompt {
                            NamePromptCard(
                                draft: $draft,
                                error: cloud.snapshot.nameError,
                                showsLater: true,
                                onSave: { Task { await cloud.claim(draft) } },
                                onLater: cloud.dismissLaunch
                            )
                            .padding(.horizontal, 32)
                            .simultaneousGesture(TapGesture().onEnded {
                                cloud.analytics.record(page: "start", control: "other")
                            })
                            .controlFrame("name")
                        }
                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .coordinateSpace(name: "start-clicks")
                .onPreferenceChange(ControlFrameKey.self) { ownedFrames = $0 }
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    let point = TapPoint(x: value.location.x, y: value.location.y)
                    let owned = ownedFrames.values.map { TapRect($0) }
                    if ClickHit.backgroundControl(at: point, owned: owned) == "other" {
                        cloud.analytics.record(page: "start", control: "other")
                    }
                })
                if showReport {
                    ReportSheet(
                        onClose: { showReport = false },
                        onSend: { category, text in
                            await cloud.analytics.sendReport(category: category, text: text)
                        },
                        onFinished: { result in
                            showReport = false
                            toast = result == .sent ? ReportCopy.thanks : ReportCopy.saved
                        }
                    )
                }
                if let toast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.paper, in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                            .padding(.bottom, 28)
                            .accessibilityIdentifier("reportToast")
                    }
                    .allowsHitTesting(false)
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        self.toast = nil
                    }
                }
            }
        }
    }

    private var mark: some View {
        HStack(spacing: 18) {
            WindowGlyph()
                .fill(AppTheme.coral.opacity(0.9), style: FillStyle(eoFill: true))
                .frame(width: 54, height: 78)
            PaperPlaneGlyph()
                .fill(AppTheme.paper)
                .overlay(PaperPlaneGlyph().stroke(AppTheme.ink.opacity(0.45), lineWidth: 1.5))
                .frame(width: 86, height: 36)
        }
        .accessibilityHidden(true)
    }
}

/// Static paper morning. The cycle runs only while a run is playing.
private struct MorningStill: View {
    private let sky = SkyCycle.sample(at: 0)

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack {
                LinearGradient(colors: [sky.top.color, sky.bottom.color], startPoint: .top, endPoint: .bottom)
                Ellipse()
                    .fill(SkyCycle.cloudTint(sky).color.opacity(0.72))
                    .frame(width: width * 0.42, height: 34)
                    .position(x: width * 0.22, y: height * 0.16)
                Ellipse()
                    .fill(SkyCycle.cloudTint(sky).color.opacity(0.55))
                    .frame(width: width * 0.28, height: 24)
                    .position(x: width * 0.48, y: height * 0.10)
                Ellipse()
                    .fill(SkyCycle.cloudTint(sky).color.opacity(0.62))
                    .frame(width: width * 0.36, height: 30)
                    .position(x: width * 0.78, y: height * 0.20)
                Circle()
                    .fill(sky.sun.color)
                    .overlay(Circle().stroke(Color(red: 0.62, green: 0.46, blue: 0.30).opacity(0.85), lineWidth: 1.5))
                    .frame(width: 54, height: 54)
                    .position(
                        x: width * sky.sunX,
                        y: height * (1 - SkyCycle.sunHeightFraction(sky))
                    )
                MorningRoofline(width: width, height: height, sky: sky)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MorningRoofline: View {
    var width: CGFloat
    var height: CGFloat
    var sky: SkyCycle.Sample

    var body: some View {
        Canvas { context, _ in
            let specs: [(CGFloat, CGFloat, CGFloat, CGFloat, Int)] = [
                (0.02, 0.16, 0.13, 0.045, 0),
                (0.20, 0.11, 0.09, 0.040, 1),
                (0.34, 0.18, 0.16, 0.050, 2),
                (0.55, 0.08, 0.11, 0.060, 3),
                (0.66, 0.14, 0.12, 0.035, 4),
                (0.82, 0.16, 0.15, 0.040, 5)
            ]
            for spec in specs {
                let x = width * spec.0
                let w = width * spec.1
                let body = height * spec.2
                let rise = height * spec.3
                let tint = SkyCycle.buildingTint(
                    SkyCycle.collagePapers[spec.4 % SkyCycle.collagePapers.count],
                    sky
                )
                var path = Path()
                path.move(to: CGPoint(x: x, y: height))
                path.addLine(to: CGPoint(x: x, y: height - body))
                path.addLine(to: CGPoint(x: x + w * 0.5, y: height - body - rise))
                path.addLine(to: CGPoint(x: x + w, y: height - body))
                path.addLine(to: CGPoint(x: x + w, y: height))
                path.closeSubpath()
                context.fill(path, with: .color(tint.color))
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

struct PaperPlaneGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.94, y: rect.height * 0.50))
        path.addLine(to: CGPoint(x: rect.width * 0.06, y: rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.width * 0.30, y: rect.height * 0.50))
        path.addLine(to: CGPoint(x: rect.width * 0.06, y: rect.height * 0.84))
        path.closeSubpath()
        return path
    }
}

struct ControlFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func controlFrame(_ name: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ControlFrameKey.self,
                    value: [name: geo.frame(in: .named("start-clicks"))]
                )
            }
        )
    }
}

extension TapRect {
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}

struct WindowGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: 8, height: 8))
        let opening = rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.30)
        path.addRoundedRect(in: opening, cornerSize: CGSize(width: 4, height: 4))
        return path
    }
}
