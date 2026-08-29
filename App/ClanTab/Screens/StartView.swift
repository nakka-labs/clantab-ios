import SwiftUI

/// The very first screen for a device with no remembered group: choose to
/// create a new group or join an existing one by code.
struct StartView: View {
    let onCreate: () -> Void
    let onJoinWithCode: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text("ClanTab")
                    .font(.largeTitle.bold())
                Text("Split expenses with friends. No accounts, no ads.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                Button("Create a Group", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Join with a Code", action: onJoinWithCode)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}
