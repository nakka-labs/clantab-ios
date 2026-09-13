import Foundation

/// The app's 3 top-level tabs (`CHECKLIST.md` UX audit [6]) — replaces the
/// old single-stack nav where Friends/Settings were separate full-screen
/// routes. A 4th tab, Insights, was removed 2026-09-13 (`CHECKLIST.md`
/// "Remove the Insights tab") — it duplicated Home's own balance summary
/// and had no demonstrated demand.
enum MainTab: Hashable {
    case home
    case friends
    case settings
}
