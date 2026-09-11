import Testing
@testable import ClanTabKit

@Suite("WhatsNew")
struct WhatsNewTests {
    @Test("unseenReleases: nil lastSeenBuild returns nothing — the caller decides what a fresh install does")
    func testUnseenReleasesNilLastSeen() {
        #expect(WhatsNew.unseenReleases(sinceBuild: nil).isEmpty)
    }

    @Test("unseenReleases: only releases strictly newer than lastSeenBuild, oldest first")
    func testUnseenReleasesFiltersAndOrders() {
        let all = WhatsNew.releases
        let latest = all.map(\.build).max() ?? 0
        // Every real release is newer than a very old build.
        let unseen = WhatsNew.unseenReleases(sinceBuild: 0)
        #expect(unseen.map(\.build) == all.map(\.build).sorted())
        // Nothing is newer than the newest release itself.
        #expect(WhatsNew.unseenReleases(sinceBuild: latest).isEmpty)
    }

    @Test("shouldShow: false before onboarding is finished, even with unseen releases")
    func testShouldShowRequiresOnboarding() {
        #expect(!WhatsNew.shouldShow(lastSeenBuild: 0, currentBuild: 999, hasCompletedOnboarding: false))
    }

    @Test("shouldShow: false for a fresh install / pre-feature user (nil lastSeenBuild)")
    func testShouldShowFalseForNilLastSeen() {
        #expect(!WhatsNew.shouldShow(lastSeenBuild: nil, currentBuild: 999, hasCompletedOnboarding: true))
    }

    @Test("shouldShow: false once lastSeenBuild has caught up to currentBuild")
    func testShouldShowFalseWhenCaughtUp() {
        let currentBuild = WhatsNew.releases.map(\.build).max() ?? 0
        #expect(!WhatsNew.shouldShow(lastSeenBuild: currentBuild, currentBuild: currentBuild, hasCompletedOnboarding: true))
    }

    @Test("shouldShow: true once onboarding is done and a release landed since lastSeenBuild")
    func testShouldShowTrue() {
        let currentBuild = (WhatsNew.releases.map(\.build).max() ?? 0) + 1
        #expect(WhatsNew.shouldShow(lastSeenBuild: 0, currentBuild: currentBuild, hasCompletedOnboarding: true))
    }
}
