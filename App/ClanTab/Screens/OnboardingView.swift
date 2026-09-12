import SwiftUI

/// The first-run walkthrough (`CHECKLIST.md` "Onboarding walkthrough") — three
/// pages explaining the group → expense → settle-up loop, shown once before
/// the start screen. `onComplete` fires on "Get Started" or "Skip"; the caller
/// records the flag and dismisses.
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        /// An `Assets.xcassets` image name — a real cropped screenshot of the
        /// screen being described, not an SF Symbol standing in for it
        /// (`CHECKLIST.md` UX audit [4]). Each is a genuine "Goa Trip" sample
        /// group run through the actual app (same sample data as
        /// `PreviewGroupHomeView`'s pre-auth preview), captured in the
        /// Simulator and cropped to just the illustrative content — no
        /// status bar or tab bar.
        let imageName: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(
            imageName: "OnboardingGroupHome",
            title: "A group for every split",
            body: "Start one for a trip, a shared house, or a night out, then add the people splitting the costs. They don't need an account."
        ),
        Page(
            imageName: "OnboardingAddExpense",
            title: "Add expenses as they happen",
            body: "Log who paid and how to split it — equally, exact amounts, or percentages. ClanTab keeps the running tally."
        ),
        Page(
            imageName: "OnboardingSettleUp",
            title: "Settle up, sorted",
            body: "One tap shows exactly who owes whom, simplified to the fewest payments. Mark them paid and you're square."
        ),
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onComplete)
                    .font(.subheadline)
                    .opacity(isLastPage ? 0 : 1)
                    .disabled(isLastPage)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                    pageView(item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            VStack(spacing: 20) {
                pageDots
                Button {
                    if isLastPage {
                        onComplete()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text(isLastPage ? "Get Started" : "Continue")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .primaryButtonShadow()
            }
            .padding()
        }
        .background {
            Rectangle()
                .fill(Surface.canvas)
                .overlay(Color.accentColor.opacity(0.04))
                .ignoresSafeArea()
        }
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 20) {
            Image(item.imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                .padding(.horizontal, 40)
                .frame(maxHeight: 340)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(item.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(item.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { i in
                Circle()
                    .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(page + 1) of \(pages.count)")
    }
}
