import SwiftUI

// MARK: - InsightsView

struct InsightsView: View {
    @EnvironmentObject var vm:         ExpenseViewModel
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAllCards    = false
    @State private var showAI          = false
    @State private var aiPrompt:  String? = nil
    @State private var yearlyExpanded       = false
    @State private var selectedChartMonth: Int? = nil

    private var cards: [InsightCard] {
        InsightEngine.generate(
            expenses:      vm.expenses,
            categories:    vm.categories,
            monthlyIncome: vm.monthlyIncome,
            savingGoal:    vm.savingGoal
        )
    }

    private var visibleCards: [InsightCard] {
        showAllCards ? cards : Array(cards.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        monthlySummaryStrip
                        insightCardList
                        categoryTrendRow
                        yearlySection
                        Spacer().frame(height: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showAI) {
            AIAssistantView(autoSendPrompt: aiPrompt)
                .environmentObject(vm)
                .environmentObject(subManager)
        }
    }

    // MARK: - Monthly Summary Strip

    private var monthlySummaryStrip: some View {
        let insights = vm.monthlyInsights(count: 6)
        let current  = insights.last ?? vm.currentMonthInsight
        let previous = insights.dropLast().last

        return HStack(spacing: 0) {
            summaryPill(
                label: "Spent",
                value: current.totalSpent.toCompactCurrency(),
                color: VeloceTheme.textPrimary
            )

            stripDivider

            summaryPill(
                label: "Saved",
                value: current.totalSaved.toCompactCurrency(),
                color: VeloceTheme.ok
            )

            if current.income > 0 {
                stripDivider
                summaryPill(
                    label: "Save Rate",
                    value: String(format: "%.0f%%", current.savingRate),
                    color: current.savingRate >= 20 ? VeloceTheme.ok : VeloceTheme.caution
                )
            }

            if let prev = previous, prev.totalSpent > 0, current.totalSpent > 0 {
                let delta = current.totalSpent - prev.totalSpent
                let pct   = abs(delta) / prev.totalSpent * 100
                stripDivider
                summaryPill(
                    label: "vs Last Month",
                    value: "\(delta >= 0 ? "+" : "-")\(String(format: "%.0f", pct))%",
                    color: delta <= 0 ? VeloceTheme.ok : VeloceTheme.over
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(VeloceTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    private func summaryPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(VeloceTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(VeloceTheme.divider)
            .frame(width: 1, height: 30)
    }

    // MARK: - Insight Card List

    private var insightCardList: some View {
        VStack(spacing: 12) {
            if cards.isEmpty {
                emptyState
            } else {
                ForEach(visibleCards) { card in
                    InsightCardView(card: card) {
                        aiPrompt = card.aiPrompt
                        showAI   = true
                    }
                }

                if cards.count > 5 && !showAllCards {
                    Button(action: { withAnimation(.spring(response: 0.35)) { showAllCards = true } }) {
                        HStack(spacing: 6) {
                            Text("Show \(cards.count - 5) more insights")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(VeloceTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(VeloceTheme.accentBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(VeloceTheme.accent.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(VeloceTheme.textTertiary)
            Text("No insights yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VeloceTheme.textPrimary)
            Text("Add a few more expenses and insights will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(VeloceTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .veloceCard()
    }

    // MARK: - Category Trend Pills

    private var categoryTrendRow: some View {
        let monthly  = InsightEngine.buildMonthly(from: vm.expenses, count: 3)
        let current  = monthly.last
        let previous = monthly.dropLast().last
        guard let cur = current, let prev = previous else { return AnyView(EmptyView()) }

        let trends: [(Category, Double, Double)] = vm.visibleCategories.compactMap { cat in
            let c = cur.byCategory[cat.id]  ?? 0
            let p = prev.byCategory[cat.id] ?? 0
            guard c > 0 || p > 0 else { return nil }
            let pct = p > 0 ? (c - p) / p * 100 : 0
            return (cat, c, pct)
        }.sorted { abs($0.2) > abs($1.2) }

        guard !trends.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("Category Trends")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(trends, id: \.0.id) { cat, amount, pct in
                            categoryTrendPill(cat: cat, amount: amount, pct: pct)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        )
    }

    private func categoryTrendPill(cat: Category, amount: Double, pct: Double) -> some View {
        let color   = Color(hex: cat.colorHex)
        let isUp    = pct > 0
        let isFlat  = abs(pct) < 2

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
                Text(cat.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .lineLimit(1)
            }
            Text(amount.toCompactCurrency())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(VeloceTheme.textPrimary)

            HStack(spacing: 3) {
                Image(systemName: isFlat ? "minus" : (isUp ? "arrow.up" : "arrow.down"))
                    .font(.system(size: 8, weight: .bold))
                Text(isFlat ? "Stable" : "\(String(format: "%.0f%%", abs(pct)))")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isFlat ? VeloceTheme.textTertiary : (isUp ? VeloceTheme.over : VeloceTheme.ok))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Yearly Section (collapsible)

    private var yearlySection: some View {
        let insight = vm.yearlyInsight

        return VStack(spacing: 10) {
            Button(action: { withAnimation(.spring(response: 0.35)) { yearlyExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VeloceTheme.accent)
                    Text("\(String(insight.year)) Year Overview")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textPrimary)
                    Spacer()
                    Image(systemName: yearlyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(VeloceTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            if yearlyExpanded {
                yearlyDetailContent(insight: insight)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func yearlyDetailContent(insight: ExpenseViewModel.YearlyInsight) -> some View {
        VStack(spacing: 12) {
            // Stats row
            HStack(spacing: 0) {
                yearlyStat("Total Spent", insight.totalSpent.toCompactCurrency(), VeloceTheme.textPrimary)
                Divider().frame(height: 34)
                yearlyStat("Total Saved", insight.totalSaved.toCompactCurrency(), VeloceTheme.ok)
                Divider().frame(height: 34)
                yearlyStat("Monthly Avg", insight.monthlyAverage.toCompactCurrency(), VeloceTheme.accent)
            }
            .veloceCard(radius: 14, padding: 14)

            // Best / Worst month
            let nonEmpty = insight.months.filter { $0.totalSpent > 0 }
            if !nonEmpty.isEmpty {
                HStack(spacing: 10) {
                    if let best = insight.bestMonth {
                        yearlyHighlight(
                            icon: "star.fill", color: VeloceTheme.ok,
                            label: "Best saving", month: best.shortLabel,
                            value: best.totalSaved.toCompactCurrency()
                        )
                    }
                    if let worst = insight.worstMonth {
                        yearlyHighlight(
                            icon: "flame.fill", color: VeloceTheme.over,
                            label: "Highest spend", month: worst.shortLabel,
                            value: worst.totalSpent.toCompactCurrency()
                        )
                    }
                }
            }

            // Month mini bar chart
            yearlyBarChart(months: insight.months)
        }
    }

    private func yearlyStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(VeloceTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func yearlyHighlight(icon: String, color: Color, label: String, month: String, value: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(VeloceTheme.textTertiary)
                Text(month)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    private func yearlyBarChart(months: [ExpenseViewModel.MonthlyInsight]) -> some View {
        YearlyBarChartView(months: months, selectedIndex: $selectedChartMonth)
            .veloceCard(radius: 14, padding: 14)
    }
}

// MARK: - Yearly Bar Chart View

private struct YearlyBarChartView: View {

    typealias MI = ExpenseViewModel.MonthlyInsight

    let months:         [MI]
    @Binding var selectedIndex: Int?

    private let chartH: CGFloat = 92
    private let cal = Calendar.current

    // MARK: Derived

    /// Consistent Y-axis ceiling: year maximum × 1.15 padding, min 1 to avoid /0
    private var maxValue: Double {
        max(months.map(\.totalSpent).max() ?? 0, 1) * 1.15
    }

    private func ratio(_ m: MI) -> CGFloat {
        CGFloat(m.totalSpent / maxValue)
    }

    /// Index of month with best saving rate (highest savings as % of income)
    private var bestIdx: Int? {
        months.indices
            .filter { months[$0].income > 0 && months[$0].totalSpent > 0 }
            .max { months[$0].savingRate < months[$1].savingRate }
    }

    /// Index of month with highest absolute spending
    private var worstIdx: Int? {
        months.indices
            .filter { months[$0].totalSpent > 0 }
            .max { months[$0].totalSpent < months[$1].totalSpent }
    }

    private func isCurrent(_ m: MI) -> Bool {
        cal.isDate(m.monthStart, equalTo: Date(), toGranularity: .month)
    }

    private func barColor(idx: Int, month: MI) -> Color {
        if idx == bestIdx  { return VeloceTheme.ok }
        if idx == worstIdx { return VeloceTheme.over }
        if isCurrent(month){ return VeloceTheme.accent }
        return VeloceTheme.accent.opacity(0.30)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            chartArea
            labelsRow
            if let sel = selectedIndex, sel >= 0, sel < months.count {
                tooltipCard(
                    month:    months[sel],
                    previous: sel > 0 ? months[sel - 1] : nil
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedIndex)
    }

    // MARK: Header (title + legend)

    private var headerRow: some View {
        HStack {
            Text("Month by Month")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VeloceTheme.textSecondary)
            Spacer()
            HStack(spacing: 10) {
                legendDot(VeloceTheme.ok,   "Best saving")
                legendDot(VeloceTheme.over, "Most spent")
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(VeloceTheme.textTertiary)
        }
    }

    // MARK: Chart area

    private var chartArea: some View {
        GeometryReader { geo in
            let count = max(months.count, 1)
            let bw    = geo.size.width / CGFloat(count)

            ZStack(alignment: .topLeading) {
                // Reference lines + dashed trend line drawn via Canvas
                overlayCanvas(barWidth: bw)

                // Bars — anchored to bottom
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(months.enumerated()), id: \.offset) { idx, m in
                        barColumn(idx: idx, month: m)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: chartH)
    }

    // MARK: Individual bar

    private func barColumn(idx: Int, month: MI) -> some View {
        let col   = barColor(idx: idx, month: month)
        let r     = ratio(month)
        let barH  = month.totalSpent > 0 ? max(4, chartH * r) : 0
        let isSel = selectedIndex == idx
        let glow  = (idx == bestIdx || idx == worstIdx)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            if month.totalSpent == 0 {
                // Zero-data placeholder — thin line so layout doesn't collapse
                Capsule()
                    .fill(VeloceTheme.divider)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(col)
                        .shadow(color: col.opacity(glow ? 0.42 : 0), radius: 5, y: 2)
                    if isSel {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(col.opacity(0.8), lineWidth: 1.5)
                    }
                }
                .frame(height: barH)
                .padding(.horizontal, 3)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: chartH)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                selectedIndex = (selectedIndex == idx) ? nil : idx
            }
        }
    }

    // MARK: Canvas overlay — reference lines + smooth dashed trend line

    @ViewBuilder
    private func overlayCanvas(barWidth: CGFloat) -> some View {
        let mv = maxValue   // capture for Canvas closure

        Canvas { ctx, size in
            // Subtle horizontal reference lines at 50% and 75% of max value
            for topFraction in [0.25 as Double, 0.50] {
                var p = Path()
                let y = size.height * topFraction
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(VeloceTheme.divider.opacity(0.8)), lineWidth: 0.5)
            }

            // Smooth bezier trend line (dashed, low opacity)
            guard months.count > 1, months.contains(where: { $0.totalSpent > 0 }) else { return }
            let pts: [CGPoint] = months.enumerated().map { i, m in
                CGPoint(
                    x: CGFloat(i) * barWidth + barWidth / 2,
                    y: size.height * (1.0 - CGFloat(m.totalSpent / mv))
                )
            }
            var path = Path()
            path.move(to: pts[0])
            for i in 1..<pts.count {
                let a = pts[i - 1], b = pts[i]
                let cp1 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: a.y)
                let cp2 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: b.y)
                path.addCurve(to: b, control1: cp1, control2: cp2)
            }
            ctx.stroke(
                path,
                with: .color(VeloceTheme.accent.opacity(0.28)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [5, 4])
            )
        }
        .frame(height: chartH)
        .allowsHitTesting(false)
    }

    // MARK: Month labels row

    private var labelsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(months.enumerated()), id: \.offset) { idx, m in
                Text(m.shortLabel)
                    .font(.system(size: 9, weight: selectedIndex == idx ? .bold : .medium))
                    .foregroundStyle(
                        isCurrent(m)          ? VeloceTheme.accent :
                        selectedIndex == idx  ? VeloceTheme.textPrimary :
                                                VeloceTheme.textTertiary
                    )
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Tap tooltip

    private func tooltipCard(month: MI, previous: MI?) -> some View {
        let f        = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale     = Locale(identifier: "en_US")

        let deltaText: String? = {
            guard let prev = previous, prev.totalSpent > 0, month.totalSpent > 0 else { return nil }
            let d   = month.totalSpent - prev.totalSpent
            let pct = abs(d) / prev.totalSpent * 100
            let sym = d >= 0 ? "▲" : "▼"
            return "\(sym) \(String(format: "%.0f%%", pct)) vs \(prev.shortLabel)"
        }()
        let deltaIsUp = (previous?.totalSpent ?? 0) < month.totalSpent

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(f.string(from: month.monthStart))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VeloceTheme.textPrimary)

                HStack(spacing: 14) {
                    tooltipStat("Spent",  month.totalSpent.toCompactCurrency(), VeloceTheme.textPrimary)
                    if month.income > 0 {
                        tooltipStat("Saved",  month.totalSaved.toCompactCurrency(), VeloceTheme.ok)
                        tooltipStat(
                            "Rate",
                            String(format: "%.0f%%", month.savingRate),
                            month.savingRate >= 20 ? VeloceTheme.ok : VeloceTheme.caution
                        )
                    }
                }
            }
            Spacer()
            if let d = deltaText {
                Text(d)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(deltaIsUp ? VeloceTheme.over : VeloceTheme.ok)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(VeloceTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tooltipStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(VeloceTheme.textTertiary)
        }
    }
}

// MARK: - InsightCardView

struct InsightCardView: View {
    let card:       InsightCard
    let onAskAI:    () -> Void

    private var accentColor: Color { Color(hex: card.hexColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: card.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        priorityBadge
                        Text(card.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textPrimary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }

            // Key number
            Text(card.keyNumber)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)

            // Detail
            Text(card.detail)
                .font(.system(size: 13))
                .foregroundStyle(VeloceTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Bottom action row
            HStack(spacing: 8) {
                if let action = card.action {
                    Text(action)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(accentColor.opacity(0.10), in: Capsule())
                        .lineLimit(1)
                }

                Spacer()

                if card.aiPrompt != nil {
                    Button(action: onAskAI) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Ask AI")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(VeloceTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(VeloceTheme.accentBg, in: Capsule())
                        .overlay(Capsule().strokeBorder(VeloceTheme.accent.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(VeloceTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accentColor.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var priorityBadge: some View {
        switch card.priority {
        case .risk:
            Text("RISK")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(VeloceTheme.over)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(VeloceTheme.over.opacity(0.12), in: Capsule())
        case .opportunity:
            Text("TIP")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(VeloceTheme.ok)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(VeloceTheme.ok.opacity(0.12), in: Capsule())
        case .informational:
            EmptyView()
        }
    }
}

// MARK: - Preview

#Preview {
    InsightsView()
        .environmentObject(ExpenseViewModel())
        .environmentObject(SubscriptionManager.shared)
}
