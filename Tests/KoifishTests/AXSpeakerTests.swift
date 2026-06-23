import XCTest
@testable import Koifish

/// Speaker attribution parsed from chat-bubble accessibility descriptions.
/// Sample descriptions are taken verbatim from a real Messages AX tree.
final class AXSpeakerAttributionTests: XCTestCase {
    func testUserOwnMessageIsMe() {
        XCTAssertEqual(AXContext.messageSpeaker(fromDescription: "Your iMessage, Nej, 14:28"), "Me")
        XCTAssertEqual(AXContext.messageSpeaker(fromDescription: "Your iMessage, Har du ett nummer?, 17:20"), "Me")
    }

    func testReceivedMessageKeepsSenderName() {
        XCTAssertEqual(AXContext.messageSpeaker(fromDescription: "Ellen ❤️, Vi är i tessin, 16:22"), "Ellen ❤️")
        XCTAssertEqual(AXContext.messageSpeaker(fromDescription: "Ellen ❤️, Ja gärna , 17:11"), "Ellen ❤️")
    }

    func testBodyWithCommasStillResolvesSpeaker() {
        XCTAssertEqual(AXContext.messageSpeaker(fromDescription: "Your iMessage, Hey, you around?, 9:05"), "Me")
        XCTAssertEqual(AXContext.messageSpeaker(fromDescription: "Sam, sure, see you then, 10:30"), "Sam")
    }

    func testNonMessageDescriptionsAreIgnored() {
        XCTAssertNil(AXContext.messageSpeaker(fromDescription: "Message"))
        XCTAssertNil(AXContext.messageSpeaker(fromDescription: "Conversations"))
        XCTAssertNil(AXContext.messageSpeaker(fromDescription: "Today 16:22"))   // no comma → not "a, b, time"
        XCTAssertNil(AXContext.messageSpeaker(fromDescription: ""))
    }

    func testEmptySpeakerIsIgnored() {
        XCTAssertNil(AXContext.messageSpeaker(fromDescription: ", body, 12:00"))
    }

    func testLooksLikeTime() {
        XCTAssertTrue(AXContext.looksLikeTime("14:28"))
        XCTAssertTrue(AXContext.looksLikeTime("9:05 PM"))
        XCTAssertFalse(AXContext.looksLikeTime("Nybrogatan"))
        XCTAssertFalse(AXContext.looksLikeTime("hello"))
    }
}
