import SpriteKit
import SwiftUI

struct PlayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            GameCanvas(scene: model.scene)
                .ignoresSafeArea()
            if LaunchOptions.scriptedEndScore != nil || LaunchOptions.guidedStride != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("glideTapArea")
                    .accessibilityLabel("Glide")
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture {
                        if LaunchOptions.scriptedEndScore != nil {
                            model.recordScriptedGlideTap()
                        } else {
                            model.guidedTap()
                        }
                    }
            }
            VStack {
                Text("\(model.score)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.72), in: Capsule())
                    .padding(.top, 12)
                    .accessibilityIdentifier("scoreLabel")
                    .accessibilityLabel("Score \(model.score)")
                Spacer()
                if model.showCoach {
                    Text("tap to glide")
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.88))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.82), in: Capsule())
                        .padding(.bottom, 36)
                        .accessibilityIdentifier("coachLabel")
                        .accessibilityLabel("tap to glide")
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            Text(model.flightAdvice)
                .font(.system(size: 1))
                .opacity(0.01)
                .frame(width: 4, height: 4)
                .accessibilityIdentifier("flightState")
                .accessibilityLabel(
                    String(
                        format: "advice=%@;y=%.4f;target=%.4f;score=%d",
                        model.flightAdvice,
                        model.planeY,
                        model.guidedTargetY,
                        model.score
                    )
                )
        }
        .overlay(alignment: .bottomTrailing) {
            if LaunchOptions.guidedStride != nil {
                Button(action: model.guidedCoast) {
                    Color.clear.frame(width: 44, height: 44)
                }
                .accessibilityLabel("Coast")
                .accessibilityIdentifier("coastButton")
                .padding(8)
            }
        }
        .background(Color(uiColor: AppTheme.skyBackground))
    }
}

struct GameCanvas: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = false
        view.backgroundColor = AppTheme.skyBackground
        scene.scaleMode = .aspectFit
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene {
            view.presentScene(scene)
        }
    }
}
