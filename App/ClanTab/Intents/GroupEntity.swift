import AppIntents
import ClanTabKit

/// A group Siri/Shortcuts can name — backed by whatever's in
/// `KnownGroupsStoring` on this device (`FEATURE_BACKLOG.md` "Siri / App
/// Intents"). Empty-named groups (never actually opened yet, so there's
/// nothing to say) are excluded — see `KnownGroup.name`'s doc comment.
struct GroupEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "ClanTab Group"
    static let defaultQuery = GroupEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct GroupEntityQuery: EntityQuery {
    private var knownGroups: KnownGroupsStoring { UserDefaultsKnownGroupsStore(defaults: .standard) }

    func entities(for identifiers: [String]) async throws -> [GroupEntity] {
        Self.namedGroups(knownGroups.all()).filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GroupEntity] {
        Self.namedGroups(knownGroups.all())
    }

    /// Pulled out as a pure function so the filtering rule (skip anything
    /// with no name yet) is unit-testable without a real `UserDefaults`.
    static func namedGroups(_ groups: [KnownGroup]) -> [GroupEntity] {
        groups.filter { !$0.name.isEmpty }.map { GroupEntity(id: $0.groupId, name: $0.name) }
    }
}
