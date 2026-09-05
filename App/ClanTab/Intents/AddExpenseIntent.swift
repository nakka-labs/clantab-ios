import AppIntents
import ClanTabKit

/// Spoken/displayed when `AddExpenseIntent.perform()` can't go through.
enum AddExpenseIntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount
    case needsSignIn
    case notAMember(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount:
            "Enter an amount greater than zero."
        case .needsSignIn:
            "Open ClanTab and sign in first."
        case .notAMember(let name):
            "You're not a member of \(name) yet — open ClanTab to join it first."
        }
    }
}

/// The pure pieces of the intent — pulled out of `perform()` so they're
/// unit-testable without Keychain/network access, which `AppIntent.perform()`
/// itself can't be given a fake for (`FEATURE_BACKLOG.md` "Siri / App
/// Intents").
enum AddExpenseIntentLogic {
    /// Siri delivers the amount as a `Double` — converted to minor units once,
    /// right at this boundary, per `AGENTS.md`'s "convert only at the edge"
    /// rule for money.
    static func minorUnits(from amount: Double) -> Int64 {
        Int64((amount * 100).rounded())
    }

    /// Always-equal-split, paid-by-you (`FEATURE_BACKLOG.md`'s scoped-down
    /// v1: no voice control over payer or split type). An empty/whitespace
    /// description falls back to a plain placeholder rather than sending an
    /// empty string.
    static func buildRequest(
        payerId: String,
        memberIds: [String],
        amountMinor: Int64,
        currency: String,
        description: String,
        date: Date,
        id: String
    ) -> AddExpenseRequest {
        let trimmed = description.trimmingCharacters(in: .whitespaces)
        return AddExpenseRequest(
            id: id,
            payerId: payerId,
            amountMinor: amountMinor,
            currency: currency,
            description: trimmed.isEmpty ? "Expense" : trimmed,
            date: date,
            splitType: .equal,
            splits: Validation.equalSplit(amountMinor: amountMinor, memberIds: memberIds, remainderRecipient: payerId)
        )
    }
}

/// "Add a ₹500 expense to Flatmates" (`FEATURE_BACKLOG.md`). Group is
/// disambiguated by name via `GroupEntity`; the payer is always the
/// signed-in user's own membership in that group, and the split is always
/// equal among its *current* members — no voice control over either, the
/// scope cut that keeps this out of "moderate-high effort" territory.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add an Expense"
    static let description = IntentDescription(
        "Add an expense to a ClanTab group, split equally among its current members, paid by you."
    )

    @Parameter(title: "Group")
    var group: GroupEntity

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Description")
    var expenseDescription: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add a \(\.$amount) expense to \(\.$group) for \(\.$expenseDescription)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else { throw AddExpenseIntentError.invalidAmount }
        guard let session = KeychainSessionStore().load(), !session.isExpired() else {
            throw AddExpenseIntentError.needsSignIn
        }

        // A fresh, stateless client — Siri constructs a new `AddExpenseIntent`
        // per invocation, so there's no live `AuthViewModel`/`GroupViewModel`
        // to reuse; this mirrors exactly what those do on the app's own
        // launch/refresh paths, just called directly.
        let client = ClanTabClient(baseURL: AppConfig.apiBaseURL)
        let myGroups = try await client.myGroups(token: session.token).groups
        guard let membership = myGroups.first(where: { $0.groupId == group.id }) else {
            throw AddExpenseIntentError.notAMember(group.name)
        }

        // The cached access token from ordinary app use, if any — a group
        // predating `ACCESS_TOKEN_PLAN.md` (or one this device only ever
        // learned about via `GET /api/auth/groups`) needs none; the Bearer
        // session above already satisfies `requireGroup`'s claimed-member
        // fallback either way.
        let accessToken = UserDefaultsKnownGroupsStore(defaults: .standard).all().first { $0.groupId == group.id }?.accessToken
        let state = try await client.fetchGroupState(groupId: group.id, accessToken: accessToken)

        let amountMinor = AddExpenseIntentLogic.minorUnits(from: amount)
        let request = AddExpenseIntentLogic.buildRequest(
            payerId: membership.memberId,
            memberIds: state.members.map(\.id),
            amountMinor: amountMinor,
            currency: state.group.currency,
            description: expenseDescription ?? "",
            date: Date(),
            id: UUID().uuidString
        )
        _ = try await client.addExpense(groupId: group.id, request, accessToken: accessToken)

        let amountText = MoneyFormat.string(minorUnits: amountMinor, currency: state.group.currency)
        return .result(dialog: "Added \(amountText) to \(group.name).")
    }
}
