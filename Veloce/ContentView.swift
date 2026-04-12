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
                        SummaryHeaderView()
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
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(VeloceTheme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(VeloceTheme.surfaceRaised, in: Circle())
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InputBarView(onAITap: handleAITap, onManualAdd: { showAddExpense = true })
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
            EditGroupsSheet()
                .environmentObject(vm)
                .environmentObject(subManager)
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

// MARK: - Spending Panel State

private enum SpendingPanelState: String {
    case compact, medium, expanded

    var maxBarHeight: CGFloat {
        switch self {
        case .compact:  return 72
        case .medium:   return 160
        case .expanded: return 220
        }
    }

    /// Show category name + amount labels
    var showLabels: Bool { self != .compact }
    /// Show % spent badge
    var showPercentage: Bool { self == .expanded }

    /// Next state when dragging up (expand)
    var larger: SpendingPanelState {
        switch self {
        case .compact:  return .medium
        case .medium:   return .expanded
        case .expanded: return .expanded
        }
    }

    /// Next state when dragging down (collapse)
    var smaller: SpendingPanelState {
        switch self {
        case .compact:  return .compact
        case .medium:   return .compact
        case .expanded: return .medium
        }
    }
}

// MARK: - Columns Card

private struct ColumnsCard: View {
    @EnvironmentObject var vm: ExpenseViewModel
    let onTap:        (Category) -> Void
    let onLongPress:  (Category) -> Void
    let onSwipeUp:    (Category) -> Void
    let onEditGroups: () -> Void

    // Edit-budget mode state
    @State private var isEditingBudget:  Bool   = false
    @State private var activeCategoryId: UUID?  = nil
    @State private var fixedTotalBudget: Double = 0   // total frozen on entry

    // Panel resize state
    @AppStorage("spending_panel_state") private var savedState: String = SpendingPanelState.medium.rawValue
    @State private var panelState:  SpendingPanelState = .medium
    @State private var dragOffset:  CGFloat = 0
    @State private var isDragging:  Bool    = false
    @AppStorage("spending_hint_seen") private var hintSeen: Bool = false

    private var remainingBudget: Double {
        fixedTotalBudget - vm.totalBudget
    }

    /// Live bar height that tracks the finger during drag, then snaps on release
    private var effectiveBarHeight: CGFloat {
        // Negative dragOffset = dragging up = expand = more height
        let adjusted = panelState.maxBarHeight - dragOffset
        return min(max(adjusted, SpendingPanelState.compact.maxBarHeight),
                   SpendingPanelState.expanded.maxBarHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Header ───────────────────────────────────────────
            if isEditingBudget {
                editHeader
            } else {
                normalHeader
            }

            // ── Hint text (edit-budget mode) ─────────────────────
            if isEditingBudget {
                HStack(spacing: 5) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 11))
                    Text("Drag bars to adjust your budget")
                        .font(.system(size: 12))
                }
                .foregroundStyle(VeloceTheme.textSecondary)
                .padding(.horizontal, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── Columns ──────────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 14) {
                    if isEditingBudget {
                        ForEach(vm.visibleCategories) { cat in
                            BudgetEditColumnView(
                                category:      cat,
                                totalBudget:   fixedTotalBudget,
                                categoryColor: vm.categoryColor(for: cat),
                                isActive:      activeCategoryId == cat.id,
                                isAnyActive:   activeCategoryId != nil,
                                onBudgetChange: { newBudget in
                                    applyBudget(newBudget, for: cat)
                                },
                                onDragStart: {
                                    withAnimation(.spring(response: 0.28)) {
                                        activeCategoryId = cat.id
                                    }
                                },
                                onDragEnd: {
                                    withAnimation(.spring(response: 0.35)) {
                                        activeCategoryId = nil
                                    }
                                }
                            )
                        }
                    } else {
                        ForEach(vm.visibleCategories) { cat in
                            CategoryColumnView(
                                category:       cat,
                                barRatio:       vm.barRatio(for: cat),
                                categoryColor:  vm.categoryColor(for: cat),
                                statusColor:    vm.statusColor(for: cat),
                                isHighlighted:  vm.highlightedCategoryId == cat.id,
                                maxBarH:        effectiveBarHeight,
                                showLabels:     panelState.showLabels,
                                showPercentage: panelState.showPercentage,
                                isResizing:     isDragging,
                                onTap:          { onTap(cat) },
                                onLongPress:    { onLongPress(cat) },
                                onSwipeUp:      { onSwipeUp(cat) }
                            )
                            .equatable()
                        }
                    }
                }
                .padding(.horizontal, 2)
                // Extra top padding in edit mode so the bubble (inside barStack) has
                // visual breathing room near the card's top edge.
                .padding(.top, isEditingBudget ? 10 : 0)
                .padding(.bottom, 4)
            }

            // ── Resize handle (hidden in edit mode) ──────────────
            if !isEditingBudget {
                resizeHandleArea
            }
        }
        .veloceCard(radius: 22, padding: 20)
        // Extra elevation shadow while dragging
        .shadow(
            color: .black.opacity(isDragging ? 0.10 : 0),
            radius: 28, x: 0, y: 12
        )
        .scaleEffect(isDragging ? 1.006 : 1.0)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isEditingBudget)
        .animation(.spring(response: 0.28), value: isDragging)
        .onAppear {
            panelState = SpendingPanelState(rawValue: savedState) ?? .medium
        }
    }

    // MARK: - Resize handle

    private var resizeHandleArea: some View {
        VStack(spacing: 6) {
            // First-time hint
            if !hintSeen {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 9, weight: .medium))
                    Text("Drag to expand")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(VeloceTheme.textTertiary)
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation(.easeOut(duration: 0.4)) { hintSeen = true }
                    }
                }
            }

            // Pill handle
            Capsule()
                .fill(isDragging ? VeloceTheme.textSecondary : VeloceTheme.divider)
                .frame(width: isDragging ? 52 : 36, height: isDragging ? 5 : 4)
                .animation(.spring(response: 0.2), value: isDragging)
                .frame(maxWidth: .infinity)
                // Tall hit target so users can grab it easily
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(resizeGesture)
        }
    }

    // MARK: - Resize gesture

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if !isDragging {
                    withAnimation(.spring(response: 0.2)) { isDragging = true }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if !hintSeen {
                        withAnimation(.easeOut(duration: 0.3)) { hintSeen = true }
                    }
                }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                // Incorporate a fraction of the throw velocity for a more natural feel
                let velocity  = value.predictedEndTranslation.height - value.translation.height
                let projected = value.translation.height + velocity * 0.25
                let threshold: CGFloat = 30

                let next: SpendingPanelState
                if projected < -threshold {
                    next = panelState.larger
                } else if projected > threshold {
                    next = panelState.smaller
                } else {
                    next = panelState
                }

                let changed = next != panelState

                withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
                    panelState = next
                    dragOffset = 0
                    isDragging = false
                }

                savedState = next.rawValue
                if changed {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
    }

    // MARK: - Headers

    private var normalHeader: some View {
        HStack(spacing: 8) {
            Text("Spending")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VeloceTheme.textPrimary)
            Spacer()
            editBudgetButton
            editGroupsButton
        }
    }

    private var editHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Edit Budget")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textPrimary)

                // Remaining pool – turns red when over-allocated
                HStack(spacing: 4) {
                    Circle()
                        .fill(remainingBudget < 0 ? VeloceTheme.over : VeloceTheme.ok)
                        .frame(width: 5, height: 5)
                    Text(remainingBudget < 0
                         ? "\((-remainingBudget).toCompactCurrency()) over"
                         : "\(remainingBudget.toCompactCurrency()) remaining")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(remainingBudget < 0
                                         ? VeloceTheme.over
                                         : VeloceTheme.textSecondary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.25), value: remainingBudget)
                }
            }

            Spacer()

            // Done button
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                    isEditingBudget  = false
                    activeCategoryId = nil
                }
            } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VeloceTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(VeloceTheme.accentBg, in: Capsule())
            }
        }
    }

    // MARK: - Edit Budget button (replaces the old Absolute/Relative toggle)

    private var editBudgetButton: some View {
        Button {
            fixedTotalBudget = vm.totalBudget   // freeze total before entering
            withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                isEditingBudget = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 11))
                Text("Edit Budget")
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

    // MARK: - Budget constraint logic

    /// Applies a new budget for one category, clamped so total never exceeds fixedTotalBudget.
    private func applyBudget(_ newBudget: Double, for category: Category) {
        // Sum of every other category's budget
        let othersTotal = vm.categories
            .filter { $0.id != category.id }
            .reduce(0) { $0 + $1.budget }

        let maxAllowed = max(0, fixedTotalBudget - othersTotal)
        let clamped    = min(newBudget, maxAllowed)

        // Warn with haptic when hitting the wall
        if newBudget > maxAllowed {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        vm.updateBudget(categoryId: category.id, newBudget: clamped)
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
