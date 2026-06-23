import XCTest
@testable import Koifish

final class InteractionLogTrimTests: XCTestCase {
    func testKeepsOnlyTheLastNLines() {
        XCTAssertEqual(InteractionLog.keepingLast(2, of: "a\nb\nc\n"), "b\nc\n")
        XCTAssertEqual(InteractionLog.keepingLast(2, of: "a\nb\nc"), "b\nc\n")   // no trailing newline in
        XCTAssertEqual(InteractionLog.keepingLast(1, of: "only\n"), "only\n")
    }

    func testLeavesShortContentUntouched() {
        XCTAssertEqual(InteractionLog.keepingLast(5, of: "a\nb\n"), "a\nb\n")
        XCTAssertEqual(InteractionLog.keepingLast(3, of: ""), "")
    }
}

final class UserBriefTests: XCTestCase {
    func testContentTrimsAndEmptyIsNil() {
        XCTAssertNil(UserBrief("   \n ").content)
        XCTAssertEqual(UserBrief("  hi  ").content, "hi")
    }

    func testEmptyBriefProducesNoPromptBlock() {
        XCTAssertTrue(UserBrief("").promptBlock.isEmpty)
        XCTAssertTrue(UserBrief("   ").promptBlock.isEmpty)
    }

    func testLongBriefIsTruncatedInThePrompt() {
        let huge = String(repeating: "x", count: UserBrief.maxPromptChars + 1000)
        let block = UserBrief(huge).promptBlock
        XCTAssertTrue(block.contains("…"))
        XCTAssertFalse(block.contains(huge))                 // the full text never lands
        XCTAssertLessThan(block.count, huge.count)
    }

    func testShortBriefIsKeptVerbatim() {
        let block = UserBrief("I'm Sam, I run support at Acme.").promptBlock
        XCTAssertTrue(block.contains("I'm Sam, I run support at Acme."))
    }
}

final class StyleProfileDecodingTests: XCTestCase {
    private func decode(_ json: String) -> StyleProfile? {
        try? JSONDecoder().decode(StyleProfile.self, from: Data(json.utf8))
    }

    func testMissingKeysFallBackToDefaults() {
        let p = decode(#"{"description":"casual, lowercase"}"#)
        XCTAssertEqual(p?.description, "casual, lowercase")
        XCTAssertEqual(p?.sampleCount, 0)
        XCTAssertNil(p?.updatedAtEpoch)
    }

    func testEmptyObjectDecodesToDefaults() {
        let p = decode("{}")
        XCTAssertEqual(p?.description, "")
        XCTAssertEqual(p?.sampleCount, 0)
    }

    func testUnknownFutureKeysAreIgnored() {
        let p = decode(#"{"description":"hi","sampleCount":7,"somethingNew":42}"#)
        XCTAssertEqual(p?.description, "hi")
        XCTAssertEqual(p?.sampleCount, 7)
    }

    func testRoundTrips() {
        var original = StyleProfile()
        original.description = "terse, dry humor"
        original.sampleCount = 12
        original.updatedAtEpoch = 1_700_000_000
        let data = try! JSONEncoder().encode(original)
        let back = try! JSONDecoder().decode(StyleProfile.self, from: data)
        XCTAssertEqual(back.description, "terse, dry humor")
        XCTAssertEqual(back.sampleCount, 12)
        XCTAssertEqual(back.updatedAtEpoch, 1_700_000_000)
    }
}
