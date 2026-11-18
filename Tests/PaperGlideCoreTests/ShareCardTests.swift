import PaperGlideCore
import XCTest

final class ShareCardTests: XCTestCase {
    func testScoreZeroAndAMissingName() {
        for username in [nil, "", "   "] as [String?] {
            let card = ShareCard.copy(score: 0, username: username)
            XCTAssertEqual(card.title, "Paper Glide")
            XCTAssertEqual(card.subject, "Paper Glide")
            XCTAssertEqual(card.scoredLine, "I scored")
            XCTAssertEqual(card.scoreText, "0")
            XCTAssertEqual(card.caption, "I scored 0 in Paper Glide")
            XCTAssertEqual(card.caption, ShareMessage.text(score: 0, username: username))
        }
        let twelve = ShareCard.copy(score: 12, username: nil)
        XCTAssertEqual(twelve.scoreText, "12")
        XCTAssertEqual(twelve.caption, "I scored 12 in Paper Glide")
    }

    func testClaimedNameIsTheScoredLineAndTheCaption() {
        let card = ShareCard.copy(score: 27, username: "owen")
        XCTAssertEqual(card.scoredLine, "owen scored")
        XCTAssertEqual(card.scoreText, "27")
        XCTAssertEqual(card.caption, "I scored 27 in Paper Glide as owen")
        XCTAssertEqual(card.caption, ShareMessage.text(score: 27, username: "owen"))
    }

    func testSixteenCharacterNameAndFourDigitScoreStayOneLine() {
        let name = "skyward_pilot_01"
        XCTAssertEqual(name.count, UsernameRules.maximumLength)
        let card = ShareCard.copy(score: 4096, username: name)
        XCTAssertEqual(card.scoredLine, "skyward_pilot_01 scored")
        XCTAssertEqual(card.scoreText, "4096")
        XCTAssertFalse(card.scoredLine.contains("\n"))
        XCTAssertFalse(card.scoreText.contains("\n"))
        XCTAssertFalse(card.title.contains("\n"))
        XCTAssertEqual(card.caption, ShareMessage.text(score: 4096, username: name))
    }

    func testLinesShrinkUntilTheyFitAndNeverAskForASecondLine() {
        let fitted = ShareCard.pointSize(starting: 58, step: 2, maxWidth: 920) { size in
            size * 40
        }
        XCTAssertEqual(fitted, 22)
        XCTAssertLessThanOrEqual(fitted * 40, 920)

        let alreadyFits = ShareCard.pointSize(starting: 300, step: 10, maxWidth: 920) { _ in 100 }
        XCTAssertEqual(alreadyFits, 300)

        let stopped = ShareCard.pointSize(starting: 58, step: 2, maxWidth: 10) { _ in 10_000 }
        XCTAssertGreaterThan(stopped, 0)
        XCTAssertLessThan(stopped, 58)
    }

    func testAFailedRenderFallsBackToTheCaption() {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let card = ShareCard.offer(score: 27, username: "owen", renderedPNG: png)
        guard case .card(let bytes, let caption) = card else {
            return XCTFail("expected a card")
        }
        XCTAssertEqual(bytes, png)
        XCTAssertEqual(caption, "I scored 27 in Paper Glide as owen")

        let missing = ShareCard.offer(score: 0, username: nil, renderedPNG: nil)
        let empty = ShareCard.offer(score: 4, username: "pilot", renderedPNG: Data())
        XCTAssertEqual(missing, .text("I scored 0 in Paper Glide"))
        XCTAssertEqual(empty, .text("I scored 4 in Paper Glide as pilot"))
    }

    func testNameClaimedOnTheDeathScreenIsWhatTheNextCardUses() async {
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
        let before = ShareCard.copy(score: runScore, username: offered.username)
        XCTAssertEqual(before.scoredLine, "I scored")
        XCTAssertEqual(before.caption, "I scored 9 in Paper Glide")

        let claimed = await sync.claim("Pilot")
        let atTap = ShareCard.copy(score: runScore, username: claimed.username)
        XCTAssertEqual(atTap.scoredLine, "pilot scored")
        XCTAssertEqual(atTap.scoreText, "9")
        XCTAssertEqual(atTap.caption, "I scored 9 in Paper Glide as pilot")
        XCTAssertEqual(
            ShareCard.offer(score: runScore, username: claimed.username, renderedPNG: nil),
            .text(atTap.caption)
        )
    }

    func testCardCopyHasNoRankURLOrHashtag() {
        let samples = [
            ShareCard.copy(score: 0, username: nil),
            ShareCard.copy(score: 27, username: "owen"),
            ShareCard.copy(score: 4096, username: "skyward_pilot_01")
        ]
        let banned = ["rank", "http", "www", "apple.com", "testflight", "flappy", "new best"]
        for card in samples {
            let fields = [card.title, card.scoredLine, card.scoreText, card.caption, card.subject]
            for sample in fields {
                let lowered = sample.lowercased()
                for word in banned {
                    XCTAssertFalse(lowered.contains(word), "\(sample) contains \(word)")
                }
                XCTAssertFalse(sample.contains("#"))
            }
        }
    }
}
