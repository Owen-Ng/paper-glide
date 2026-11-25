import Foundation
import PaperGlideCore
import XCTest

final class GoldenFixtureTests: XCTestCase {
    func testPaperGlideCoreMatchesCommittedFixtures() throws {
        let directory = fixturesDirectory()
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(urls.count, 3)
        for url in urls {
            let file = try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: url))
            XCTAssertEqual(file.format, GoldenFixture.format, url.lastPathComponent)
            XCTAssertFalse(file.steps.isEmpty, url.lastPathComponent)
            let actual = GoldenFixture.capture(
                name: file.name,
                seed: file.seed,
                tapSteps: file.tapSteps,
                maxSteps: file.steps.count - 1
            )
            assertMatch(file, actual, file: file.name)
            assertInvariants(file)
        }
    }

    private func assertMatch(_ expected: GoldenFile, _ actual: GoldenFile, file: String) {
        XCTAssertEqual(actual.steps.count, expected.steps.count, file)
        XCTAssertEqual(actual.tapSteps, expected.tapSteps, file)
        XCTAssertEqual(actual.seed, expected.seed, file)
        let tolerance = expected.tolerance
        XCTAssertEqual(actual.timestep, expected.timestep, accuracy: tolerance.time, file)
        for pair in zip(expected.steps, actual.steps) {
            let step = pair.0.step
            XCTAssertEqual(pair.1.step, pair.0.step, "\(file) step \(step)")
            XCTAssertEqual(pair.1.score, pair.0.score, "\(file) score \(step)")
            XCTAssertEqual(pair.1.phase, pair.0.phase, "\(file) phase \(step)")
            XCTAssertEqual(pair.1.flightTime, pair.0.flightTime, accuracy: tolerance.time, "\(file) time \(step)")
            XCTAssertEqual(pair.1.plane.x, pair.0.plane.x, accuracy: tolerance.position, "\(file) x \(step)")
            XCTAssertEqual(pair.1.plane.y, pair.0.plane.y, accuracy: tolerance.position, "\(file) y \(step)")
            XCTAssertEqual(pair.1.plane.velocityY, pair.0.plane.velocityY, accuracy: tolerance.velocity, "\(file) vy \(step)")
            XCTAssertEqual(pair.1.scrollSpeed, pair.0.scrollSpeed, accuracy: tolerance.scroll, "\(file) scroll \(step)")
            XCTAssertEqual(pair.1.spawnGapHeight, pair.0.spawnGapHeight, accuracy: tolerance.gap, "\(file) gap \(step)")
            XCTAssertEqual(pair.1.ramp.stepIndex, pair.0.ramp.stepIndex, "\(file) ramp \(step)")
            XCTAssertEqual(pair.1.ramp.gapHeight, pair.0.ramp.gapHeight, accuracy: tolerance.gap, "\(file) ramp gap \(step)")
            XCTAssertEqual(pair.1.ramp.scrollSpeed, pair.0.ramp.scrollSpeed, accuracy: tolerance.scroll, "\(file) ramp scroll \(step)")
            XCTAssertEqual(pair.1.obstacles.count, pair.0.obstacles.count, "\(file) obstacles \(step)")
            for windows in zip(pair.0.obstacles, pair.1.obstacles) {
                XCTAssertEqual(windows.1.id, windows.0.id, "\(file) id \(step)")
                XCTAssertEqual(windows.1.left, windows.0.left, accuracy: tolerance.position, "\(file) left \(step)")
                XCTAssertEqual(windows.1.width, windows.0.width, accuracy: tolerance.position, "\(file) width \(step)")
                XCTAssertEqual(windows.1.gapCenterY, windows.0.gapCenterY, accuracy: tolerance.position, "\(file) center \(step)")
                XCTAssertEqual(windows.1.gapHeight, windows.0.gapHeight, accuracy: tolerance.gap, "\(file) opening \(step)")
                switch (windows.0.spacingFromPrevious, windows.1.spacingFromPrevious) {
                case (nil, nil):
                    break
                case let (lhs?, rhs?):
                    XCTAssertEqual(rhs, lhs, accuracy: tolerance.spacing, "\(file) spacing \(step)")
                default:
                    XCTFail("\(file) spacing null mismatch at step \(step)")
                }
            }
        }
    }

    private func assertInvariants(_ file: GoldenFile) {
        let name = file.name
        let standard = GameConfig.standard
        let tolerance = file.tolerance
        XCTAssertEqual(file.timestep, standard.physicsStep, accuracy: tolerance.time, name)
        XCTAssertEqual(file.config.physicsStep, standard.physicsStep, accuracy: tolerance.time, name)
        XCTAssertEqual(file.config.gravity, standard.gravity, accuracy: tolerance.position, name)
        XCTAssertEqual(file.config.obstacleGapHeight, standard.obstacleGapHeight, accuracy: tolerance.gap, name)
        XCTAssertEqual(file.config.obstacleSpacing, standard.obstacleSpacing, accuracy: tolerance.spacing, name)
        XCTAssertEqual(file.config.scrollSpeed, standard.scrollSpeed, accuracy: tolerance.scroll, name)
        XCTAssertEqual(file.config.worldHeight, standard.worldHeight, accuracy: tolerance.position, name)
        XCTAssertEqual(file.steps[0].score, 0, name)
        XCTAssertEqual(file.steps[0].phase, "playing", name)
        XCTAssertEqual(file.steps[0].plane.y, standard.planeStartY, accuracy: tolerance.position, name)
        XCTAssertEqual(file.steps[0].flightTime, 0, accuracy: tolerance.time, name)
        var previousScore = 0
        for step in file.steps {
            XCTAssertGreaterThanOrEqual(step.score, previousScore, name)
            previousScore = step.score
            let level = DifficultyRamp.level(
                score: step.score,
                baseGap: standard.obstacleGapHeight,
                baseScroll: standard.scrollSpeed
            )
            XCTAssertEqual(step.ramp.stepIndex, level.stepIndex, "\(name) ramp index \(step.step)")
            XCTAssertEqual(step.ramp.gapHeight, level.gapHeight, accuracy: tolerance.gap, name)
            XCTAssertEqual(step.ramp.scrollSpeed, level.scrollSpeed, accuracy: tolerance.scroll, name)
            XCTAssertEqual(step.scrollSpeed, step.ramp.scrollSpeed, accuracy: tolerance.scroll, name)
            XCTAssertEqual(step.spawnGapHeight, step.ramp.gapHeight, accuracy: tolerance.gap, name)
            for index in step.obstacles.indices {
                if index == 0 {
                    XCTAssertNil(step.obstacles[index].spacingFromPrevious, "\(name) first spacing")
                } else if let spacing = step.obstacles[index].spacingFromPrevious {
                    let delta = step.obstacles[index].left - step.obstacles[index - 1].left
                    XCTAssertEqual(spacing, delta, accuracy: tolerance.spacing, "\(name) spacing \(step.step)")
                } else {
                    XCTFail("\(name) missing spacing at step \(step.step)")
                }
            }
        }
        if name == "no-tap-fall" {
            XCTAssertEqual(file.steps.last?.phase, "dead")
            XCTAssertTrue(file.tapSteps.isEmpty)
        }
        if name == "pilot-ramp" {
            XCTAssertGreaterThanOrEqual(file.steps.map(\.score).max() ?? 0, 5)
            XCTAssertGreaterThanOrEqual(file.steps.map(\.ramp.stepIndex).max() ?? 0, 1)
        }
    }

    private func fixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/golden", isDirectory: true)
    }
}
