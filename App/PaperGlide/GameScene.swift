import PaperGlideCore
import SpriteKit
import UIKit

final class PaperGlideScene: SKScene {
    var onSnapshot: ((GameSnapshot) -> Void)?

    private let session: GameSession
    private let tones = TonePlayer()
    private let sceneryNode = SKNode()
    private let obstacleNode = SKNode()
    private let planeNode = SKShapeNode()
    private let creaseNode = SKShapeNode()
    private var clouds: [Cloud] = []
    private var decorTime: CGFloat = 0
    private var lastUpdateTime: TimeInterval = 0
    private var didBuildScenery = false
    private var renderedScore = 0
    private var renderedPhase: RunPhase = .playing

    init(session: GameSession) {
        self.session = session
        let size = CGSize(width: session.config.worldWidth, height: session.config.worldHeight)
        super.init(size: size)
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = AppTheme.skyBackground
        physicsWorld.gravity = .zero
    }

    required init?(coder: NSCoder) {
        fatalError("PaperGlideScene is created in code")
    }

    override func didMove(to view: SKView) {
        scaleMode = .aspectFit
        size = CGSize(width: session.config.worldWidth, height: session.config.worldHeight)
        lastUpdateTime = 0
        buildSceneryIfNeeded()
        let snapshot = session.snapshot
        renderedScore = snapshot.score
        renderedPhase = snapshot.phase
        render(snapshot)
    }

    override func update(_ currentTime: TimeInterval) {
        let dt: Double
        if lastUpdateTime == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = currentTime - lastUpdateTime
        }
        lastUpdateTime = currentTime
        guard dt > 0 else { return }

        session.step(dt: dt)
        let snapshot = session.snapshot
        if snapshot.score > renderedScore {
            tones.playScore()
        }
        if renderedPhase == .playing, snapshot.phase == .dead {
            tones.playFold()
        }
        renderedScore = snapshot.score
        renderedPhase = snapshot.phase
        onSnapshot?(snapshot)
        scrollClouds(dt: dt)
        render(snapshot)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.snapshot.phase == .playing else { return }
        session.tap()
        tones.playTap()
        onSnapshot?(session.snapshot)
    }

    private func buildSceneryIfNeeded() {
        guard !didBuildScenery else { return }
        didBuildScenery = true

        let band = SKSpriteNode(color: AppTheme.paperBand, size: CGSize(width: size.width, height: size.height * 0.42))
        band.anchorPoint = .zero
        band.position = .zero
        band.zPosition = 0
        sceneryNode.addChild(band)

        let specs: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (70, 520, 150, 54, 18),
            (210, 600, 190, 42, 26),
            (20, 440, 120, 36, 14)
        ]
        for spec in specs {
            let node = SKShapeNode(ellipseOf: CGSize(width: spec.2, height: spec.3))
            node.fillColor = UIColor(white: 1, alpha: 0.72)
            node.strokeColor = .clear
            node.position = CGPoint(x: spec.0, y: spec.1)
            node.zPosition = 1
            sceneryNode.addChild(node)
            clouds.append(Cloud(node: node, speed: spec.4, width: spec.2, baseX: spec.0))
        }

        sceneryNode.zPosition = 0
        obstacleNode.zPosition = 5
        addChild(sceneryNode)
        addChild(obstacleNode)
        configurePlane()
    }

    private func configurePlane() {
        let width = CGFloat(session.config.planeWidth)
        let height = CGFloat(session.config.planeHeight)
        let halfW = width / 2
        let halfH = height / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: halfW, y: 0))
        path.addLine(to: CGPoint(x: -halfW, y: halfH))
        path.addLine(to: CGPoint(x: -halfW * 0.32, y: 0))
        path.addLine(to: CGPoint(x: -halfW, y: -halfH))
        path.closeSubpath()
        planeNode.path = path
        planeNode.fillColor = AppTheme.planeFill
        planeNode.strokeColor = AppTheme.planeStroke
        planeNode.lineWidth = 1.5
        planeNode.zPosition = 10

        let crease = CGMutablePath()
        crease.move(to: CGPoint(x: -halfW * 0.32, y: 0))
        crease.addLine(to: CGPoint(x: halfW * 0.2, y: halfH * 0.18))
        creaseNode.path = crease
        creaseNode.strokeColor = AppTheme.planeStroke.withAlphaComponent(0.7)
        creaseNode.lineWidth = 1
        creaseNode.zPosition = 11
        planeNode.addChild(creaseNode)
        addChild(planeNode)
    }

    private func scrollClouds(dt: Double) {
        decorTime += CGFloat(dt)
        let span = size.width + 200
        guard span > 0 else { return }
        for cloud in clouds {
            let travel = decorTime * cloud.speed
            let wrapped = travel.truncatingRemainder(dividingBy: span)
            var x = cloud.baseX - wrapped
            if x < -cloud.width {
                x += span
            }
            cloud.node.position.x = x
        }
    }

    private func render(_ snapshot: GameSnapshot) {
        obstacleNode.removeAllChildren()
        for window in snapshot.obstacles {
            draw(window)
        }
        let plane = snapshot.plane
        planeNode.position = CGPoint(x: plane.x, y: plane.y)
        let limit = max(session.config.maxUpwardSpeed, session.config.maxDownwardSpeed)
        let tilt = max(-1.0, min(1.0, plane.velocityY / limit))
        planeNode.zRotation = CGFloat(tilt) * 0.45
    }

    private func draw(_ window: Obstacle) {
        let palette = AppTheme.facades[abs(window.id) % AppTheme.facades.count]
        let frame = darkened(palette)
        let left = CGFloat(window.left)
        let width = CGFloat(window.width)
        let gapBottom = CGFloat(window.gapBottom)
        let gapTop = CGFloat(window.gapTop)
        let worldHeight = CGFloat(session.config.worldHeight)

        addBlock(
            rect: CGRect(x: left, y: 0, width: width, height: max(0, gapBottom)),
            fill: palette,
            parent: obstacleNode
        )
        addBlock(
            rect: CGRect(x: left, y: gapTop, width: width, height: max(0, worldHeight - gapTop)),
            fill: palette,
            parent: obstacleNode
        )

        let sill: CGFloat = 7
        addBlock(
            rect: CGRect(x: left, y: gapBottom - sill, width: width, height: sill),
            fill: frame,
            parent: obstacleNode
        )
        addBlock(
            rect: CGRect(x: left, y: gapTop, width: width, height: sill),
            fill: frame,
            parent: obstacleNode
        )

        let opening = CGRect(x: left, y: gapBottom, width: width, height: max(0, gapTop - gapBottom))
        let outline = SKShapeNode(path: CGPath(rect: opening, transform: nil))
        outline.strokeColor = frame
        outline.lineWidth = 3
        outline.fillColor = .clear
        outline.zPosition = 1
        obstacleNode.addChild(outline)
    }

    private func addBlock(rect: CGRect, fill: UIColor, parent: SKNode) {
        guard rect.width > 1, rect.height > 1 else { return }
        let corner = min(8, min(rect.width / 2, rect.height / 2))
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        let node = SKShapeNode(path: path)
        node.fillColor = fill
        node.strokeColor = UIColor(white: 1, alpha: 0.35)
        node.lineWidth = 1
        parent.addChild(node)
    }

    private func darkened(_ color: UIColor) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(red: red * 0.78, green: green * 0.78, blue: blue * 0.78, alpha: 1)
    }
}

private struct Cloud {
    let node: SKShapeNode
    let speed: CGFloat
    let width: CGFloat
    let baseX: CGFloat
}
