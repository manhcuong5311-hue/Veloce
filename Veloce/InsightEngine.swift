import Foundation

// MARK: - InsightCard

struct InsightCard: Identifiable {

    enum Priority: Int, Comparable {
        case risk = 0, opportunity = 1, informational = 2
        static func < (l: Priority, r: Priority) -> Bool { l.rawValue < r.rawValue }
    }

    enum Kind {
        case anomaly, forecast, saving, categorySpike, consecutiveTrend,
             behavioral, streak, weekly, micro
    }

    let id                = UUID()
    let priority:           Priority
    let kind:               Kind
    let icon:               String       // SF Symbol
    let title:              String
    let keyNumber:          String       // Large highlighted value
    let detail:             String       // 1–2 sentence explanation
    let action:             String?      // Suggested action label
    let aiPrompt:           String?      // Pre-filled prompt for AI chat
    let hexColor:           String
    let relatedCategoryId:  UUID?
}

// MARK: - InsightEngine

struct InsightEngine {

    // MARK: MonthlyData

    struct MonthlyData {
        let monthStart:  Date
        let monthEnd:    Date
        let expenses:    [Expense]
        let total:       Double
        let byCategory:  [UUID: Double]

        /// Days elapsed:
        /// • current month → today's day-of-month (min 1)
        /// • past month    → full calendar days in the month
        var daysElapsed: Int {
            let cal = Calendar.current
            let now = Date()
            if now >= monthStart && now < monthEnd {
                return max(1, cal.component(.day, from: now))
            }
            let comps = cal.dateComponents([.day], from: monthStart, to: monthEnd)
            return max(1, comps.day ?? 30)
        }

        var dailyRate: Double {
            let d = daysElapsed
            return d > 0 ? total / Double(d) : 0
        }
    }

    // MARK: Build monthly windows (oldest → newest)

    static func buildMonthly(from expenses: [Expense], count: Int = 6) -> [MonthlyData] {
        let cal = Calendar.current
        let now = Date()
        return (0..<count).reversed().compactMap { offset -> MonthlyData? in
            guard
                let monthDate  = cal.date(byAdding: .month, value: -offset, to: now),
                let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
                let monthEnd   = cal.date(byAdding: .month, value: 1, to: monthStart)
            else { return nil }

            let slice = expenses.filter { $0.date >= monthStart && $0.date < monthEnd }
            var byCat: [UUID: Double] = [:]
            for e in slice { byCat[e.categoryId, default: 0] += e.amount }

            return MonthlyData(
                monthStart: monthStart,
                monthEnd:   monthEnd,
                expenses:   slice,
                total:      slice.reduce(0) { $0 + $1.amount },
                byCategory: byCat
            )
        }
    }

    // MARK: Main entry point

    /// Returns priority-sorted InsightCards (risk → opportunity → informational).
    static func generate(
        expenses:      [Expense],
        categories:    [Category],
        monthlyIncome: Double,
        savingGoal:    Double
    ) -> [InsightCard] {
        guard !expenses.isEmpty else { return [] }

        let monthly = buildMonthly(from: expenses, count: 6)
        guard let current = monthly.last else { return [] }

        var cards: [InsightCard] = []

        // Risk
        if let c = anomalyCard(current: current)                                             { cards.append(c) }
        if let c = forecastCard(current: current, savingGoal: savingGoal, income: monthlyIncome) { cards.append(c) }

        // Opportunity
        cards += categoryInsightCards(monthly: monthly, categories: categories)
        if let c = consecutiveTrendCard(monthly: monthly, categories: categories)            { cards.append(c) }
        if let c = savingCard(current: current, savingGoal: savingGoal, income: monthlyIncome) { cards.append(c) }
        if let c = weekendCard(current: current)                                             { cards.append(c) }

        // Informational
        if let c = streakCard(current: current, income: monthlyIncome, savingGoal: savingGoal) { cards.append(c) }
        if let c = weeklyCard(current: current)                                              { cards.append(c) }
        if let c = microCard(categories: categories)                                         { cards.append(c) }

        return cards.sorted { $0.priority < $1.priority }
    }

    // MARK: - Anomaly: today's spike vs 7-day daily average

    private static func anomalyCard(current: MonthlyData) -> InsightCard? {
        let cal      = Calendar.current
        let now      = Date()
        let todayStart = cal.startOfDay(for: now)

        let todayTotal = current.expenses
            .filter { $0.date >= todayStart }
            .reduce(0) { $0 + $1.amount }
        guard todayTotal > 0 else { return nil }

        // 7-day average excluding today
        let sevenAgo = cal.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        let recentExpenses = current.expenses.filter { $0.date >= sevenAgo && $0.date < todayStart }
        let recentAvg: Double
        if recentExpenses.isEmpty {
            let prev = current.daysElapsed - 1
            recentAvg = prev > 0 ? current.total / Double(prev) : 0
        } else {
            recentAvg = recentExpenses.reduce(0) { $0 + $1.amount } / 7.0
        }
        guard recentAvg > 0, todayTotal >= recentAvg * 2.5 else { return nil }

        let multiple = todayTotal / recentAvg
        return InsightCard(
            priority:          .risk,
            kind:              .anomaly,
            icon:              "bolt.fill",
            title:             String(localized: "insight_anomaly_title"),
            keyNumber:         todayTotal.toCompactCurrency(),
            detail:            String(format: String(localized: "insight_anomaly_detail_fmt"),
                                      todayTotal.toCompactCurrency(), multiple, recentAvg.toCompactCurrency()),
            action:            String(localized: "insight_anomaly_action"),
            aiPrompt:          "I spent \(todayTotal.toCompactCurrency()) today — \(String(format: "%.1f", multiple))× my usual daily average of \(recentAvg.toCompactCurrency()). What happened and how should I adjust?",
            hexColor:          "E88A7A",
            relatedCategoryId: nil
        )
    }

    // MARK: - Forecast: project end-of-month savings

    private static func forecastCard(
        current:    MonthlyData,
        savingGoal: Double,
        income:     Double
    ) -> InsightCard? {
        guard income > 0, current.daysElapsed > 3 else { return nil }

        let cal = Calendar.current
        let daysInMonth = cal.dateComponents([.day], from: current.monthStart, to: current.monthEnd).day ?? 30
        let projectedSpend  = current.dailyRate * Double(daysInMonth)
        let projectedSaving = income - projectedSpend
        let isOnTrack       = savingGoal <= 0 || projectedSaving >= savingGoal * 0.9

        // Don't show trivial "on track" card when no saving goal is set
        if isOnTrack && savingGoal <= 0 { return nil }

        let shortfall  = max(0, savingGoal - projectedSaving)
        let daysLeft   = max(1, daysInMonth - current.daysElapsed)
        let dailyCut   = shortfall / Double(daysLeft)

        let detail: String
        if projectedSaving < 0 {
            detail = String(format: String(localized: "insight_forecast_overspend_detail_fmt"),
                            (-projectedSaving).toCompactCurrency(), dailyCut.toCompactCurrency())
        } else if isOnTrack {
            detail = String(format: String(localized: "insight_forecast_ontrack_detail_fmt"),
                            projectedSaving.toCompactCurrency(), savingGoal.toCompactCurrency())
        } else {
            detail = String(format: String(localized: "insight_forecast_shortfall_detail_fmt"),
                            projectedSaving.toCompactCurrency(), shortfall.toCompactCurrency(),
                            savingGoal.toCompactCurrency(), dailyCut.toCompactCurrency())
        }

        return InsightCard(
            priority:          isOnTrack ? .opportunity : .risk,
            kind:              .forecast,
            icon:              isOnTrack ? "chart.line.uptrend.xyaxis" : "exclamationmark.triangle.fill",
            title:             isOnTrack ? String(localized: "insight_forecast_ontrack_title") : String(localized: "insight_forecast_atrisk_title"),
            keyNumber:         max(0, projectedSaving).toCompactCurrency(),
            detail:            detail,
            action:            isOnTrack ? nil : String(format: String(localized: "insight_forecast_atrisk_action_fmt"), dailyCut.toCompactCurrency()),
            aiPrompt:          "My projected end-of-month savings is \(max(0, projectedSaving).toCompactCurrency()) and my goal is \(savingGoal.toCompactCurrency()). What should I cut to stay on track?",
            hexColor:          isOnTrack ? "6BBF8E" : "E8B86D",
            relatedCategoryId: nil
        )
    }

    // MARK: - Category spike: >10% increase vs last month and >100k delta

    private static func categoryInsightCards(
        monthly:    [MonthlyData],
        categories: [Category]
    ) -> [InsightCard] {
        guard let current  = monthly.last,
              let previous = monthly.dropLast().last,
              previous.total > 0
        else { return [] }

        let minDelta: Double = 100_000
        var cards: [InsightCard] = []

        for cat in categories where !cat.isHidden {
            let cur  = current.byCategory[cat.id]  ?? 0
            let prev = previous.byCategory[cat.id] ?? 0
            guard prev > 0, cur > 0 else { continue }
            let delta = cur - prev
            let pct   = delta / prev * 100
            guard pct >= 10, delta >= minDelta else { continue }

            let save20 = cur * 0.20
            cards.append(InsightCard(
                priority:          .opportunity,
                kind:              .categorySpike,
                icon:              "arrow.up.right.circle.fill",
                title:             String(format: String(localized: "insight_catspike_title_fmt"), cat.name, pct),
                keyNumber:         "+\(delta.toCompactCurrency())",
                detail:            String(format: String(localized: "insight_catspike_detail_fmt"),
                                          cat.name, cur.toCompactCurrency(), prev.toCompactCurrency(), save20.toCompactCurrency()),
                action:            String(format: String(localized: "insight_catspike_action_fmt"), cat.name, save20.toCompactCurrency()),
                aiPrompt:          "My \(cat.name) spending jumped \(String(format: "%.0f", pct))% vs last month (+\(delta.toCompactCurrency())). What's driving this and how can I reduce it?",
                hexColor:          cat.colorHex,
                relatedCategoryId: cat.id
            ))
        }

        return Array(cards.prefix(2))
    }

    // MARK: - Consecutive trend: 3+ months rising ≥5% in same category

    private static func consecutiveTrendCard(
        monthly:    [MonthlyData],
        categories: [Category]
    ) -> InsightCard? {
        guard monthly.count >= 3 else { return nil }

        for cat in categories where !cat.isHidden {
            var streak = 0
            var maxStreak = 0
            for i in 1..<monthly.count {
                let prev = monthly[i - 1].byCategory[cat.id] ?? 0
                let curr = monthly[i].byCategory[cat.id] ?? 0
                let pct  = prev > 0 ? (curr - prev) / prev * 100 : 0
                if pct >= 5 { streak += 1; maxStreak = max(maxStreak, streak) }
                else        { streak = 0 }
            }
            guard maxStreak >= 2 else { continue }  // 3 consecutive months = 2 jumps

            let months = maxStreak + 1
            return InsightCard(
                priority:          .opportunity,
                kind:              .consecutiveTrend,
                icon:              "arrow.up.right.square.fill",
                title:             String(format: String(localized: "insight_trend_title_fmt"), cat.name, months),
                keyNumber:         "\(months)",
                detail:            String(format: String(localized: "insight_trend_detail_fmt"), cat.name, months),
                action:            String(format: String(localized: "insight_trend_action_fmt"), cat.name),
                aiPrompt:          "My \(cat.name) spending has been rising for \(months) consecutive months. Help me understand why and how to break the trend.",
                hexColor:          cat.colorHex,
                relatedCategoryId: cat.id
            )
        }
        return nil
    }

    // MARK: - Saving progress toward monthly goal

    private static func savingCard(
        current:    MonthlyData,
        savingGoal: Double,
        income:     Double
    ) -> InsightCard? {
        guard savingGoal > 0, income > 0 else { return nil }

        let remaining = income - current.total
        let pct       = min(remaining / savingGoal * 100, 100)
        let isAhead   = remaining >= savingGoal

        return InsightCard(
            priority:          isAhead ? .opportunity : .informational,
            kind:              .saving,
            icon:              isAhead ? "leaf.fill" : "target",
            title:             isAhead ? String(localized: "insight_saving_secured_title") : String(localized: "insight_saving_progress_title"),
            keyNumber:         String(format: "%.0f%%", max(0, pct)),
            detail:            isAhead
                ? String(format: String(localized: "insight_saving_secured_detail_fmt"),
                          remaining.toCompactCurrency(), pct, savingGoal.toCompactCurrency())
                : String(format: String(localized: "insight_saving_progress_detail_fmt"),
                          pct, savingGoal.toCompactCurrency(), (income - savingGoal).toCompactCurrency()),
            action:            isAhead ? nil : String(format: String(localized: "insight_saving_progress_action_fmt"),
                                                      (income - savingGoal).toCompactCurrency()),
            aiPrompt:          "I'm at \(String(format: "%.0f", pct))% of my \(savingGoal.toCompactCurrency()) monthly saving goal. What's the best strategy to reach it?",
            hexColor:          isAhead ? "6BBF8E" : "7B6CF0",
            relatedCategoryId: nil
        )
    }

    // MARK: - Weekend behavioral pattern

    private static func weekendCard(current: MonthlyData) -> InsightCard? {
        guard current.expenses.count >= 5 else { return nil }
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"

        var weekdayTotal: Double = 0, weekendTotal: Double = 0
        var weekdayDays = Set<String>(), weekendDays = Set<String>()

        for e in current.expenses {
            let wd  = cal.component(.weekday, from: e.date)
            let key = fmt.string(from: e.date)
            if wd == 1 || wd == 7 { weekendTotal += e.amount; weekendDays.insert(key) }
            else                  { weekdayTotal += e.amount; weekdayDays.insert(key) }
        }
        guard !weekdayDays.isEmpty, !weekendDays.isEmpty else { return nil }

        let weekdayAvg = weekdayTotal / Double(weekdayDays.count)
        let weekendAvg = weekendTotal / Double(weekendDays.count)
        guard weekdayAvg > 0, weekendAvg >= weekdayAvg * 1.3 else { return nil }

        let ratio = weekendAvg / weekdayAvg
        return InsightCard(
            priority:          .opportunity,
            kind:              .behavioral,
            icon:              "calendar.badge.plus",
            title:             String(format: String(localized: "insight_weekend_title_fmt"), (ratio - 1) * 100),
            keyNumber:         String(format: "×%.1f", ratio),
            detail:            String(format: String(localized: "insight_weekend_detail_fmt"),
                                      weekendAvg.toCompactCurrency(), weekdayAvg.toCompactCurrency(), ratio),
            action:            String(localized: "insight_weekend_action"),
            aiPrompt:          "I spend \(String(format: "%.1f", ratio))× more on weekends (\(weekendAvg.toCompactCurrency())/day) than weekdays (\(weekdayAvg.toCompactCurrency())/day). How can I close this gap?",
            hexColor:          "E8B86D",
            relatedCategoryId: nil
        )
    }

    // MARK: - Streak: consecutive days of mindful spending (>0 and ≤ daily budget)

    private static func streakCard(
        current:    MonthlyData,
        income:     Double,
        savingGoal: Double
    ) -> InsightCard? {
        guard income > 0, current.daysElapsed >= 3 else { return nil }
        let dailyBudget = (income - savingGoal) / 30.0
        guard dailyBudget > 0 else { return nil }

        let cal = Calendar.current
        let now = Date()

        var dailyTotals: [Date: Double] = [:]
        for e in current.expenses {
            let day = cal.startOfDay(for: e.date)
            dailyTotals[day, default: 0] += e.amount
        }

        var streak   = 0
        var checkDay = cal.startOfDay(for: now)
        for _ in 0..<30 {
            guard let prevDay = cal.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = prevDay
            let spent = dailyTotals[checkDay] ?? 0
            if spent > 0 && spent <= dailyBudget { streak += 1 }
            else { break }
        }
        guard streak >= 3 else { return nil }

        return InsightCard(
            priority:          .informational,
            kind:              .streak,
            icon:              "flame.fill",
            title:             String(format: String(localized: "insight_streak_title_fmt"), streak),
            keyNumber:         "\(streak)",
            detail:            String(format: String(localized: "insight_streak_detail_fmt"),
                                      dailyBudget.toCompactCurrency(), streak),
            action:            nil,
            aiPrompt:          "I've spent under budget for \(streak) days in a row. How do I maintain this momentum?",
            hexColor:          "E07A5F",
            relatedCategoryId: nil
        )
    }

    // MARK: - Weekly: this week vs last week

    private static func weeklyCard(current: MonthlyData) -> InsightCard? {
        let cal = Calendar.current
        let now = Date()
        guard let weekStart     = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart)
        else { return nil }

        let thisWeek = current.expenses
            .filter { $0.date >= weekStart }
            .reduce(0) { $0 + $1.amount }
        let lastWeek = current.expenses
            .filter { $0.date >= lastWeekStart && $0.date < weekStart }
            .reduce(0) { $0 + $1.amount }

        guard thisWeek > 0, lastWeek > 0 else { return nil }

        let delta = thisWeek - lastWeek
        let pct   = abs(delta) / lastWeek * 100
        let isUp  = delta > 0

        return InsightCard(
            priority:          .informational,
            kind:              .weekly,
            icon:              "calendar.badge.checkmark",
            title:             String(localized: "insight_weekly_title"),
            keyNumber:         thisWeek.toCompactCurrency(),
            detail:            isUp
                ? String(format: String(localized: "insight_weekly_detail_up_fmt"),
                          thisWeek.toCompactCurrency(), pct, lastWeek.toCompactCurrency())
                : String(format: String(localized: "insight_weekly_detail_down_fmt"),
                          thisWeek.toCompactCurrency(), pct, lastWeek.toCompactCurrency()),
            action:            nil,
            aiPrompt:          "I spent \(thisWeek.toCompactCurrency()) this week vs \(lastWeek.toCompactCurrency()) last week (\(isUp ? "+" : "-")\(String(format: "%.0f%%", pct))). Is this a concerning trend?",
            hexColor:          "5B8DB8",
            relatedCategoryId: nil
        )
    }

    // MARK: - Micro: single actionable 10% reduction for top over-budget category

    private static func microCard(categories: [Category]) -> InsightCard? {
        let active = categories.filter { !$0.isHidden && $0.spent > 0 }
        guard !active.isEmpty else { return nil }

        let cat: Category? =
            active.filter { $0.spent > $0.budget && $0.budget > 0 }
                  .sorted  { ($0.spent - $0.budget) > ($1.spent - $1.budget) }
                  .first
            ?? active.sorted { $0.spent > $1.spent }.first

        guard let cat else { return nil }

        let reduce10 = cat.spent * 0.10
        let yearly   = reduce10 * 12
        let perDay   = reduce10 / 30.0

        return InsightCard(
            priority:          .informational,
            kind:              .micro,
            icon:              "lightbulb.fill",
            title:             String(format: String(localized: "insight_micro_title_fmt"), cat.name),
            keyNumber:         reduce10.toCompactCurrency(),
            detail:            String(format: String(localized: "insight_micro_detail_fmt"),
                                      cat.name, reduce10.toCompactCurrency(), yearly.toCompactCurrency(), perDay.toCompactCurrency()),
            action:            String(format: String(localized: "insight_micro_action_fmt"), cat.name),
            aiPrompt:          "Help me reduce my \(cat.name) spending by 10%. What specific things can I cut?",
            hexColor:          cat.colorHex,
            relatedCategoryId: cat.id
        )
    }
}
