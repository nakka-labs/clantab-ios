import SwiftUI
import PhotosUI
import ClanTabKit

/// Rename the group, change its default currency, rename or remove members, or
/// leave the group on this device (`DESIGN.md` §2). Reached from Group Home's
/// "Group Options" menu.
struct GroupSettingsView: View {
    let groupId: String
    /// A live snapshot from `GroupViewModel` — the member list re-renders after
    /// `onChanged` triggers a refetch.
    let state: GroupStateResponse
    let client: ClanTabClient
    /// This group's capability-link credential (`ACCESS_TOKEN_PLAN.md`) — used
    /// to authorize "Regenerate Link" itself, same as any other group route.
    let accessToken: String?
    /// The signed-in identity's session token — needed by the media-presign
    /// endpoint for the cover-image upload (`CHECKLIST.md` "Group cover image").
    var sessionToken: String?
    /// The signed-in member's own row in `state.members`, if any — gates the
    /// "My UPI ID" section (`FEATURE_BACKLOG.md` "UPI deep link on Settle
    /// Up"). `nil` for a device that hasn't claimed a member yet.
    let myMemberId: String?
    let onChanged: () -> Void
    /// Called with the fresh token right after a successful regenerate, so
    /// the caller (`GroupHomeView`'s `GroupViewModel`) can start using it
    /// immediately — before its own next `refetch()` would otherwise notice.
    let onRegenerated: (String) -> Void
    let onLeave: () -> Void
    let onDone: () -> Void

    @State private var name: String
    @State private var currency: String
    /// The group's chosen identity emoji (`CHECKLIST.md` "Group visual
    /// identity"), `""` for none. Picked from a preset set below rather than
    /// free text, so there's nothing to validate.
    @State private var emoji: String
    @State private var renamingMember: Member?
    @State private var renameText = ""
    @State private var newMemberName = ""
    @State private var isAddingMember = false
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var confirmingLeave = false
    @State private var confirmingRegenerate = false
    @State private var isRegenerating = false
    @State private var isArchiving = false
    /// The "Default Split" editor (`FEATURE_BACKLOG.md` "Default split config
    /// per group"): whether it's expanded, the per-member percent drafts, and
    /// the in-flight flag.
    @State private var editingDefaultSplit = false
    @State private var draftPercent: [String: String] = [:]
    @State private var isSavingDefaultSplit = false
    @State private var myUpiVpa = ""
    @State private var isSavingUpiVpa = false
    /// Drives the "Report a Problem" sheet (`FEATURE_BACKLOG.md`,
    /// `SHIP_PLAN.md` Track 3 §7) — set from either a member row's swipe
    /// action or the general entry point below.
    @State private var reportingTarget: (target: ReportTarget, label: String)?
    @State private var reportConfirmation: String?
    /// Cover image (`CHECKLIST.md` "Group cover image").
    @Environment(\.avatarImageLoader) private var avatarLoader
    @State private var pickedCover: PhotosPickerItem?
    @State private var isSavingCover = false

    init(
        groupId: String,
        state: GroupStateResponse,
        client: ClanTabClient,
        accessToken: String? = nil,
        sessionToken: String? = nil,
        myMemberId: String? = nil,
        onChanged: @escaping () -> Void,
        onRegenerated: @escaping (String) -> Void = { _ in },
        onLeave: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.groupId = groupId
        self.state = state
        self.client = client
        self.accessToken = accessToken
        self.sessionToken = sessionToken
        self.myMemberId = myMemberId
        self.onChanged = onChanged
        self.onRegenerated = onRegenerated
        self.onLeave = onLeave
        self.onDone = onDone
        _name = State(initialValue: state.group.name)
        _currency = State(initialValue: state.group.currency)
        _emoji = State(initialValue: state.group.emoji ?? "")
        _myUpiVpa = State(initialValue: state.members.first(where: { $0.id == myMemberId })?.upiVpa ?? "")
    }

    /// A small preset set — enough to give a trip / house / group a face,
    /// short enough to scan. Order roughly by how common the use is.
    static let emojiOptions = ["🏖️", "🏠", "✈️", "🍽️", "🎉", "🍻", "🚗", "⛰️", "⛺️", "🏝️", "🎓", "💼", "🏡", "🐶", "⚽️", "🎬"]

    private var myMember: Member? { state.members.first(where: { $0.id == myMemberId }) }
    private var trimmedMyUpiVpa: String { myUpiVpa.trimmingCharacters(in: .whitespaces) }
    private var isUpiVpaDirty: Bool { trimmedMyUpiVpa != (myMember?.upiVpa ?? "") }

    private var currencyChoices: [String] {
        AppConfig.supportedCurrencies.contains(currency)
            ? AppConfig.supportedCurrencies
            : [currency] + AppConfig.supportedCurrencies
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDirty: Bool {
        trimmedName != state.group.name
            || currency != state.group.currency
            || emoji != (state.group.emoji ?? "")
    }
    private var trimmedNewMemberName: String { newMemberName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                TextField("Group name", text: $name)
                Picker("Default currency", selection: $currency) {
                    ForEach(currencyChoices, id: \.self) { Text($0).tag($0) }
                }
                emojiPicker
            } header: {
                Text("Group")
            } footer: {
                Text("The default currency for new expenses. Existing expenses keep the currency they were entered in.")
            }

            coverImageSection

            defaultSplitSection

            Section {
                ForEach(state.members) { member in
                    Button {
                        renameText = member.displayName
                        renamingMember = member
                    } label: {
                        HStack(spacing: 10) {
                            MemberAvatar(member, size: 28)
                            Text(member.displayName).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .swipeActions {
                        // Omitted rather than shown disabled when we already
                        // know it'll be rejected (`CHECKLIST.md` UX audit
                        // [21]) — the section footer below states the rule,
                        // this is just not offering the one swipe action
                        // that would silently fail against it.
                        if isRemovable(member) {
                            Button("Remove", role: .destructive) { Task { await remove(member) } }
                        }
                        Button("Report") { reportingTarget = (.member(id: member.id), member.displayName) }
                            .tint(.orange)
                    }
                }
            } header: {
                Text("Members")
            } footer: {
                Text("A member can only be removed if they have no expenses or settlements and aren't signed in.")
            }

            Section {
                HStack {
                    TextField("Name", text: $newMemberName)
                        .submitLabel(.done)
                        .onSubmit { Task { await addMember() } }
                    Button("Add") { Task { await addMember() } }
                        .disabled(isAddingMember || trimmedNewMemberName.isEmpty)
                }
            } header: {
                Text("Add Someone")
            } footer: {
                Text("Adds them to the ledger by name alone — no app or account needed. They can sign in and claim this spot for themselves later.")
            }

            if myMember != nil {
                Section {
                    HStack {
                        TextField("name@bank", text: $myUpiVpa)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if isSavingUpiVpa {
                            ProgressView()
                        } else if isUpiVpaDirty {
                            Button("Save") { Task { await saveMyUpiVpa() } }
                        }
                    }
                } header: {
                    Text("My UPI ID")
                } footer: {
                    Text("Shown to others as a \"Pay via UPI\" shortcut when they settle up with you. Leave blank to remove it.")
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            if let reportConfirmation {
                Section { Text(reportConfirmation).foregroundStyle(.secondary) }
            }

            Section {
                Button("Report a Problem") { reportingTarget = (.group, state.group.name) }
            } footer: {
                Text("Report this group's name or content — Apple requires this for apps with shared user-generated content.")
            }

            // Regenerate/Archive/Leave used to be three plain Sections, the
            // same visual weight as "Add Someone" above — a routine rename
            // and an irreversible link rotation read identically
            // (`CHECKLIST.md` UX audit [20]). One red-tinted "Danger Zone"
            // groups them instead, each row carrying its own warning icon
            // and consequence line.
            Section {
                dangerZoneRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Regenerate Link",
                    caption: "Makes a fresh invite link and code; the old ones stop working immediately, for anyone still holding them. Not undoable.",
                    isLoading: isRegenerating,
                    action: { confirmingRegenerate = true }
                )
                dangerZoneRow(
                    icon: "archivebox",
                    title: state.group.archivedAt == nil ? "Archive Group" : "Unarchive Group",
                    caption: state.group.archivedAt == nil
                        ? "Hides the group from everyone's list once the trip's over. Nothing is deleted, and any member can bring it back."
                        : "This group is archived. Unarchive it to move it back into everyone's list.",
                    isLoading: isArchiving,
                    action: { Task { await setArchived(state.group.archivedAt == nil) } }
                )
                dangerZoneRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Leave This Group",
                    caption: "Removes this group from this device. Your expenses stay for everyone else.",
                    isLoading: false,
                    action: { confirmingLeave = true }
                )
            } header: {
                Text("Danger Zone").foregroundStyle(.red)
            }
        }
        .materialSheetContent()
        .navigationTitle("Group Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isBusy || !isDirty || trimmedName.isEmpty)
            }
        }
        .dismissibleKeyboard()
        .alert(
            "Rename Member",
            isPresented: Binding(get: { renamingMember != nil }, set: { if !$0 { renamingMember = nil } }),
            presenting: renamingMember
        ) { member in
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await rename(member) } }
        }
        .confirmationDialog("Leave this group?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive, action: onLeave)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It'll be removed from this device. Your expenses stay for everyone else.")
        }
        .confirmationDialog("Regenerate the invite link?", isPresented: $confirmingRegenerate, titleVisibility: .visible) {
            Button("Regenerate", role: .destructive) { Task { await regenerateLink() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The old link and join code stop working immediately, for anyone still holding them. Not undoable.")
        }
        .onChange(of: pickedCover) { _, item in
            guard let item else { return }
            Task { await handlePickedCover(item) }
        }
        .sheet(isPresented: Binding(get: { reportingTarget != nil }, set: { if !$0 { reportingTarget = nil } })) {
            if let reportingTarget {
                ReportContentView(
                    groupId: groupId,
                    target: reportingTarget.target,
                    targetLabel: reportingTarget.label,
                    client: client,
                    accessToken: accessToken,
                    onSubmitted: {
                        self.reportingTarget = nil
                        reportConfirmation = "Thanks — we'll take a look."
                    },
                    onCancel: { self.reportingTarget = nil }
                )
            }
        }
    }

    /// A "None" chip plus a horizontally-scrolling row of preset emoji; the
    /// current pick is filled with the accent colour. Tapping the current
    /// pick again is the same as choosing "None".
    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emoji").foregroundStyle(.primary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    emojiChip(nil, isSelected: emoji.isEmpty) { Image(systemName: "slash.circle").font(.body) }
                    ForEach(Self.emojiOptions, id: \.self) { option in
                        emojiChip(option, isSelected: emoji == option) { Text(option).font(.title3) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Cover image (CHECKLIST.md "Group cover image")

    private var coverKey: String { "groups/\(groupId)/cover" }

    @ViewBuilder
    private var coverImageSection: some View {
        Section {
            HStack(spacing: 12) {
                Group {
                    if state.group.coverKey != nil {
                        GroupCoverImage(groupId: groupId, coverKey: coverKey, accessToken: accessToken)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Surface.well)
                            .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                    }
                }
                .frame(width: 72, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                PhotosPicker(
                    selection: $pickedCover,
                    matching: .images,
                    preferredItemEncoding: .compatible,
                    photoLibrary: .shared()
                ) {
                    Text(state.group.coverKey == nil ? "Add Cover Image" : "Change Cover")
                }
                .disabled(isSavingCover)

                Spacer()
                if isSavingCover { ProgressView() }
            }

            if state.group.coverKey != nil {
                Button("Remove Cover", role: .destructive) {
                    Task { await removeCover() }
                }
                .disabled(isSavingCover)
            }
        } header: {
            Text("Cover Image")
        } footer: {
            Text("Shown on the group's card and at the top of the group. Any member can change it.")
        }
    }

    private func handlePickedCover(_ item: PhotosPickerItem) async {
        errorMessage = nil
        defer { pickedCover = nil }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let picked = UIImage(data: data),
            let jpeg = CoverImage.jpegData(from: picked),
            let compressed = UIImage(data: jpeg)
        else {
            errorMessage = "Couldn't read that photo. Try another."
            return
        }

        isSavingCover = true
        defer { isSavingCover = false }
        do {
            guard let sessionToken else {
                errorMessage = "Sign in to set a cover image."
                return
            }
            let ticket = try await client.presignMediaUpload(
                .groupCover, contentType: "image/jpeg", contentLength: jpeg.count,
                groupId: groupId, token: sessionToken, accessToken: accessToken
            )
            try await client.uploadImage(jpeg, using: ticket)
            _ = try await client.updateGroup(groupId: groupId, coverImage: .commit, accessToken: accessToken)
            avatarLoader?.prime(coverKey, with: compressed) // show it instantly everywhere
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func removeCover() async {
        errorMessage = nil
        isSavingCover = true
        defer { isSavingCover = false }
        do {
            _ = try await client.updateGroup(groupId: groupId, coverImage: .remove, accessToken: accessToken)
            avatarLoader?.invalidate(coverKey)
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    // MARK: - Default split (FEATURE_BACKLOG.md "Default split config per group")

    @ViewBuilder
    private var defaultSplitSection: some View {
        Section {
            if editingDefaultSplit {
                ForEach(state.members) { member in
                    HStack {
                        Text(member.displayName)
                        Spacer()
                        TextField("0", text: draftPercentBinding(for: member.id))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 44)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
                Text(draftPercentTotal == 100 ? "Adds up to 100%." : "\(draftPercentTotal)% assigned")
                    .font(.caption)
                    .foregroundStyle(draftPercentTotal == 100 ? Color.secondary : Color.red)
                HStack {
                    Button("Split Equally", role: .destructive) { Task { await saveDefaultSplit(nil) } }
                    Spacer()
                    Button("Save") { Task { await saveDefaultSplit(draftDefaultSplit) } }
                        .disabled(draftDefaultSplit == nil || isSavingDefaultSplit)
                }
            } else {
                HStack {
                    Text("Default Split")
                    Spacer()
                    Text(currentDefaultSplitLabel).foregroundStyle(.secondary)
                }
                Button("Change") { startEditingDefaultSplit() }
            }
        } header: {
            Text("Default Split")
        } footer: {
            Text("New expenses open with this split. You can still change it on any expense.")
        }
    }

    /// One row of the "Danger Zone" section (`CHECKLIST.md` UX audit [20]) —
    /// a leading warning icon plus a title/consequence pair, replacing what
    /// used to be three separate `Section`s each with their own footer.
    private func dangerZoneRow(icon: String, title: String, caption: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.red)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(title).foregroundStyle(.red)
                    }
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isLoading)
    }

    private var currentDefaultSplitLabel: String {
        guard let split = state.group.defaultSplit else { return "Split equally" }
        let name: (String) -> String = { id in
            state.members.first { $0.id == id }?.displayName ?? "?"
        }
        return split.weights.map { "\(name($0.memberId)) \($0.weight)%" }.joined(separator: " · ")
    }

    private func draftPercentBinding(for memberId: String) -> Binding<String> {
        Binding(get: { draftPercent[memberId] ?? "" }, set: { draftPercent[memberId] = $0 })
    }

    private func draftPercent(for memberId: String) -> Int {
        Int(draftPercent[memberId]?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
    }

    private var draftPercentTotal: Int {
        state.members.reduce(0) { $0 + draftPercent(for: $1.id) }
    }

    /// The editor's current weights as a valid `DefaultSplit`, or `nil` if it
    /// doesn't add up / has no positive weight.
    private var draftDefaultSplit: DefaultSplit? {
        let weights = state.members
            .map { DefaultSplitWeight(memberId: $0.id, weight: draftPercent(for: $0.id)) }
            .filter { $0.weight > 0 }
        let split = DefaultSplit(weights: weights)
        return split.isValid ? split : nil
    }

    private func startEditingDefaultSplit() {
        var draft: [String: String] = [:]
        if let current = state.group.defaultSplit {
            for w in current.weights { draft[w.memberId] = String(w.weight) }
        } else {
            // Seed from an equal split so the user starts from something sane.
            let base = 100 / max(1, state.members.count)
            for member in state.members { draft[member.id] = String(base) }
        }
        draftPercent = draft
        editingDefaultSplit = true
    }

    /// `nil` → "split equally" (clears the config).
    private func saveDefaultSplit(_ split: DefaultSplit?) async {
        errorMessage = nil
        isSavingDefaultSplit = true
        defer { isSavingDefaultSplit = false }
        do {
            _ = try await client.updateGroup(
                groupId: groupId,
                defaultSplit: split.map { .set($0) } ?? .cleared,
                accessToken: accessToken
            )
            editingDefaultSplit = false
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func emojiChip<Label: View>(_ value: String?, isSelected: Bool, @ViewBuilder label: () -> Label) -> some View {
        Button {
            emoji = value ?? ""
        } label: {
            label()
                .frame(width: 40, height: 40)
                .background(isSelected ? Color.accentColor.opacity(0.22) : Surface.well, in: Circle())
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.map { "Emoji \($0)" } ?? "No emoji")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            _ = try await client.updateGroup(
                groupId: groupId,
                name: trimmedName != state.group.name ? trimmedName : nil,
                currency: currency != state.group.currency ? currency : nil,
                emoji: emojiUpdate,
                accessToken: accessToken
            )
            onChanged()
            onDone()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// `.unchanged` / `.set` / `.cleared` for the emoji, from the picker's
    /// state versus what the group currently has.
    private var emojiUpdate: FieldUpdate<String> {
        guard emoji != (state.group.emoji ?? "") else { return .unchanged }
        return emoji.isEmpty ? .cleared : .set(emoji)
    }

    private func rename(_ member: Member) async {
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        renamingMember = nil
        guard !newName.isEmpty, newName != member.displayName else { return }
        errorMessage = nil
        do {
            _ = try await client.renameMember(groupId: groupId, memberId: member.id, displayName: newName, accessToken: accessToken)
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// Add a placeholder member by name alone (`MANDATORY_LOGIN_PLAN.md`
    /// Part 2.5) — the same `POST .../members` endpoint the join-by-link flow
    /// already uses, just triggered by an existing member instead of the
    /// person themselves. No identity attached; they can claim this spot
    /// later via the existing claim flow (`ACCOUNTS_DESIGN.md` §6).
    private func addMember() async {
        let trimmed = trimmedNewMemberName
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        isAddingMember = true
        defer { isAddingMember = false }
        do {
            _ = try await client.joinGroup(groupId: groupId, JoinGroupRequest(displayName: trimmed), accessToken: accessToken)
            newMemberName = ""
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func isRemovable(_ member: Member) -> Bool {
        Self.isRemovable(member, myMemberId: myMemberId, expenses: state.expenses, settlements: state.settlements)
    }

    /// Whether the section footer's rule ("no expenses or settlements,
    /// isn't signed in") is already known to be violated, checked against
    /// state already in hand rather than waiting for the server to say so
    /// (`CHECKLIST.md` UX audit [21]). `static` + free of `self` so it's
    /// testable without standing up the view. A member claimed by a
    /// *different* identity can't be detected this way — `Member` never
    /// exposes that, deliberately (`DESIGN.md` §8) — so that residual case
    /// still gets rejected server-side; `remove(_:)` already surfaces its
    /// specific reason via `friendlyMessage`, not a generic fallback.
    static func isRemovable(_ member: Member, myMemberId: String?, expenses: [Expense], settlements: [Settlement]) -> Bool {
        guard member.id != myMemberId else { return false }
        let onAnExpense = expenses.contains { expense in
            expense.payers.contains { $0.memberId == member.id } || expense.splits.contains { $0.memberId == member.id }
        }
        let onASettlement = settlements.contains { $0.fromId == member.id || $0.toId == member.id }
        return !onAnExpense && !onASettlement
    }

    private func remove(_ member: Member) async {
        errorMessage = nil
        do {
            try await client.removeMember(groupId: groupId, memberId: member.id, accessToken: accessToken)
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// Set or clear the signed-in member's own UPI VPA
    /// (`FEATURE_BACKLOG.md` "UPI deep link on Settle Up"). An empty field
    /// clears it (`FieldUpdate.cleared`); worker rejects an actual empty
    /// string, so blank-vs-clear is disambiguated here, not on the wire.
    private func saveMyUpiVpa() async {
        guard let myMemberId else { return }
        errorMessage = nil
        isSavingUpiVpa = true
        defer { isSavingUpiVpa = false }
        let update: FieldUpdate<String> = trimmedMyUpiVpa.isEmpty ? .cleared : .set(trimmedMyUpiVpa)
        do {
            _ = try await client.renameMember(groupId: groupId, memberId: myMemberId, upiVpa: update, accessToken: accessToken)
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// Archive / unarchive the group (`CHECKLIST.md` "Archive a group") — a
    /// group-wide, reversible "hide it, the trip's done" flag.
    private func setArchived(_ archived: Bool) async {
        errorMessage = nil
        isArchiving = true
        defer { isArchiving = false }
        do {
            _ = try await client.updateGroup(groupId: groupId, archived: archived, accessToken: accessToken)
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// Rotate the group's access token (`ACCESS_TOKEN_PLAN.md` Part 1) —
    /// every previously shared link/code stops working immediately.
    private func regenerateLink() async {
        errorMessage = nil
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            let response = try await client.regenerateLink(groupId: groupId, accessToken: accessToken)
            onRegenerated(response.accessToken)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}
