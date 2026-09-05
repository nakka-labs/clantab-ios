import AppIntents

/// Registers `AddExpenseIntent` with Siri/Shortcuts so it's discoverable
/// without the user first building a custom shortcut (`FEATURE_BACKLOG.md`
/// "Siri / App Intents").
struct ClanTabShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "Add an expense to \(.applicationName)",
                "Log an expense in \(.applicationName)",
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle"
        )
    }
}
