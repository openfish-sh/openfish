import XCTest
@testable import Koifish

final class OnDeviceModelTests: XCTestCase {
    func testIsAvailableMatchesAvailableCase() {
        XCTAssertTrue(OnDeviceModel.Status.available.isAvailable)
        XCTAssertFalse(OnDeviceModel.Status.intelligenceNotEnabled.isAvailable)
        XCTAssertFalse(OnDeviceModel.Status.unsupportedOS.isAvailable)
        XCTAssertFalse(OnDeviceModel.Status.frameworkMissing.isAvailable)
    }

    func testEveryStatusHasADescription() {
        for status in [OnDeviceModel.Status.available, .unsupportedOS, .deviceNotEligible,
                       .intelligenceNotEnabled, .modelNotReady, .frameworkMissing] {
            XCTAssertFalse(status.description.isEmpty)
        }
    }

    func testStatusQueryIsConsistentAndSafe() {
        // Must not crash on any OS, and the convenience flag must track the case.
        let status = OnDeviceModel.status
        XCTAssertEqual(status.isAvailable, status == .available)
    }

    func testRespondThrowsUnavailableWhenModelIsOff() async {
        // On CI / a Mac with Apple Intelligence off, respond must fail fast with a
        // typed .unavailable rather than hang. (Skipped where the model is live.)
        guard !OnDeviceModel.isAvailable else { return }
        do {
            _ = try await OnDeviceModel.respond(to: "hello")
            XCTFail("expected GenerationError.unavailable")
        } catch let OnDeviceModel.GenerationError.unavailable(status) {
            XCTAssertFalse(status.isAvailable)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRespondIfAvailableReturnsNilWhenModelIsOff() async {
        guard !OnDeviceModel.isAvailable else { return }
        let result = await OnDeviceModel.respondIfAvailable(to: "hello")
        XCTAssertNil(result)
    }
}
