import PaperGlideCore
import XCTest

final class UsernameRulesTests: XCTestCase {
    func testNormalizeLowercasesAndTrims() {
        XCTAssertEqual(UsernameRules.normalize("  AbC_9 "), "abc_9")
    }

    func testLengthAndLeadingLetter() {
        XCTAssertEqual(UsernameRules.shapeProblem("ab"), .tooShort)
        XCTAssertEqual(UsernameRules.shapeProblem("  a "), .tooShort)
        XCTAssertEqual(UsernameRules.shapeProblem("___"), .mustStartWithLetter)
        XCTAssertEqual(UsernameRules.shapeProblem("1abc"), .mustStartWithLetter)
        XCTAssertEqual(UsernameRules.shapeProblem("abc"), nil)
        XCTAssertEqual(UsernameRules.shapeProblem(String(repeating: "a", count: 16)), nil)
        XCTAssertEqual(UsernameRules.shapeProblem(String(repeating: "a", count: 17)), .invalid)
    }

    func testAllowedCharacters() {
        XCTAssertEqual(UsernameRules.shapeProblem("ab c"), .invalid)
        XCTAssertEqual(UsernameRules.shapeProblem("ab!c"), .invalid)
        XCTAssertEqual(UsernameRules.shapeProblem("a__"), nil)
        XCTAssertNil(UsernameRules.problem("paper_1"))
    }

    func testReservedWordsAndLeetspeak() {
        let blocked = [
            "admin", "Admin", "adm1n", "adm_in",
            "paperglide", "p4p3rgl1de",
            "support", "supp0rt",
            "moderator", "m0der4t0r",
            "apple", "app1e",
            "official", "off1c1al",
            "xxadmin", "pineapple"
        ]
        for name in blocked {
            XCTAssertEqual(UsernameRules.problem(name), .unavailable, name)
        }
        XCTAssertEqual(UsernameRules.shapeProblem("4dm1n"), .mustStartWithLetter)
        XCTAssertEqual(UsernameRules.shapeProblem("0ff1c14l"), .mustStartWithLetter)
        XCTAssertNil(UsernameRules.problem("paper"))
        XCTAssertNil(UsernameRules.problem("glide"))
        XCTAssertNil(UsernameRules.problem("pilot_7"))
    }

    func testCopyNeverEchoesTheName() {
        let samples = ["admin", "paperglide", "4dm1n", "abc", "toolongnameplease"]
        for sample in samples {
            let messages = [
                NameCopy.tooShort, NameCopy.startWithLetter, NameCopy.invalid,
                NameCopy.taken, NameCopy.unavailable, NameCopy.offline, NameCopy.saveFailed
            ]
            for message in messages where sample.count >= 3 {
                XCTAssertFalse(message.lowercased().contains(sample.lowercased()), message)
            }
        }
        XCTAssertEqual(NameCopy.helper, "pick a name. letters, numbers and _ only. you can't change it later.")
        XCTAssertEqual(NameCopy.tooShort, "at least 3 characters")
        XCTAssertEqual(NameCopy.startWithLetter, "start with a letter")
        XCTAssertEqual(NameCopy.taken, "that name's taken. try another")
        XCTAssertEqual(NameCopy.unavailable, "that name isn't available. try another")
        XCTAssertEqual(NameCopy.invalid, "that name won't work. try another")
        XCTAssertEqual(NameCopy.offline, "you're offline. we'll check this name when you're back")
        XCTAssertEqual(NameCopy.saveFailed, "couldn't save. try again")
    }
}
