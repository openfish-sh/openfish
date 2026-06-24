import XCTest
@testable import Koifish

final class ProfileTests: XCTestCase {
    func testCodableRoundTrip() {
        let p = Profile(name: "Work — Sales", brief: "I sell widgets", styleSeed: "punchy, friendly")
        let data = try! JSONEncoder().encode(p)
        let back = try! JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(back, p)
    }

    func testProfileListRoundTrips() {
        let list = [Profile(name: "Default"), Profile(name: "Work")]
        let data = try! JSONEncoder().encode(list)
        XCTAssertEqual(try! JSONDecoder().decode([Profile].self, from: data), list)
    }

    func testResolveActiveKeepsSavedWhenItStillExists() {
        let a = Profile(name: "A"), b = Profile(name: "B")
        XCTAssertEqual(ProfileStore.resolveActiveID(in: [a, b], saved: b.id), b.id)
    }

    func testResolveActiveFallsBackToFirstWhenSavedIsGone() {
        let a = Profile(name: "A"), b = Profile(name: "B")
        XCTAssertEqual(ProfileStore.resolveActiveID(in: [a, b], saved: UUID()), a.id)
        XCTAssertEqual(ProfileStore.resolveActiveID(in: [a, b], saved: nil), a.id)
    }

    func testResolveActiveIsNilForEmptyList() {
        XCTAssertNil(ProfileStore.resolveActiveID(in: [], saved: UUID()))
    }
}
