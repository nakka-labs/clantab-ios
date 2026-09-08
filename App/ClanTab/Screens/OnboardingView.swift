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
        let symbol: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(
            symbol: "person.3.fill",
            title: "A group for every split",
            body: "Start one for a trip, a shared house, or a night out, then add the people splitting the costs. They don't need an account."
        ),
        Page(
            symbol: "list.bullet.rectangle.fill",
            title: "Add expenses as they happen",
            body: "Log who paid and how to split it — equally, exact amounts, or percentages. ClanTab keeps the running tally."
        ),
        Page(
            symbol: "checkmark.seal.fill",
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
        VStack(spacing: 28) {
            Image(systemName: item.symbol)
                .font(.system(size: 68, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 148, height: 148)
                .background(Color.accentColor.opacity(0.12), in: Circle())
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
