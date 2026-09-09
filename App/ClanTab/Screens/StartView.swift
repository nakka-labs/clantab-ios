import ClanTabKit
import SwiftUI

/// The very first screen for a device with no active group: open one of the
/// groups this identity knows, create a new group, or join by code. Sign-in
/// (Apple or Google) is mandatory before any of that — no guest tier
/// (`MANDATORY_LOGIN_PLAN.md` Part 3).
struct StartView: View {
    let onCreate: () -> Void
    let onJoinWithCode: () -> Void
    var groups: [KnownGroup] = []
    var onOpenGroup: (_ groupId: String) -> Void = { _ in }
    var onRemoveGroup: (_ groupId: String) -> Void = { _ in }
    var isSignedIn: Bool = false
    var isSigningIn: Bool = false
    /// Error from exchanging the credential (network / verification), owned by
    /// `AuthViewModel`. The credential-sheet's own failures are handled locally.
    var authError: String? = nil
    var onSignIn: (_ identityToken: String, _ userID: String, _ authorizationCode: String?) -> Void = { _, _, _ in }
    var onSignInWithGoogle: (_ identityToken: String) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    @State private var sheetError: String?

    var body: some View {
        // Content flows from the top and scrolls only if it actually
        // overflows (a long groups list, or large Dynamic Type) — no more
        // centering everything in the middle of a stack with dead space
        // above and below (`CHECKLIST.md` "Root screen layout"). Signed in,
        // the branding is the nav-bar large title and the create/join
        // actions dock to the bottom.
        Group {
            if isSignedIn {
                if groups.isEmpty {
                    // A "get started" screen — centered, no big title, so it
                    // doesn't read as an empty list.
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else {
                    ScrollView {
                        GroupsListView(groups: groups, onOpenGroup: onOpenGroup, onRemoveGroup: onRemoveGroup)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .navigationTitle("ClanTab")
                }
            } else {
                // A welcome screen with a clear focal split: the logo +
                // wordmark own the upper-centre of the screen, and the
                // sign-in controls dock to the bottom safe area (below) —
                // deliberately separated, not one centred clump.
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    hero
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSignedIn {
                VStack(spacing: 10) {
                    Button(action: onCreate) {
                        Text("Create a Group").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .primaryButtonShadow()
                    Button(action: onJoinWithCode) {
                        Text("Join with a Code").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .background(.bar)
            } else {
                signInSection
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            }
        }
        .toolbar {
            if isSignedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        // Before sign-in there's no title or toolbar — drop the empty nav bar
        // so the welcome hero centres against the full screen.
        .toolbar(isSignedIn ? .automatic : .hidden, for: .navigationBar)
    }

    /// The "welcome" hero, shown only before sign-in — once you're in, the
    /// nav-bar large title carries the wordmark and the groups list gets the
    /// space.
    private var hero: some View {
        VStack(spacing: 20) {
            Image("LaunchLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.tint)
            VStack(spacing: 10) {
                Text("ClanTab")
                    .font(.display(weight: .bold))
                Text("Split expenses with friends. No ads.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Signed in, but no groups on this device yet — say what the two buttons
    /// below are for instead of leaving a blank gap.
    private var emptyState: some View {
        VStack(spacing: 10) {
            // ClanTab's custom empty-state glyph (`DESIGN_BIBLE.md` §4),
            // shared with every other genuine zero-state.
            Image("EmptyStateGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.secondary)
            Text("No groups yet")
                .font(.title2.bold())
            Text("Start one for a trip or a shared house — or join one with a code someone sent you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var signInSection: some View {
        VStack(spacing: 12) {
            Text("Sign in to create or join a group.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 2)

            AppleSignInButton(
                onCredential: { token, userID, authCode in
                    sheetError = nil
                    onSignIn(token, userID, authCode)
                },
                onFailure: { sheetError = $0 }
            )
            .frame(height: 48)
            .disabled(isSigningIn)
            .opacity(isSigningIn ? 0.5 : 1)

            GoogleSignInButton(
                onCredential: { token in
                    sheetError = nil
                    onSignInWithGoogle(token)
                },
                onFailure: { sheetError = $0 }
            )
            .frame(height: 48)
            .disabled(isSigningIn)
            .opacity(isSigningIn ? 0.5 : 1)

            if let message = authError ?? sheetError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
