import Foundation

/// Abstracts local persistence of recurring-reminder templates
/// (`FEATURE_BACKLOG.md`). The app supplies `UserDefaultsRecurringTemplatesStore`;
/// tests and previews use `InMemoryRecurringTemplatesStore`. Local-only, like
/// `KnownGroupsStore` — no backend or wire change for this feature.
public protocol RecurringTemplatesStoring: Sendable {
    /// This group's templates, oldest-created first.
    func all(forGroup groupId: String) -> [RecurringTemplate]
    /// Insert or update (matched by `id`).
    func save(_ template: RecurringTemplate)
    func remove(id: String)
}

/// `UserDefaults`-backed store, all groups' templates in one JSON array under
/// `"clantab.recurringTemplates"` (small enough that per-group keys would be
/// premature — same reasoning as `UserDefaultsKnownGroupsStore`).
public final class UserDefaultsRecurringTemplatesStore: RecurringTemplatesStoring, @unchecked Sendable {
    private static let key = "clantab.recurringTemplates"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func all(forGroup groupId: String) -> [RecurringTemplate] {
        lock.lock(); defer { lock.unlock() }
        return load().filter { $0.groupId == groupId }.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ template: RecurringTemplate) {
        lock.lock(); defer { lock.unlock() }
        var templates = load()
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        persist(templates)
    }

    public func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        persist(load().filter { $0.id != id })
    }

    private func load() -> [RecurringTemplate] {
        guard let data = defaults.data(forKey: Self.key),
              let templates = try? JSONDecoder().decode([RecurringTemplate].self, from: data)
        else { return [] }
        return templates
    }

    private func persist(_ templates: [RecurringTemplate]) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// In-memory store for tests and SwiftUI previews.
public final class InMemoryRecurringTemplatesStore: RecurringTemplatesStoring, @unchecked Sendable {
    private var templates: [RecurringTemplate]
    private let lock = NSLock()

    public init(_ templates: [RecurringTemplate] = []) {
        self.templates = templates
    }

    public func all(forGroup groupId: String) -> [RecurringTemplate] {
        lock.lock(); defer { lock.unlock() }
        return templates.filter { $0.groupId == groupId }.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ template: RecurringTemplate) {
        lock.lock(); defer { lock.unlock() }
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
    }

    public func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        templates.removeAll { $0.id == id }
    }
}
