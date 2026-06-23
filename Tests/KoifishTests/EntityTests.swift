import XCTest
@testable import Koifish

/// Exercises the on-device entity extractor. Apple's name model can shift between
/// OS versions, so we assert on stable, well-known, capitalized entities and use
/// containment checks rather than exact full-set equality.
final class EntityExtractorTests: XCTestCase {
    private func names(_ entities: [NamedEntity], of kind: EntityKind) -> Set<String> {
        Set(entities.filter { $0.kind == kind }.map { $0.name })
    }

    func testExtractsKnownPeoplePlacesOrgs() {
        let text = "I met Tim Cook in Cupertino on Tuesday. Acme Corp and Microsoft both replied."
        let entities = EntityExtractor.entities(in: text)

        XCTAssertTrue(names(entities, of: .person).contains("Tim Cook"))
        XCTAssertTrue(names(entities, of: .place).contains("Cupertino"))
        let orgs = names(entities, of: .organization)
        XCTAssertTrue(orgs.contains("Microsoft"))
        XCTAssertTrue(orgs.contains("Acme Corp"))
    }

    func testEmptyTextYieldsNothing() {
        XCTAssertTrue(EntityExtractor.entities(in: "").isEmpty)
        XCTAssertTrue(EntityExtractor.entities(in: "   \n  ").isEmpty)
    }

    func testRollupTalliesAndRanksByMentionCount() {
        var rollup = EntityRollup()
        rollup.add("Microsoft shipped it. Tim Cook spoke.")
        rollup.add("Microsoft again, and Microsoft once more.")  // Microsoft now 3, Tim Cook 1

        let ranked = rollup.ranked
        XCTAssertFalse(ranked.isEmpty)
        // Most-mentioned wins the top slot.
        XCTAssertEqual(ranked.first?.entity.name, "Microsoft")
        XCTAssertEqual(ranked.first?.entity.kind, .organization)
        XCTAssertEqual(ranked.first?.count, 3)
    }

    func testRollupMergesSameNameCaseInsensitively() {
        var rollup = EntityRollup()
        // Same org, two casings — should merge into one bucket with count 2.
        rollup.add(NamedEntity(name: "Microsoft", kind: .organization))
        rollup.add(NamedEntity(name: "microsoft", kind: .organization))

        let orgs = rollup.ranked.filter { $0.entity.kind == .organization }
        XCTAssertEqual(orgs.count, 1)
        XCTAssertEqual(orgs.first?.count, 2)
    }

    func testSameSpellingDifferentKindStaySeparate() {
        var rollup = EntityRollup()
        rollup.add(NamedEntity(name: "Jordan", kind: .person))
        rollup.add(NamedEntity(name: "Jordan", kind: .place))
        XCTAssertEqual(rollup.ranked.count, 2)
    }

    func testEmptyRollupIsEmpty() {
        XCTAssertTrue(EntityRollup().isEmpty)
        XCTAssertTrue(EntityRollup().ranked.isEmpty)
    }
}
