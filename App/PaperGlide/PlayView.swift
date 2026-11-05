import SpriteKit
import SwiftUI

struct PlayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            GameCanvas(scene: model.scene)
                .ignoresSafeArea()
            if LaunchOptions.scriptedEndScore != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("glideTapArea")
                    .accessibilityLabel("Glide")
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture {
                        model.recordScriptedGlideTap()
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
