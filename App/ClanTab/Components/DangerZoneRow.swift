import SwiftUI

/// One row of a red-tinted "Danger Zone" section — an icon, a red title, and
/// a line of consequence underneath, all tappable together. Introduced for
/// Group Settings' Regenerate/Archive/Leave trio (`CHECKLIST.md` UX audit
/// [20]: a routine rename and an irreversible link rotation used to read as
/// identically weighted plain rows) and reused by `SettingsView`'s "Delete
/// Account" (UX audit fresh-eyes-pass [3]: the single most irreversible
/// action in the app used to be red text one row below "Sign Out" with no
/// separating header — the least emphasis of any destructive action in the
/// app, not the most).
struct DangerZoneRow: View {
    let icon: String
    let title: String
    let caption: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
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
}
