import SwiftUI

// MARK: - InsightsView

struct InsightsView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: InsightsTab = .monthly

    enum InsightsTab: String, CaseIterable {
        case monthly = "Monthly"
        case yearly  = "Yearly"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Picker("", selection: $selectedTab) {
                            ForEach(InsightsTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                        if selectedTab == .monthly {
                            monthlyContent
                        } else {
                            yearlyContent
                        }
                    }
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Monthly Content

    private var monthlyContent: some View {
        let insights   = vm.monthlyInsights(count: 6)
        let current    = insights.last ?? vm.currentMonthInsight
        let previous   = insights.dropLast().last

        return VStack(spacing: 16) {
            // ── Summary card ──────────────────────────────────────
            monthlySummaryCard(current: current, previous: previous)

            // ── Trend chart ───────────────────────────────────────
            if insights.contains(where: { $0.totalSpent > 0 }) {
                trendChartCard(insights: insights)
            }

            // ── Category breakdown ────────────────────────────────
            categoryBreakdownCard(insight: current)

            Spacer().frame(height: 32)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Monthly Summary Card

    private func monthlySummaryCard(
        current:  ExpenseViewModel.MonthlyInsight,
        previous: ExpenseViewModel.MonthlyInsight?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(current.fullLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VeloceTheme.textSecondary)
                .tracking(0.3)

            // Big spent number
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(current.totalSpent.toCurrencyString())
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .contentTransition(.numericText())
                Text("spent")
                    .font(.system(size: 14))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .offset(y: -2)
            }

            // Stats row
            HStack(spacing: 0) {
                statPill(
                    label: "Saved",
                    value: current.totalSaved.toCompactCurrency(),
                    color: VeloceTheme.ok,
                    icon:  "leaf.fill"
                )

                Spacer()

                if current.income > 0 {
                    statPill(
                        label: "Rate",
                        value: String(format: "%.0f%%", current.savingRate),
                        color: current.savingRate >= 20 ? VeloceTheme.ok : VeloceTheme.caution,
                        icon:  "percent"
                    )
                    Spacer()
                }

                if let prev = previous, prev.totalSpent > 0 {
                    let delta = current.totalSpent - prev.totalSpent
                    let pct   = prev.totalSpent > 0 ? abs(delta) / prev.totalSpent * 100 : 0
                    statPill(
                        label: "vs Last Month",
                        value: "\(delta >= 0 ? "+" : "-")\(String(format: "%.0f", pct))%",
                        color: delta <= 0 ? VeloceTheme.ok : VeloceTheme.over,
                        icon:  delta <= 0 ? "arrow.down" : "arrow.up"
                    )
                }
            }

            // Month-over-month comparison blurb
            if let prev = previous, prev.income > 0, current.income > 0 {
                let savedDelta = current.totalSaved - prev.totalSaved
                let pct        = prev.totalSaved > 0
                    ? abs(savedDelta) / prev.totalSaved * 100
                    : 0
                let positive = savedDelta >= 0

                HStack(spacing: 8) {
                    Image(systemName: positive ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(positive ? VeloceTheme.ok : VeloceTheme.over)
                    Text(
                        positive
                        ? "You saved \(String(format: "%.0f", pct))% more than last month"
                        : "You saved \(String(format: "%.0f", pct))% less than last month"
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VeloceTheme.textSecondary)
                }
                .padding(10)
                .background(
                    (positive ? VeloceTheme.ok : VeloceTheme.over).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
        }
        .veloceCard(radius: 18, padding: 18)
    }

    private func statPill(label: String, value: String, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(VeloceTheme.textTertiary)
        }
    }

    // MARK: - Trend Chart Card

    private func trendChartCard(insights: [ExpenseViewModel.MonthlyInsight]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("6-Month Trend")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VeloceTheme.textPrimary)

            let maxSpent = insights.map(\.totalSpent).max() ?? 1

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(insights.enumerated()), id: \.offset) { idx, insight in
                    let isLast = idx == insights.count - 1
                    let ratio  = maxSpent > 0 ? CGFloat(insight.totalSpent / maxSpent) : 0

                    VStack(spacing: 4) {
                        // Bar
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isLast ? VeloceTheme.accent : VeloceTheme.accent.opacity(0.35))
                                    .frame(height: max(4, geo.size.height * ratio))
                            }
                        }
                        .frame(height: 80)

                        Text(insight.shortLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isLast ? VeloceTheme.textPrimary : VeloceTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.5, dampingFraction: 0.78), value: ratio)
                }
            }

            // Legend
            HStack(spacing: 14) {
                legendDot(color: VeloceTheme.accent, label: "Current month")
                legendDot(color: VeloceTheme.accent.opacity(0.35), label: "Previous months")
            }
        }
        .veloceCard(radius: 18, padding: 18)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(VeloceTheme.textTertiary)
        }
    }

    // MARK: - Category Breakdown Card

    private func categoryBreakdownCard(insight: ExpenseViewModel.MonthlyInsight) -> some View {
        let pairs: [(Category, Double)] = vm.categories
            .compactMap { cat -> (Category, Double)? in
                guard let amt = insight.byCategory[cat.id], amt > 0 else { return nil }
                return (cat, amt)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0 }

        return VStack(alignment: .leading, spacing: 14) {
            Text("Top Categories")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VeloceTheme.textPrimary)

            if pairs.isEmpty {
                Text("No expenses recorded this month.")
                    .font(.system(size: 13))
                    .foregroundStyle(VeloceTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                let maxAmt = pairs.first?.1 ?? 1
                VStack(spacing: 10) {
                    ForEach(pairs, id: \.0.id) { cat, amount in
                        categoryRow(cat: cat, amount: amount, maxAmount: maxAmt, total: insight.totalSpent)
                    }
                }
            }
        }
        .veloceCard(radius: 18, padding: 18)
    }

    private func categoryRow(cat: Category, amount: Double, maxAmount: Double, total: Double) -> some View {
        let color = Color(hex: cat.colorHex)
        let pct   = total > 0 ? amount / total * 100 : 0
        let ratio = maxAmount > 0 ? CGFloat(amount / maxAmount) : 0

        return VStack(spacing: 5) {
            HStack {
                Image(systemName: cat.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(cat.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Spacer()
                Text(amount.toCompactCurrency())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 11))
                    .foregroundStyle(VeloceTheme.textTertiary)
                    .frame(width: 32, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.12)).frame(height: 5)
                    Capsule().fill(color).frame(width: geo.size.width * ratio, height: 5)
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Yearly Content

    private var yearlyContent: some View {
        let insight = vm.yearlyInsight

        return VStack(spacing: 16) {
            yearlyOverviewCard(insight: insight)
            if insight.bestMonth != nil || insight.worstMonth != nil {
                yearlyHighlightsCard(insight: insight)
            }
            yearlyMonthGridCard(insight: insight)
            Spacer().frame(height: 32)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Yearly Overview Card

    private func yearlyOverviewCard(insight: ExpenseViewModel.YearlyInsight) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(String(insight.year)) Overview")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VeloceTheme.textSecondary)
                .tracking(0.3)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(insight.totalSpent.toCurrencyString())
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .contentTransition(.numericText())
                Text("spent YTD")
                    .font(.system(size: 14))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .offset(y: -2)
            }

            HStack(spacing: 0) {
                statPill(
                    label: "Saved",
                    value: insight.totalSaved.toCompactCurrency(),
                    color: VeloceTheme.ok,
                    icon:  "leaf.fill"
                )
                Spacer()
                statPill(
                    label: "Monthly Avg",
                    value: insight.monthlyAverage.toCompactCurrency(),
                    color: VeloceTheme.accent,
                    icon:  "chart.bar"
                )
                Spacer()
                let nonEmpty = insight.months.filter { $0.totalSpent > 0 }.count
                statPill(
                    label: "Active Months",
                    value: "\(nonEmpty)",
                    color: VeloceTheme.textSecondary,
                    icon:  "calendar"
                )
            }
        }
        .veloceCard(radius: 18, padding: 18)
    }

    // MARK: - Yearly Highlights Card

    private func yearlyHighlightsCard(insight: ExpenseViewModel.YearlyInsight) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlights")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VeloceTheme.textPrimary)

            if let best = insight.bestMonth {
                highlightRow(
                    icon:    "star.fill",
                    color:   VeloceTheme.ok,
                    title:   "Best saving month",
                    detail:  best.fullLabel,
                    value:   best.totalSaved.toCompactCurrency(),
                    subtext: String(format: "%.0f%% saved", best.savingRate)
                )
            }

            if let worst = insight.worstMonth {
                highlightRow(
                    icon:    "flame.fill",
                    color:   VeloceTheme.over,
                    title:   "Highest spending month",
                    detail:  worst.fullLabel,
                    value:   worst.totalSpent.toCompactCurrency(),
                    subtext: ""
                )
            }
        }
        .veloceCard(radius: 18, padding: 18)
    }

    private func highlightRow(icon: String, color: Color, title: String, detail: String, value: String, subtext: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(VeloceTheme.textTertiary)
                Text(detail)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                if !subtext.isEmpty {
                    Text(subtext)
                        .font(.system(size: 11))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }
        }
    }

    // MARK: - Yearly Month Grid Card

    private func yearlyMonthGridCard(insight: ExpenseViewModel.YearlyInsight) -> some View {
        let maxSpent = insight.months.map(\.totalSpent).max() ?? 1
        let cols     = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

        return VStack(alignment: .leading, spacing: 14) {
            Text("Month by Month")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VeloceTheme.textPrimary)

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(insight.months, id: \.monthStart) { m in
                    monthGridCell(month: m, maxSpent: maxSpent)
                }
            }
        }
        .veloceCard(radius: 18, padding: 18)
    }

    private func monthGridCell(month: ExpenseViewModel.MonthlyInsight, maxSpent: Double) -> some View {
        let ratio    = maxSpent > 0 ? CGFloat(month.totalSpent / maxSpent) : 0
        let isCurrent: Bool = {
            let cal = Calendar.current
            return cal.isDate(month.monthStart, equalTo: Date(), toGranularity: .month)
        }()

        return VStack(spacing: 6) {
            Text(month.shortLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isCurrent ? VeloceTheme.accent : VeloceTheme.textSecondary)

            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isCurrent ? VeloceTheme.accent : VeloceTheme.accent.opacity(0.28))
                        .frame(height: max(3, geo.size.height * ratio))
                }
            }
            .frame(height: 40)

            if month.totalSpent > 0 {
                Text(month.totalSpent.toCompactCurrency())
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(VeloceTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(.system(size: 9))
                    .foregroundStyle(VeloceTheme.divider)
            }
        }
        .padding(8)
        .background(
            isCurrent ? VeloceTheme.accent.opacity(0.06) : VeloceTheme.surfaceRaised,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            isCurrent
                ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(VeloceTheme.accent.opacity(0.25), lineWidth: 1)
                : nil
        )
    }
}

// MARK: - Preview

#Preview {
    InsightsView().environmentObject(ExpenseViewModel())
}
