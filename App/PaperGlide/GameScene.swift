import Foundation
import PaperGlideCore
import SpriteKit
import UIKit

final class PaperGlideScene: SKScene {
    var onSnapshot: ((GameSnapshot) -> Void)?

    private let session: GameSession
    private let tones = TonePlayer()
    private let farCloudNode = SKNode()
    private let nearCloudNode = SKNode()
    private let skylineNode = SKNode()
    private let obstacleNode = SKNode()
    private let sunNode = SKNode()
    private let moonNode = SKNode()
    private let sunDisc = SKShapeNode(circleOfRadius: 26)
    private let moonGlow = SKShapeNode(circleOfRadius: 24)
    private let moonBody = SKShapeNode(circleOfRadius: 15)
    private let moonBite = SKShapeNode(circleOfRadius: 13)
    private let planeNode = SKShapeNode()
    private let creaseNode = SKShapeNode()
    private var skyBands: [SKSpriteNode] = []
    private var starNodes: [SKShapeNode] = []
    private var clouds: [Cloud] = []
    private var skyline: [SkylinePiece] = []
    private var decoratedRunID = -1
    private var cloudFlightTime = 0.0
    private var didBuildScenery = false
    private var lastUpdateTime: TimeInterval = 0
    private var renderedScore = 0
    private var renderedPhase: RunPhase = .playing

    init(session: GameSession) {
        self.session = session
        let size = CGSize(width: session.config.worldWidth, height: session.config.worldHeight)
        super.init(size: size)
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = SkyCycle.sample(at: 0).top.uiColor
        physicsWorld.gravity = .zero
    }

    required init?(coder: NSCoder) {
        fatalError("PaperGlideScene is created in code")
    }

    override func didMove(to view: SKView) {
        scaleMode = .aspectFit
        size = CGSize(width: session.config.worldWidth, height: session.config.worldHeight)
        lastUpdateTime = 0
        render(session.snapshot)
    }

    /// Draws the session as it is now. A new run calls this so the page does not
    /// linger on the previous crash for a frame.
    func presentCurrentSnapshot() {
        render(session.snapshot)
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

        if LaunchOptions.scriptedEndScore != nil || LaunchOptions.guidedStride != nil {
            let snapshot = session.snapshot
            onSnapshot?(snapshot)
            render(snapshot)
            return
        }

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
        render(snapshot)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.snapshot.phase == .playing else { return }
        if LaunchOptions.guidedStride != nil || LaunchOptions.scriptedEndScore != nil {
            return
        }
        let coachWasShowing = session.snapshot.showCoach
        PlayClicks.recordFlap()
        session.tap()
        if coachWasShowing, let score = LaunchOptions.scriptedEndScore {
            session.endRun(withScore: score)
        }
        tones.playTap()
        onSnapshot?(session.snapshot)
    }

    private func render(_ snapshot: GameSnapshot) {
        buildSceneryIfNeeded()
        syncDecor(to: snapshot)
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

    private func buildSceneryIfNeeded() {
        guard !didBuildScenery else { return }
        didBuildScenery = true

        let bandCount = 48
        let bandHeight = size.height / CGFloat(bandCount)
        for index in 0..<bandCount {
            let band = SKSpriteNode(color: .white, size: CGSize(width: size.width + 2, height: bandHeight + 1))
            band.anchorPoint = .zero
            band.position = CGPoint(x: -1, y: CGFloat(index) * bandHeight)
            band.zPosition = CGFloat(index) * 0.001
            addChild(band)
            skyBands.append(band)
        }

        let starSpots: [(CGFloat, CGFloat, CGFloat)] = [
            (0.08, 0.94, 1.1),
            (0.16, 0.975, 1.3),
            (0.27, 0.925, 1.0),
            (0.39, 0.96, 1.2),
            (0.51, 0.935, 1.0),
            (0.63, 0.97, 1.4),
            (0.74, 0.92, 1.0),
            (0.86, 0.955, 1.15),
            (0.93, 0.93, 1.0)
        ]
        for spot in starSpots {
            let star = SKShapeNode(circleOfRadius: spot.2)
            star.fillColor = UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1)
            star.strokeColor = .clear
            star.position = CGPoint(x: spot.0 * size.width, y: spot.1 * size.height)
            star.zPosition = 1
            star.alpha = 0
            star.isHidden = true
            addChild(star)
            starNodes.append(star)
        }

        sunDisc.fillColor = SkyCycle.sample(at: 0).sun.uiColor
        sunDisc.strokeColor = UIColor(red: 0.62, green: 0.46, blue: 0.30, alpha: 0.9)
        sunDisc.lineWidth = 1.5
        sunDisc.zPosition = 0
        sunNode.addChild(sunDisc)
        let crease = CGMutablePath()
        crease.move(to: CGPoint(x: -8, y: -6))
        crease.addLine(to: CGPoint(x: 11, y: 5))
        let sunCrease = SKShapeNode(path: crease)
        sunCrease.strokeColor = UIColor(red: 0.72, green: 0.54, blue: 0.32, alpha: 0.75)
        sunCrease.lineWidth = 1.25
        sunCrease.zPosition = 1
        sunNode.addChild(sunCrease)
        sunNode.zPosition = 2
        addChild(sunNode)

        moonGlow.fillColor = UIColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1)
        moonGlow.strokeColor = .clear
        moonGlow.alpha = 0.16
        moonGlow.zPosition = 0
        moonBody.fillColor = UIColor(red: 0.97, green: 0.94, blue: 0.86, alpha: 1)
        moonBody.strokeColor = UIColor(red: 0.62, green: 0.56, blue: 0.46, alpha: 0.85)
        moonBody.lineWidth = 1.25
        moonBody.zPosition = 1
        moonBite.strokeColor = .clear
        moonBite.position = CGPoint(x: 8, y: 5)
        moonBite.zPosition = 2
        moonNode.addChild(moonGlow)
        moonNode.addChild(moonBody)
        moonNode.addChild(moonBite)
        moonNode.position = CGPoint(x: SkyCycle.moonXFraction * size.width, y: SkyCycle.moonYFraction * size.height)
        moonNode.zPosition = 2
        addChild(moonNode)

        farCloudNode.zPosition = 3
        skylineNode.zPosition = 4
        nearCloudNode.zPosition = 5
        obstacleNode.zPosition = 10
        addChild(farCloudNode)
        addChild(skylineNode)
        addChild(nearCloudNode)
        addChild(obstacleNode)
        buildSkyline()
        configurePlane()
    }

    private func buildSkyline() {
        let papers = SkyCycle.collagePapers
        let specs: [(CGFloat, CGPath, Int)] = [
            (6, peak(width: 52, body: 100, rise: 38, lean: 0.46), 0),
            (66, shed(width: 36, body: 72, rise: 34, highOnLeft: true), 1),
            (110, folded(width: 70, body: 120), 2),
            (188, peak(width: 24, body: 90, rise: 58, lean: 0.50), 3),
            (220, lean(width: 52, body: 108, skew: 16, rise: 30), 4),
            (286, shed(width: 40, body: 64, rise: 26, highOnLeft: false), 5),
            (332, peak(width: 52, body: 128, rise: 36, lean: 0.62), 6)
        ]
        for spec in specs {
            let node = SKShapeNode(path: spec.1)
            node.position = CGPoint(x: spec.0, y: 0)
            node.lineWidth = 1
            node.zPosition = CGFloat(spec.2) * 0.01
            skylineNode.addChild(node)
            let paper = papers[spec.2 % papers.count]
            skyline.append(SkylinePiece(node: node, paper: paper))
        }
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
        planeNode.zPosition = 16

        let shadow = SKShapeNode(path: path)
        shadow.fillColor = UIColor(red: 0.33, green: 0.29, blue: 0.26, alpha: 0.20)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2.2, y: -3.2)
        shadow.zPosition = -1
        planeNode.addChild(shadow)

        let crease = CGMutablePath()
        crease.move(to: CGPoint(x: -halfW * 0.32, y: 0))
        crease.addLine(to: CGPoint(x: halfW * 0.2, y: halfH * 0.18))
        creaseNode.path = crease
        creaseNode.strokeColor = AppTheme.planeStroke.withAlphaComponent(0.7)
        creaseNode.lineWidth = 1
        creaseNode.zPosition = 1
        planeNode.addChild(creaseNode)
        addChild(planeNode)
    }

    /// Clouds and the sky read `flightTime`. A crash freezes it, so the page freezes
    /// with it. A new run id rebuilds the cloud set and starts the clock at morning.
    private func syncDecor(to snapshot: GameSnapshot) {
        if snapshot.runID != decoratedRunID {
            decoratedRunID = snapshot.runID
            rebuildClouds(seed: snapshot.runSeed)
            cloudFlightTime = snapshot.flightTime
        } else {
            let elapsed = snapshot.flightTime - cloudFlightTime
            cloudFlightTime = snapshot.flightTime
            if elapsed > 0 {
                advanceClouds(elapsed: elapsed, scroll: snapshot.scrollSpeed)
            }
        }
        apply(SkyCycle.sample(at: snapshot.flightTime))
    }

    private func apply(_ sample: SkyCycle.Sample) {
        let count = skyBands.count
        if count > 1 {
            for (index, band) in skyBands.enumerated() {
                let t = CGFloat(index) / CGFloat(count - 1)
                band.color = sample.bottom.mix(sample.top, t).uiColor
            }
        }
        backgroundColor = sample.top.uiColor
        view?.backgroundColor = sample.top.uiColor

        let starsVisible = sample.starAlpha > 0.04
        for star in starNodes {
            star.isHidden = !starsVisible
            star.alpha = sample.starAlpha * 0.7
        }

        let sunVisible = sample.sunAlpha > 0.03 && sample.sunAltitude > 0
        sunNode.isHidden = !sunVisible
        sunNode.alpha = sample.sunAlpha
        sunDisc.fillColor = sample.sun.uiColor
        sunNode.position = CGPoint(
            x: sample.sunX * size.width,
            y: SkyCycle.sunHeightFraction(sample) * size.height
        )

        let moonVisible = sample.moonAlpha > 0.03
        moonNode.isHidden = !moonVisible
        moonNode.alpha = sample.moonAlpha
        moonBite.fillColor = sample.top.mix(sample.bottom, 0.12).uiColor

        let cloudColor = SkyCycle.cloudTint(sample).uiColor
        for cloud in clouds {
            for puff in cloud.puffs {
                puff.fillColor = cloudColor.withAlphaComponent(cloud.alpha)
            }
        }

        let edge = PaperRGB(r: 0.42, g: 0.38, b: 0.36)
        for piece in skyline {
            let tint = SkyCycle.buildingTint(piece.paper, sample)
            piece.node.fillColor = tint.uiColor
            piece.node.strokeColor = tint.mix(edge, 0.28).uiColor.withAlphaComponent(0.45)
        }
    }

    private func rebuildClouds(seed: UInt64) {
        farCloudNode.removeAllChildren()
        nearCloudNode.removeAllChildren()
        clouds.removeAll()

        var rng = RunRNG(seed: seed)
        let count = 2 + Int(rng.unit() * 5)
        let farCount = max(1, count / 2)
        for index in 0..<count {
            let far = index < farCount
            let width = CGFloat(far ? 100 + rng.unit() * 70 : 140 + rng.unit() * 80)
            let height = CGFloat(far ? 26 + rng.unit() * 18 : 34 + rng.unit() * 22)
            let yFraction = far ? 0.70 + rng.unit() * 0.18 : 0.30 + rng.unit() * 0.24
            let parallax = CGFloat(far ? 0.15 + rng.unit() * 0.10 : 0.30 + rng.unit() * 0.10)
            let node = SKNode()
            var puffs: [SKShapeNode] = []
            let specs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (width, height, 0, 0),
                (width * 0.62, height * 0.78, -width * 0.28, height * 0.12),
                (width * 0.55, height * 0.70, width * 0.26, -height * 0.08)
            ]
            for spec in specs {
                let puff = SKShapeNode(ellipseOf: CGSize(width: spec.0, height: spec.1))
                puff.position = CGPoint(x: spec.2, y: spec.3)
                puff.strokeColor = .clear
                puff.lineWidth = 0
                node.addChild(puff)
                puffs.append(puff)
            }
            let parent = far ? farCloudNode : nearCloudNode
            parent.addChild(node)
            let cloud = Cloud(
                node: node,
                puffs: puffs,
                width: width,
                anchorX: CGFloat(rng.unit()) * size.width,
                y: CGFloat(yFraction) * size.height,
                parallax: parallax,
                travel: 0,
                bobPhase: CGFloat(rng.unit() * Double.pi * 2),
                alpha: far ? 0.58 : 0.38
            )
            clouds.append(cloud)
            node.position = CGPoint(x: cloud.anchorX, y: cloud.y)
        }
    }

    private func advanceClouds(elapsed: Double, scroll: Double) {
        let travelBase = CGFloat(elapsed * scroll)
        for index in clouds.indices {
            let span = size.width + clouds[index].width + 80
            clouds[index].travel += travelBase * clouds[index].parallax
            if span > 1, clouds[index].travel > span * 8 {
                clouds[index].travel = clouds[index].travel.truncatingRemainder(dividingBy: span)
            }
            let minX = -clouds[index].width - 20
            var shifted = clouds[index].anchorX - clouds[index].travel - minX
            if span > 1 {
                shifted = shifted.truncatingRemainder(dividingBy: span)
                if shifted < 0 {
                    shifted += span
                }
            }
            let bob = CGFloat(sin(cloudFlightTime * 0.17 + Double(clouds[index].bobPhase))) * 4
            clouds[index].node.position = CGPoint(x: shifted + minX, y: clouds[index].y + bob)
        }
    }

    private func draw(_ window: Obstacle) {
        let palette = AppTheme.facades[abs(window.id) % AppTheme.facades.count]
        let left = CGFloat(window.left)
        let width = CGFloat(window.width)
        let gapBottom = CGFloat(window.gapBottom)
        let gapTop = CGFloat(window.gapTop)
        let worldHeight = CGFloat(session.config.worldHeight)
        let lip: CGFloat = 7
        let outer = darkened(palette, 0.66)

        addRect(
            CGRect(x: left, y: 0, width: width, height: max(0, gapBottom - lip)),
            fill: palette,
            stroke: outer,
            lineWidth: 2.25,
            z: 0
        )
        addRect(
            CGRect(x: left, y: gapTop + lip, width: width, height: max(0, worldHeight - (gapTop + lip))),
            fill: palette,
            stroke: outer,
            lineWidth: 2.25,
            z: 0
        )
        addRect(
            CGRect(x: left, y: gapBottom - lip, width: width, height: lip),
            fill: AppTheme.paperLip,
            stroke: AppTheme.gapEdge,
            lineWidth: 1.75,
            z: 1
        )
        addRect(
            CGRect(x: left, y: gapTop, width: width, height: lip),
            fill: AppTheme.paperLip,
            stroke: AppTheme.gapEdge,
            lineWidth: 1.75,
            z: 1
        )
    }

    private func addRect(
        _ rect: CGRect,
        fill: UIColor,
        stroke: UIColor,
        lineWidth: CGFloat,
        z: CGFloat
    ) {
        guard rect.width > 1, rect.height > 1 else { return }
        let node = SKShapeNode(path: CGPath(rect: rect, transform: nil))
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = lineWidth
        node.zPosition = z
        obstacleNode.addChild(node)
    }

    private func darkened(_ color: UIColor, _ factor: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(red: red * factor, green: green * factor, blue: blue * factor, alpha: 1)
    }

    private func peak(width: CGFloat, body: CGFloat, rise: CGFloat, lean: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: body))
        path.addLine(to: CGPoint(x: width * lean, y: body + rise))
        path.addLine(to: CGPoint(x: width, y: body))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.closeSubpath()
        return path
    }

    private func shed(width: CGFloat, body: CGFloat, rise: CGFloat, highOnLeft: Bool) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        if highOnLeft {
            path.addLine(to: CGPoint(x: 0, y: body + rise))
            path.addLine(to: CGPoint(x: width, y: body))
        } else {
            path.addLine(to: CGPoint(x: 0, y: body))
            path.addLine(to: CGPoint(x: width, y: body + rise))
        }
        path.addLine(to: CGPoint(x: width, y: 0))
        path.closeSubpath()
        return path
    }

    private func folded(width: CGFloat, body: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: body))
        path.addLine(to: CGPoint(x: width * 0.28, y: body + 36))
        path.addLine(to: CGPoint(x: width * 0.48, y: body + 8))
        path.addLine(to: CGPoint(x: width * 0.72, y: body + 44))
        path.addLine(to: CGPoint(x: width, y: body + 6))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.closeSubpath()
        return path
    }

    private func lean(width: CGFloat, body: CGFloat, skew: CGFloat, rise: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: skew, y: body))
        path.addLine(to: CGPoint(x: skew + width * 0.42, y: body + rise))
        path.addLine(to: CGPoint(x: skew + width, y: body * 0.94))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct Cloud {
    var node: SKNode
    var puffs: [SKShapeNode]
    var width: CGFloat
    var anchorX: CGFloat
    var y: CGFloat
    var parallax: CGFloat
    var travel: CGFloat
    var bobPhase: CGFloat
    var alpha: CGFloat
}

private struct SkylinePiece {
    var node: SKShapeNode
    var paper: PaperRGB
}

private struct RunRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func unit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}
