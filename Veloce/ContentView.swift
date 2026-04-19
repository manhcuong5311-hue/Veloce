import SwiftUI

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject private var authVM:     AuthViewModel
    @EnvironmentObject private var vm:         ExpenseViewModel
    @EnvironmentObject private var subManager: SubscriptionManager
    @EnvironmentObject private var ratingMgr:  RatingManager
    @EnvironmentObject private var notifMgr:   NotificationManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedCategory:   Category? = nil
    @State private var editingExpense:     Expense?  = nil
    @State private var showAddExpense               = false
    @State private var showAddRecurring             = false
    @State private var showRecurring                = false
    @State private var quickAddCategoryId: UUID?    = nil
    @State private var showPaywall                  = false
    @State private var showAIAssistant              = false
    @State private var showEditGroups               = false
    @State private var showSettings                 = false
    @State private var showInsights                 = false
    #if os(iOS)
    @State private var showApplePayImport           = false
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // ── Notification denied banner ───────────────────────
                        NotificationDeniedBanner()
                            .environmentObject(notifMgr)

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
                        ExpenseTimeline(
                            isPro:        subManager.isProUser,
                            onEdit:       { editingExpense = $0 },
                            onUpgradeTap: { showPaywall = true }
                        )
                            .environmentObject(vm)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // AI entry point — top-left, subtle sparkle
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: handleAITap) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                            Text("ai_tab_label")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(VeloceTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(VeloceTheme.accentBg, in: Capsule())
                    }
                }
                // Insights + Apple Pay import + Recurring + Settings — top-right
                ToolbarItemGroup(placement: .topBarTrailing) {
                    #if os(iOS)
                    if #available(iOS 18, *) {
                        Button(action: { showApplePayImport = true }) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(VeloceTheme.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(VeloceTheme.surfaceRaised, in: Circle())
                        }
                    }
                    #endif
                    Button(action: { showInsights = true }) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(VeloceTheme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(VeloceTheme.surfaceRaised, in: Circle())
                    }
                    Button(action: {
                        if subManager.isProUser { showRecurring = true }
                        else { showPaywall = true }
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(VeloceTheme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(VeloceTheme.surfaceRaised, in: Circle())
                    }
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
            InputBarView(
                onAITap:        handleAITap,
                onManualAdd:    { showAddExpense = true },
                onRecurringAdd: {
                    if subManager.isProUser { showAddRecurring = true }
                    else                    { showPaywall = true }
                }
            )
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
        .sheet(isPresented: $showAddRecurring) {
            AddRecurringSheet()
                .environmentObject(vm)
                .environmentObject(subManager)
        }
        .sheet(isPresented: $showRecurring) {
            RecurringTransactionsView()
                .environmentObject(vm)
                .environmentObject(subManager)
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
        .sheet(isPresented: $showInsights) {
            InsightsView()
                .environmentObject(vm)
                .environmentObject(subManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authVM)
                .environmentObject(subManager)
                .environmentObject(vm)
                .environmentObject(NotificationManager.shared)
        }
        #if os(iOS)
        .sheet(isPresented: $showApplePayImport) {
            if #available(iOS 18, *) {
                ApplePayImportSheet()
                    .environmentObject(vm)
            }
        }
        #endif
        .preferredColorScheme(.light)
        .overlay(alignment: .bottom) {
            RatingSoftPromptView(ratingManager: ratingMgr)
                .ignoresSafeArea()
        }
        .onAppear {
            RatingManager.shared.recordActiveDay()
            vm.processOverdueRecurring()
            checkDay7Paywall()
            checkWeeklyDigest()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                vm.processOverdueRecurring()
            }
        }
        // Soft paywall: trigger after 20th expense for free users
        .onChange(of: vm.softPaywallTrigger) { _, triggered in
            if triggered && !subManager.isProUser {
                showPaywall = true
                vm.softPaywallTrigger = false
            } else if triggered {
                vm.softPaywallTrigger = false
            }
        }
    }

    private func checkDay7Paywall() {
        guard subManager.shouldShowDay7Paywall else { return }
        subManager.markDay7PaywallShown()
        // Delay 2 s so the main UI renders before the sheet appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showPaywall = true
        }
    }

    /// Schedules a local weekly digest notification once per calendar week.
    /// Safe to call on every onAppear — UserDefaults deduplication makes it a no-op
    /// for the rest of the week after the first call.
    private func checkWeeklyDigest() {
        let key = "veloce_weekly_digest_\(currentWeekKey())"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let topCategory = vm.categories
            .filter { $0.spent > 0 }
            .max(by: { $0.spent < $1.spent })?
            .name

        notifMgr.scheduleWeeklyDigest(
            totalSpent:  vm.totalSpent,
            totalBudget: vm.totalBudget,
            topCategory: topCategory
        )
    }

    private func currentWeekKey() -> String {
        let cal   = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(comps.yearForWeekOfYear ?? 0)-W\(comps.weekOfYear ?? 0)"
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
        f.locale = Locale.current
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App name + month label
            VStack(alignment: .leading, spacing: 4) {
                Text("VeloAI")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Text(monthYear)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VeloceTheme.textSecondary)
                    .tracking(0.3)
            }

            // Total spent hero
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(vm.totalSpent.toCurrencyString())
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: vm.totalSpent)

                Text("spent_label")
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
                         ? String(format: String(localized: "budget_remaining_fmt"), rem.toCompactCurrency())
                         : String(format: String(localized: "budget_over_fmt"), (-rem).toCompactCurrency()))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(rem >= 0 ? VeloceTheme.ok : VeloceTheme.over)

                    Spacer()

                    Text(String(format: String(localized: "budget_of_total_fmt"), vm.totalBudget.toCompactCurrency()))
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
    @State private var isEditingBudget:       Bool   = false
    @State private var activeCategoryId:      UUID?  = nil
    @State private var fixedTotalBudget:      Double = 0   // total frozen on entry
    @State private var showConstraintModal:   Bool   = false
    // FIX: scroll target for the edit-mode column strip.
    // Set by the category chip nav bar OR by onDragStart — ScrollViewReader
    // picks this up via onChange and scrolls the active column into view.
    // Using UUID? lets us reset to nil after scrolling so the same chip can
    // trigger a re-scroll if the user has manually scrolled away.
    @State private var editScrollTarget:      UUID?  = nil

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
                    Text(String(localized: "budget.adjust.drag"))
                        .font(.system(size: 12))
                }
                .foregroundStyle(VeloceTheme.textSecondary)
                .padding(.horizontal, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── Columns ──────────────────────────────────────────
            // FIX: split edit vs normal mode into separate blocks so edit mode
            // can add a category navigation strip + ScrollViewReader without
            // wrapping the normal-mode view in unnecessary layers.
            if isEditingBudget {
                // ── Category navigation chips ─────────────────────
                // Allows switching to any category column by tapping its chip,
                // eliminating the Done → back → swipe → re-enter edit cycle.
                // Chips set editScrollTarget; the ScrollViewReader below reacts.
                editCategoryChips

                // ── Edit columns with programmatic scroll support ──
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 14) {
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
                                        // Auto-scroll the column being dragged into view
                                        // so it doesn't get obscured at the edge.
                                        editScrollTarget = cat.id
                                    },
                                    onDragEnd: {
                                        withAnimation(.spring(response: 0.35)) {
                                            activeCategoryId = nil
                                        }
                                    }
                                )
                                // .id() anchors enable ScrollViewReader.scrollTo()
                                .id(cat.id)
                            }
                        }
                        .padding(.horizontal, 2)
                        // Extra top padding so the live budget bubble has breathing
                        // room near the card's top edge.
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    }
                    // Respond to chip taps and drag-start auto-scroll.
                    // Reset to nil after scrolling so the same chip can re-trigger
                    // a scroll if the user has manually scrolled away.
                    .onChange(of: editScrollTarget) { _, target in
                        if let target {
                            withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
                                proxy.scrollTo(target, anchor: .center)
                            }
                            editScrollTarget = nil
                        }
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 14) {
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
                    .padding(.horizontal, 2)
                    .padding(.bottom, 4)
                }
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
        .alert(String(localized: "budget.error.title"), isPresented: $showConstraintModal) {
            Button(String(localized: "budget.error.adjustSaving")) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                    isEditingBudget  = false
                    activeCategoryId = nil
                }
            }
            
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(format: String(localized: "budget_constraint_alert_fmt"),
                        vm.savingGoal.toCompactCurrency()))
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
                    Text(String(localized: "ui.drag.expand"))
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
            Text(String(localized: "finance.spending"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VeloceTheme.textPrimary)
            Spacer()
            editBudgetButton
            editGroupsButton
        }
    }

    private var editHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Title row ─────────────────────────────────────────
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "budget.edit"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textPrimary)

                    // Remaining pool indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(remainingBudget < 0 ? VeloceTheme.over : VeloceTheme.ok)
                            .frame(width: 5, height: 5)
                        Text(remainingBudget < 0
                             ? String(format: String(localized: "edit_pool_over_fmt"), (-remainingBudget).toCompactCurrency())
                             : String(format: String(localized: "edit_pool_remaining_fmt"), remainingBudget.toCompactCurrency()))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(remainingBudget < 0
                                             ? VeloceTheme.over
                                             : VeloceTheme.textSecondary)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.25), value: remainingBudget)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                        isEditingBudget  = false
                        activeCategoryId = nil
                    }
                } label: {
                    Text(String(localized: "common.done"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VeloceTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(VeloceTheme.accentBg, in: Capsule())
                }
            }

            // ── Savings preview panel (visible when income is set) ─
            if vm.monthlyIncome > 0 {
                savingsPreviewPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Hint to set income
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text(String(localized: "settings.salary.hint"))
                        .font(.system(size: 11))
                }
                .foregroundStyle(VeloceTheme.textTertiary)
                .padding(8)
                .background(VeloceTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: vm.monthlyIncome > 0)
    }

    /// Live panel: income → saving target reserved → budget ceiling → allocated → remaining.
    /// When no saving target is set falls back to the simpler income → budget → savings view.
    private var savingsPreviewPanel: some View {
        let income      = vm.monthlyIncome
        let savingGoal  = vm.savingGoal
        let budget      = vm.totalBudget        // updates in real-time as user drags
        let hasSaving   = savingGoal > 0

        // With saving target: ceiling = income - savingGoal
        // Without:            ceiling = income (no reserved amount)
        let ceiling     = hasSaving ? max(0, income - savingGoal) : income
        let unallocated = ceiling - budget
        let isWithin    = budget <= ceiling

        // Ratio of allocated budget against total income (for the bar)
        let allocRatio    = income > 0 ? min(budget  / income, 1.0) : 0
        let ceilingRatio  = income > 0 ? min(ceiling / income, 1.0) : 1.0
        let savingsPct    = income > 0 ? savingGoal / income * 100 : 0

        return VStack(spacing: 10) {
            // ── Numbers row ───────────────────────────────────────
            HStack(alignment: .top, spacing: 0) {
                savingsColumn(
                    label: String(localized: "finance.income"),
                    value: income.toCompactCurrency(),
                    color: VeloceTheme.textSecondary
                )
                
                arrowSpacer()
                
                if hasSaving {
                    savingsColumn(
                        label: String(localized: "finance.reserved"),
                        value: savingGoal.toCompactCurrency(),
                        color: VeloceTheme.ok,
                        prefix: "-"
                    )
                    
                    arrowSpacer()
                    
                    savingsColumn(
                        label: String(localized: "finance.ceiling"),
                        value: ceiling.toCompactCurrency(),
                        color: isWithin ? VeloceTheme.textSecondary : VeloceTheme.over
                    )
                    
                    arrowSpacer()
                }
                
                savingsColumn(
                    label: String(localized: "finance.budget"),
                    value: budget.toCompactCurrency(),
                    color: VeloceTheme.accent,
                    animate: true
                )
                
                arrowSpacer()
                
                savingsColumn(
                    label: unallocated >= 0
                        ? String(localized: "finance.free")
                        : String(localized: "finance.over"),
                    value: abs(unallocated).toCompactCurrency(),
                    color: unallocated >= 0 ? VeloceTheme.ok : VeloceTheme.over,
                    prefix: unallocated >= 0 ? "+" : "-",
                    animate: true
                )
            }

            // ── Segmented bar: saving goal | allocated budget | free ──
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Full track
                    Capsule()
                        .fill(VeloceTheme.divider)
                        .frame(height: 7)

                    // Saving reserved portion (right end, rendered as remaining)
                    if hasSaving && ceilingRatio < 1.0 {
                        Capsule()
                            .fill(VeloceTheme.ok.opacity(0.30))
                            .frame(width: geo.size.width * CGFloat(1 - ceilingRatio), height: 7)
                            .offset(x: geo.size.width * CGFloat(ceilingRatio))
                    }

                    // Allocated budget
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isWithin
                                    ? [VeloceTheme.accent, VeloceTheme.accent.opacity(0.7)]
                                    : [VeloceTheme.caution, VeloceTheme.over],
                                startPoint: .leading,
                                endPoint:   .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(allocRatio), height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: allocRatio)
                }
            }
            .frame(height: 7)

            // ── Summary chip ──────────────────────────────────────
            HStack(spacing: 4) {
                if hasSaving {
                    Image(systemName: isWithin ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(isWithin
                         ? String(format: String(localized: "saving_target_reserved_pct_fmt"), savingsPct)
                         : String(format: String(localized: "budget_exceeds_ceiling_fmt"), (-unallocated).toCompactCurrency()))
                        .font(.system(size: 11, weight: .medium))
                } else {
                    let pct = income > 0 ? max(0, income - budget) / income * 100 : 0
                    Image(systemName: budget <= income ? "leaf.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(budget <= income
                         ? String(format: String(localized: "saving_income_pct_fmt"), pct)
                         : String(format: String(localized: "over_income_pct_fmt"), income > 0 ? (budget-income)/income*100 : 0))
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(isWithin ? VeloceTheme.ok : VeloceTheme.over)
            .contentTransition(.numericText())
            .animation(.spring(response: 0.25), value: isWithin)
        }
        .padding(10)
        .background(VeloceTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func savingsColumn(
        label: String,
        value: String,
        color: Color,
        prefix: String = "",
        animate: Bool = false
    ) -> some View {
        VStack(alignment: .center, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(VeloceTheme.textTertiary)

            HStack(spacing: 1) {
                if !prefix.isEmpty {
                    Text(prefix)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .if(animate) { $0.contentTransition(.numericText()) }
            }
            .foregroundStyle(color)
        }
    }
    
    private func arrowSpacer() -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(VeloceTheme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
    }

    // MARK: - Edit mode category navigation strip

    /// A horizontally scrolling row of category chips shown only during budget editing.
    /// Tapping a chip sets editScrollTarget, which the ScrollViewReader converts into a
    /// smooth programmatic scroll — letting the user jump between categories without
    /// pressing "Done" and re-entering edit mode.
    private var editCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.visibleCategories) { cat in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        editScrollTarget = cat.id
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(vm.categoryColor(for: cat))
                            Text(cat.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(VeloceTheme.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(VeloceTheme.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Edit Budget button (replaces the old Absolute/Relative toggle)

    private var editBudgetButton: some View {
        Button {
            // Use the saving-target ceiling as the budget pool.
            // This lets bars be dragged UP as long as the total stays within (salary − saving goal).
            // Falls back to 2× current total when no income is configured.
            let ceiling = vm.maxAllowedTotalBudget
            fixedTotalBudget = ceiling.isFinite
                ? max(ceiling, vm.totalBudget)   // at least current total; grows to ceiling
                : vm.totalBudget * 2             // no income set → generous headroom
            withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                isEditingBudget = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 11))
                Text(String(localized: "budget.edit"))
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
                Text(String(localized: "groups.title"))
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

    /// Applies a new budget for one category.
    /// Two constraints are enforced in order:
    ///   1. Total must not exceed `fixedTotalBudget` (the frozen pool on edit-mode entry).
    ///   2. Total must not exceed `salary - savingTarget` (the saving-target ceiling).
    /// If the saving target is the binding constraint, a modal is shown explaining why.
    private func applyBudget(_ newBudget: Double, for category: Category) {
        let othersTotal = vm.categories
            .filter { $0.id != category.id }
            .reduce(0) { $0 + $1.budget }

        // fixedTotalBudget is already set to max(savingCeiling, currentTotal) on entry,
        // so it IS the effective cap. No redundant min() needed.
        let maxAllowed = max(0, fixedTotalBudget - othersTotal)
        let clamped    = min(newBudget, maxAllowed)

        if newBudget > maxAllowed {
            // Blocked by the saving-target ceiling — explain why
            if vm.monthlyIncome > 0 {
                showConstraintModal = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        vm.updateBudget(categoryId: category.id, newBudget: clamped)
    }
}

// MARK: - Expense Timeline

private struct ExpenseTimeline: View {
    @EnvironmentObject var vm: ExpenseViewModel
    let isPro:         Bool
    let onEdit:        (Expense) -> Void
    var onUpgradeTap:  () -> Void = {}

    @State private var searchText        = ""
    @State private var filterCategoryId: UUID? = nil

    // 30-day cutoff for free users; nil means show everything (pro)
    private var historyCutoff: Date? {
        isPro ? nil
              : Calendar.current.date(byAdding: .day,
                                      value: -ExpenseViewModel.freeHistoryDays,
                                      to: Date())
    }

    // Number of expenses older than the free window (drives the upgrade banner)
    private var hiddenExpenseCount: Int {
        guard let cutoff = historyCutoff else { return 0 }
        return vm.expenses.filter { $0.date < cutoff }.count
    }

    private var filteredGroups: [ExpenseGroup] {
        let cutoff = historyCutoff
        let query  = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return vm.expenseGroups.compactMap { group in
            let filtered = group.items.filter { expense in
                let matchesSearch = query.isEmpty
                    || expense.title.lowercased().contains(query)
                    || expense.note.lowercased().contains(query)
                let matchesCategory = filterCategoryId == nil
                    || expense.categoryId == filterCategoryId
                let matchesWindow = cutoff == nil || expense.date >= cutoff!
                return matchesSearch && matchesCategory && matchesWindow
            }
            return filtered.isEmpty ? nil
                : ExpenseGroup(id: group.id, title: group.title, items: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if !vm.expenses.isEmpty {
                searchBar
                categoryFilterChips
            }
            LazyVStack(spacing: 20, pinnedViews: []) {
                if filteredGroups.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredGroups) { group in
                        DaySection(group: group, onEdit: onEdit)
                            .environmentObject(vm)
                    }
                }
            }
            // Upgrade nudge — only when older expenses are actually hidden
            if hiddenExpenseCount > 0 {
                freeHistoryBanner
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Free-tier history banner (tappable → paywall)

    private var freeHistoryBanner: some View {
        Button(action: onUpgradeTap) {
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 15))
                    .foregroundStyle(VeloceTheme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "history.last30days"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VeloceTheme.textSecondary)
                    Text(
                        String(
                            format: String(localized: "history.hidden_count_fmt"),
                            hiddenExpenseCount,
                            hiddenExpenseCount == 1 ? "" : "s"
                        )
                    )
                        .font(.system(size: 11))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                    Text(String(localized: "subscription.pro"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(VeloceTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(VeloceTheme.accentBg, in: Capsule())
            }
            .padding(12)
            .background(VeloceTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(VeloceTheme.accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(searchText.isEmpty ? VeloceTheme.textTertiary : VeloceTheme.accent)
            TextField(String(localized: "search.expenses.placeholder"), text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(VeloceTheme.textPrimary)
                .tint(VeloceTheme.accent)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(VeloceTheme.textTertiary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VeloceTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        .animation(.easeInOut(duration: 0.15), value: searchText.isEmpty)
    }

    // MARK: - Category filter chips

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All chip
                Button {
                    withAnimation(.spring(response: 0.25)) { filterCategoryId = nil }
                } label: {
                    Text(String(localized: "common.all"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(filterCategoryId == nil ? .white : VeloceTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            filterCategoryId == nil ? VeloceTheme.accent : VeloceTheme.surface,
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(
                            filterCategoryId == nil ? Color.clear : VeloceTheme.divider,
                            lineWidth: 1
                        ))
                }

                // Only categories that have at least one recorded expense
                ForEach(vm.categories.filter { cat in
                    vm.expenses.contains { $0.categoryId == cat.id }
                }) { cat in
                    let col        = Color(hex: cat.colorHex)
                    let isSelected = filterCategoryId == cat.id
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            filterCategoryId = isSelected ? nil : cat.id
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 10))
                            Text(cat.name)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(isSelected ? col : VeloceTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ? col.opacity(0.15) : VeloceTheme.surface,
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(
                            isSelected ? col.opacity(0.4) : VeloceTheme.divider,
                            lineWidth: 1
                        ))
                    }
                    .animation(.spring(response: 0.2), value: isSelected)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        let isFiltering = !searchText.isEmpty || filterCategoryId != nil
        return VStack(spacing: 14) {
            Image(systemName: isFiltering ? "magnifyingglass" : "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(VeloceTheme.textTertiary)
            Text(
                isFiltering
                ? String(localized: "empty.search.no_results")
                : String(localized: "empty.expense.none")
            )

                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VeloceTheme.textSecondary)
            Text(
                isFiltering
                ? String(localized: "empty.search.try_again")
                : String(localized: "empty.expense.suggestion")
            )
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

// MARK: - Notification Denied Banner

private struct NotificationDeniedBanner: View {
    @EnvironmentObject var notifMgr: NotificationManager

    var body: some View {
        if notifMgr.authStatus == .denied {
            Button(action: { notifMgr.openSystemSettings() }) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(VeloceTheme.over)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "notifications.disabled"))

                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VeloceTheme.textPrimary)
                        Text(String(localized: "notifications.enable_hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(VeloceTheme.textSecondary)
                    }
                    Spacer()
                    Text(String(localized: "common.enable"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VeloceTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(VeloceTheme.accentBg, in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(VeloceTheme.over.opacity(0.06))
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
        .environmentObject(ExpenseViewModel())
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(NotificationManager.shared)
        .environmentObject(RatingManager.shared)
}
