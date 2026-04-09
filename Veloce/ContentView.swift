import SwiftUI

// MARK: - Root

struct ContentView: View {
    @StateObject private var vm = ExpenseViewModel()

    @State private var selectedCategory: Category? = nil
    @State private var editingExpense:   Expense?  = nil
    @State private var showAddExpense               = false
    @State private var quickAddCategoryId: UUID?    = nil

    var body: some View {
        ZStack {
            VeloceTheme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    // ── Summary header ───────────────────────────────────
                    SummaryHeaderView()
                        .environmentObject(vm)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 20)

                    // ── Spending columns card ────────────────────────────
                    ColumnsCard(
                        onTap:       { cat in selectedCategory   = cat },
                        onLongPress: { cat in selectedCategory   = cat },
                        onSwipeUp:   { cat in
                            quickAddCategoryId = cat.id
                            showAddExpense = true
                        }
                    )
                    .environmentObject(vm)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // ── Timeline expense log ─────────────────────────────
                    ExpenseTimeline(
                        onEdit: { editingExpense = $0 }
                    )
                    .environmentObject(vm)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InputBarView(onManualAdd: { showAddExpense = true })
                .environmentObject(vm)
        }
        .sheet(item: $selectedCategory) { cat in
            CategoryDetailSheet(category: cat).environmentObject(vm)
        }
        .sheet(isPresented: $showAddExpense, onDismiss: { quickAddCategoryId = nil }) {
            AddExpenseSheet(preselectedCategoryId: quickAddCategoryId).environmentObject(vm)
        }
        .sheet(item: $editingExpense) { exp in
            EditExpenseSheet(expense: exp).environmentObject(vm)
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - Summary Header

private struct SummaryHeaderView: View {
    @EnvironmentObject var vm: ExpenseViewModel

    private var monthYear: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Month label
            Text(monthYear)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VeloceTheme.textSecondary)
                .tracking(0.3)

            // Total spent (hero number)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(vm.totalSpent.toCurrencyString())
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: vm.totalSpent)

                Text("spent")
                    .font(.system(size: 15))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .offset(y: -2)
            }

            // Progress + budget info
            VStack(alignment: .leading, spacing: 8) {
                // Thin progress track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(VeloceTheme.divider)
                            .frame(height: 5)
                        Capsule()
                            .fill(progressColor)
                            .frame(width: geo.size.width * CGFloat(vm.overallRatio), height: 5)
                            .animation(.spring(response: 0.55), value: vm.overallRatio)
                    }
                }
                .frame(height: 5)

                // Budget summary row
                HStack {
                    let rem = vm.totalBudget - vm.totalSpent
                    Text(rem >= 0
                         ? "\(rem.toCompactCurrency()) remaining"
                         : "Over by \((-rem).toCompactCurrency())")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(rem >= 0 ? VeloceTheme.ok : VeloceTheme.over)

                    Spacer()

                    Text("of \(vm.totalBudget.toCompactCurrency())")
                        .font(.system(size: 12))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
            }
        }
    }

    private var progressColor: Color {
        vm.overallRatio < 0.75 ? VeloceTheme.accent : (vm.overallRatio < 1.0 ? VeloceTheme.caution : VeloceTheme.over)
    }
}

// MARK: - Columns Card

private struct ColumnsCard: View {
    @EnvironmentObject var vm: ExpenseViewModel
    let onTap:       (Category) -> Void
    let onLongPress: (Category) -> Void
    let onSwipeUp:   (Category) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card header
            HStack {
                Text("Spending")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Spacer()
                heightToggle
            }

            // Horizontal column scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(vm.categories) { cat in
                        CategoryColumnView(
                            category:      cat,
                            barRatio:      vm.barRatio(for: cat),
                            categoryColor: vm.categoryColor(for: cat),
                            statusColor:   vm.statusColor(for: cat),
                            isHighlighted: vm.highlightedCategoryId == cat.id,
                            onTap:         { onTap(cat) },
                            onLongPress:   { onLongPress(cat) },
                            onSwipeUp:     { onSwipeUp(cat) }
                        )
                        .equatable()   // ← skip re-render when Equatable check passes
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
        }
        .veloceCard(radius: 22, padding: 20)
    }

    private var heightToggle: some View {
        Button {
            withAnimation(.spring(response: 0.3)) { vm.isHeightRelative.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: vm.isHeightRelative ? "chart.bar.fill" : "chart.bar")
                    .font(.system(size: 11))
                Text(vm.isHeightRelative ? "Relative" : "Absolute")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(VeloceTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(VeloceTheme.accentBg, in: Capsule())
        }
    }
}

// MARK: - Expense Timeline

private struct ExpenseTimeline: View {
    @EnvironmentObject var vm: ExpenseViewModel
    let onEdit: (Expense) -> Void

    var body: some View {
        LazyVStack(spacing: 20, pinnedViews: []) {
            if vm.expenseGroups.isEmpty {
                emptyState
            } else {
                ForEach(vm.expenseGroups) { group in
                    DaySection(group: group, onEdit: onEdit)
                        .environmentObject(vm)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(VeloceTheme.textTertiary)
            Text("No expenses yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VeloceTheme.textSecondary)
            Text("Try: \"ăn phở 50k sáng nay\"")
                .font(.system(size: 13))
                .foregroundStyle(VeloceTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Day Section

private struct DaySection: View {
    @EnvironmentObject var vm: ExpenseViewModel
    let group:  ExpenseGroup
    let onEdit: (Expense) -> Void

    private var dayTotal: Double {
        group.items.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(alignment: .firstTextBaseline) {
                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .tracking(0.2)
                Spacer()
                Text(dayTotal.toCompactCurrency())
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VeloceTheme.textTertiary)
            }

            // Expense rows
            VStack(spacing: 8) {
                ForEach(group.items) { expense in
                    ExpenseRowView(
                        expense:  expense,
                        category: vm.category(for: expense.categoryId),
                        onDelete: { vm.deleteExpense(expense) },
                        onEdit:   { onEdit(expense) }
                    )
                    .equatable()   // ← skip re-render when Equatable check passes
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
