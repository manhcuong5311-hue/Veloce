import SwiftUI

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject private var authVM:     AuthViewModel
    @EnvironmentObject private var vm:         ExpenseViewModel
    @EnvironmentObject private var subManager: SubscriptionManager

    @State private var selectedCategory:   Category? = nil
    @State private var editingExpense:     Expense?  = nil
    @State private var showAddExpense               = false
    @State private var quickAddCategoryId: UUID?    = nil
    @State private var showPaywall                  = false
    @State private var showAIAssistant              = false
    @State private var showEditGroups               = false
    @State private var showSettings                 = false

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // ── Summary header ───────────────────────────────────
                        SummaryHeaderView(onAITap: handleAITap)
                            .environmentObject(vm)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 20)

                        // ── Spending columns card ────────────────────────────
                        ColumnsCard(
                            onTap:        { cat in selectedCategory   = cat },
                            onLongPress:  { cat in selectedCategory   = cat },
                            onSwipeUp:    { cat in
                                quickAddCategoryId = cat.id
                                showAddExpense = true
                            },
                            onEditGroups: { showEditGroups = true }
                        )
                        .environmentObject(vm)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                        // ── Timeline expense log ─────────────────────────────
                        ExpenseTimeline(onEdit: { editingExpense = $0 })
                            .environmentObject(vm)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Veloce")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(VeloceTheme.textSecondary)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InputBarView(onManualAdd: { showAddExpense = true })
                .environmentObject(vm)
        }
        .sheet(item: $selectedCategory) { cat in
            CategoryDetailSheet(category: cat)
                .environmentObject(vm)
                .environmentObject(subManager)
        }
        .sheet(isPresented: $showAddExpense, onDismiss: { quickAddCategoryId = nil }) {
            AddExpenseSheet(preselectedCategoryId: quickAddCategoryId)
                .environmentObject(vm)
        }
        .sheet(item: $editingExpense) { exp in
            EditExpenseSheet(expense: exp).environmentObject(vm)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subManager)
        }
        .sheet(isPresented: $showEditGroups) {
            EditGroupsSheet().environmentObject(vm)
        }
        .sheet(isPresented: $showAIAssistant) {
            AIAssistantView()
                .environmentObject(vm)
                .environmentObject(subManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authVM)
                .environmentObject(subManager)
                .environmentObject(vm)
        }
        .preferredColorScheme(.light)
    }

    private func handleAITap() {
        if subManager.isProUser || subManager.canUseAI {
            showAIAssistant = true
        } else {
            showPaywall = true
        }
    }
}

// MARK: - Summary Header

private struct SummaryHeaderView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    var onAITap: () -> Void = {}

    private var monthYear: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Month label + AI button
            HStack {
                Text(monthYear)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .tracking(0.3)
                Spacer()
                Button(action: onAITap) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("AI")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(VeloceTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(VeloceTheme.accentBg, in: Capsule())
                }
            }

            // Total spent hero
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

            // Progress bar + budget row
            VStack(alignment: .leading, spacing: 8) {
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
        vm.overallRatio < 0.75
            ? VeloceTheme.accent
            : vm.overallRatio < 1.0 ? VeloceTheme.caution : VeloceTheme.over
    }
}

// MARK: - Columns Card

private struct ColumnsCard: View {
    @EnvironmentObject var vm: ExpenseViewModel
    let onTap:        (Category) -> Void
    let onLongPress:  (Category) -> Void
    let onSwipeUp:    (Category) -> Void
    let onEditGroups: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Spending")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Spacer()
                heightToggle
                editGroupsButton
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(vm.visibleCategories) { cat in
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
                        .equatable()
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

    private var editGroupsButton: some View {
        Button(action: onEditGroups) {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                Text("Groups")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(VeloceTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(VeloceTheme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(VeloceTheme.divider, lineWidth: 1))
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
            Text("Try: \"coffee 40k\" or \"lunch 80k\"")
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

    @State private var confirmDelete = false

    private var dayTotal: Double { group.items.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .tracking(0.2)
                Spacer()
                Text(dayTotal.toCompactCurrency())
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(VeloceTheme.textTertiary)
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VeloceTheme.textTertiary)
                        .frame(width: 26, height: 26)
                        .background(
                            VeloceTheme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .confirmationDialog(
                    "Delete all \(group.items.count) expense\(group.items.count == 1 ? "" : "s") from \(group.title)?",
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete All", role: .destructive) {
                        withAnimation { vm.deleteExpenses(group.items) }
                    }
                }
            }

            VStack(spacing: 8) {
                ForEach(group.items) { expense in
                    ExpenseRowView(
                        expense:  expense,
                        category: vm.category(for: expense.categoryId),
                        onDelete: { vm.deleteExpense(expense) },
                        onEdit:   { onEdit(expense) }
                    )
                    .equatable()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(ExpenseViewModel())
        .environmentObject(SubscriptionManager.shared)
}
