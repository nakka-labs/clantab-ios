import Foundation

/// The app's 4 top-level tabs (`CHECKLIST.md` UX audit [6]) — replaces the old
/// single-stack nav where Friends/Settings were separate full-screen routes
/// and Insights was buried one row deep inside every group.
enum MainTab: Hashable {
    case home
    case friends
    case insights
    case settings
}
