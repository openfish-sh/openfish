import NaturalLanguage

/// The kinds of named entity we surface — the seed of a future people/orgs index.
enum EntityKind: String, Sendable, Codable, CaseIterable {
    case person, place, organization

    /// Map Apple's name-type tags onto our kinds (ignoring everything else).
    init?(_ tag: NLTag) {
        switch tag {
        case .personalName: self = .person
        case .placeName: self = .place
        case .organizationName: self = .organization
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .person: return "Person"
        case .place: return "Place"
        case .organization: return "Organization"
        }
    }
}

/// A named entity recognized in some text.
struct NamedEntity: Hashable, Sendable, Codable {
    let name: String
    let kind: EntityKind
}

/// An entity plus how many times it was mentioned across the scanned text.
struct EntityMention: Hashable, Sendable {
    let entity: NamedEntity
    let count: Int
}

/// On-device named-entity extraction via Apple's NaturalLanguage — no network, no
/// API cost, runs locally.
///
/// It recognizes people, places, and organizations and leans on capitalization,
/// so it does well on well-formed text (window titles, emails, documents) and
/// under-recognizes lowercase casual chat and novel product names. It's a *seed*
/// for an entity index, not the whole picture — an LLM pass can fill the gaps
/// later. This notion is Openfish's own.
enum EntityExtractor {
    private static let wantedSchemes: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

    /// Every entity occurrence found in `text`, in reading order (duplicates kept;
    /// the rollup tallies them).
    static func entities(in text: String) -> [NamedEntity] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found: [NamedEntity] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word,
                             scheme: .nameType, options: wantedSchemes) { tag, range in
            if let tag, let kind = EntityKind(tag) {
                let name = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { found.append(NamedEntity(name: name, kind: kind)) }
            }
            return true
        }
        return found
    }
}

/// Tallies entities across many pieces of text — the seed of a people/orgs index.
/// Identical names of the same kind merge case-insensitively (first-seen spelling
/// kept for display). It does NOT resolve "Jane" into "Jane Smith" — that's entity
/// resolution, deliberately out of scope for the seed.
struct EntityRollup {
    private struct Bucket { var display: NamedEntity; var count: Int }
    private var buckets: [String: Bucket] = [:]

    private func key(_ e: NamedEntity) -> String { "\(e.kind.rawValue):\(e.name.lowercased())" }

    var isEmpty: Bool { buckets.isEmpty }

    mutating func add(_ text: String) {
        for entity in EntityExtractor.entities(in: text) { add(entity) }
    }

    mutating func add(_ entity: NamedEntity) {
        let k = key(entity)
        if var bucket = buckets[k] {
            bucket.count += 1
            buckets[k] = bucket
        } else {
            buckets[k] = Bucket(display: entity, count: 1)
        }
    }

    /// Entities ranked by mention count (desc), then name (case-insensitive asc).
    var ranked: [EntityMention] {
        buckets.values
            .map { EntityMention(entity: $0.display, count: $0.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.entity.name.localizedCaseInsensitiveCompare(rhs.entity.name) == .orderedAscending
            }
    }
}
