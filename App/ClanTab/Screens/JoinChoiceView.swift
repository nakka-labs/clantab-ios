import SwiftUI

/// Shown when a signed-in user opens an invite link for a group they hold no
/// membership in (`ACCOUNTS_DESIGN.md` §6). Two distinct choices: claim an
/// existing placeholder member as themselves, or join fresh as a guest.
struct JoinChoiceView: View {
    let onThisIsMe: () -> Void
    let onJoinAsGuest: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "person.2.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Join this group")
                    .font(.title2.bold())
                Text("Are you already one of the members, or joining for the first time?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onThisIsMe) {
                    VStack(spacing: 2) {
                        Text("This is me").fontWeight(.semibold)
                        Text("Link an existing member to your Apple ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onJoinAsGuest) {
                    VStack(spacing: 2) {
                        Text("Join as a guest").fontWeight(.semibold)
                        Text("Add yourself as a new member")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
        .navigationTitle("Invitation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}
