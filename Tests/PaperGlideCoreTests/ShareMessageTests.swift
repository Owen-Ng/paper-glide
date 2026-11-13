import PaperGlideCore
import XCTest

final class ShareMessageTests: XCTestCase {
    func testScoreZeroAndANormalScoreWithoutAName() {
        XCTAssertEqual(ShareMessage.subject, "Paper Glide")
        XCTAssertEqual(ShareMessage.text(score: 0, username: nil), "I scored 0 in Paper Glide")
        XCTAssertEqual(ShareMessage.text(score: 0, username: ""), "I scored 0 in Paper Glide")
        XCTAssertEqual(ShareMessage.text(score: 0, username: "   "), "I scored 0 in Paper Glide")
        XCTAssertEqual(ShareMessage.text(score: 12, username: nil), "I scored 12 in Paper Glide")
        XCTAssertEqual(ShareMessage.text(score: 1000, username: nil), "I scored 1000 in Paper Glide")
    }

    func testClaimedUsernameIsAppended() {
        XCTAssertEqual(
            ShareMessage.text(score: 12, username: "pilot"),
            "I scored 12 in Paper Glide as pilot"
        )
        XCTAssertEqual(
            ShareMessage.text(score: 0, username: "ada_1"),
            "I scored 0 in Paper Glide as ada_1"
        )
    }

    func testShareUsesTheRunScoreRatherThanAStoredBest() {
        let runScore = 3
        let storedBest = 40
        XCTAssertEqual(ShareMessage.text(score: runScore, username: nil), "I scored 3 in Paper Glide")
        XCTAssertNotEqual(
            ShareMessage.text(score: runScore, username: "pilot"),
            ShareMessage.text(score: storedBest, username: "pilot")
        )
    }

    func testNameClaimedOnTheDeathScreenIsWhatTheNextShareUses() async {
        let backend = FakeAccountBackend()
        let sync = AccountSync(
            backend: backend,
            sessions: MemorySessionStore(),
            store: MemoryCloudStore(),
            configured: true,
            now: backend.now,
            pause: { _ in }
        )
        _ = sync.prepare(online: true)
        _ = await sync.bootstrap()
        _ = sync.dismissLaunchPrompt()

        let runScore = 9
        _ = sync.record(score: runScore, durationSeconds: 30, playedAt: backend.now)
        let offered = sync.noteNewBest()
        XCTAssertTrue(offered.deathPromptVisible)
        XCTAssertNil(offered.username)
        let beforeClaim = ShareMessage.text(score: runScore, username: offered.username)
        XCTAssertEqual(beforeClaim, "I scored 9 in Paper Glide")

        let claimed = await sync.claim("Pilot")
        XCTAssertEqual(claimed.username, "pilot")
        XCTAssertFalse(claimed.deathPromptVisible)
        let atTapTime = ShareMessage.text(score: runScore, username: claimed.username)
        XCTAssertEqual(atTapTime, "I scored 9 in Paper Glide as pilot")
        XCTAssertNotEqual(atTapTime, beforeClaim)
    }

    func testShareTextHasNoRankAndNoURL() {
        let samples = [
            ShareMessage.text(score: 0, username: nil),
            ShareMessage.text(score: 12, username: nil),
            ShareMessage.text(score: 12, username: "pilot"),
            ShareMessage.text(score: 9, username: "ada_1"),
            ShareMessage.subject
        ]
        let banned = ["rank", "http", "www", "apple.com", "testflight", "flappy", "new best"]
        for sample in samples {
            let lowered = sample.lowercased()
            for word in banned {
                XCTAssertFalse(lowered.contains(word), "\(sample) contains \(word)")
            }
            XCTAssertFalse(sample.contains("#"))
        }
    }
}
