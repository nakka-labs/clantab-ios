import ClanTabKit
import SwiftUI

/// The one-page spending report (`FEATURE_BACKLOG.md` "PDF export"). Laid out
/// at A4 point size and rasterised to a PDF by `GroupReportPDF` — never shown
/// in the app's own navigation. Deliberately a plain document look (white,
/// system fonts), not the brand-gradient recap card: this is a thing people
/// file or forward, not a hero moment.
struct GroupReportView: View {
    let model: GroupReportModel

    /// A4 in points (72 dpi) — the page the PDF context is sized to.
    static let pageSize = CGSize(width: 595, height: 842)

    private static let dateStyle: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
    private let accent = Color(red: 0.0, green: 0.45, blue: 0.79) // the app's #0074CA

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            statsRow
            if !model.settleUp.isEmpty || model.expenseCount > 0 { settleUpSection }
            if !model.byMember.isEmpty { breakdown(title: "Where it went — by member", rows: memberRows) }
            if !model.byCategory.isEmpty { breakdown(title: "By category", rows: categoryRows) }
            Spacer(minLength: 0)
            footer
        }
        .padding(44)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let emoji = model.emoji, !emoji.isEmpty { Text(emoji).font(.system(size: 26)) }
                Text(model.groupName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
            }
            Text("Spending report · generated \(model.generatedAt.formatted(Self.dateStyle))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let first = model.firstExpenseDate, let last = model.lastExpenseDate {
                Text("Expenses from \(first.formatted(Self.dateStyle)) to \(last.formatted(Self.dateStyle))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat("Total spent", MoneyFormat.string(minorUnits: model.totalSpentMinor, currency: model.currency))
            Divider().frame(height: 40)
            stat(model.expenseCount == 1 ? "Expense" : "Expenses", "\(model.expenseCount)")
            Divider().frame(height: 40)
            stat(model.memberCount == 1 ? "Member" : "Members", "\(model.memberCount)")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.04)))
        .overlay(alignment: .bottom) {
            if !model.otherCurrencies.isEmpty {
                Text("Breakdowns show \(model.currency) only — also has expenses in \(model.otherCurrencies.joined(separator: ", ")).")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .offset(y: 16)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(.black)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var settleUpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Settle up")
            if model.settleUp.isEmpty {
                Text("All settled up — nobody owes anybody.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.settleUp) { line in
                    HStack(spacing: 6) {
                        Text(line.from).fontWeight(.medium)
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(line.to).fontWeight(.medium)
                        Spacer()
                        Text(line.amount).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.black)
                }
            }
        }
    }

    private var memberRows: [BreakdownRow] {
        let max = model.byMember.map(\.totalMinor).max() ?? 1
        return model.byMember.map {
            BreakdownRow(
                label: $0.member.displayName,
                amount: MoneyFormat.string(minorUnits: $0.totalMinor, currency: model.currency),
                fraction: max > 0 ? Double($0.totalMinor) / Double(max) : 0,
                color: MemberColor.color(for: $0.member.displayName)
            )
        }
    }

    private var categoryRows: [BreakdownRow] {
        let max = model.byCategory.map(\.totalMinor).max() ?? 1
        return model.byCategory.map {
            BreakdownRow(
                label: $0.category.name,
                amount: MoneyFormat.string(minorUnits: $0.totalMinor, currency: model.currency),
                fraction: max > 0 ? Double($0.totalMinor) / Double(max) : 0,
                color: accent
            )
        }
    }

    private struct BreakdownRow: Identifiable {
        let label: String
        let amount: String
        let fraction: Double
        let color: Color
        var id: String { label }
    }

    private func breakdown(title: String, rows: [BreakdownRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.label).font(.system(size: 12)).foregroundStyle(.black).lineLimit(1)
                        Spacer()
                        Text(row.amount)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.black)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.07))
                            Capsule().fill(row.color).frame(width: Swift.max(2, geo.size.width * row.fraction))
                        }
                    }
                    .frame(height: 7)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(accent)
            .tracking(0.5)
    }

    private var footer: some View {
        HStack {
            Text("Made with ClanTab")
            Spacer()
            Text(model.generatedAt.formatted(.dateTime.day().month().year().hour().minute()))
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
}
