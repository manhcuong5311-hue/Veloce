import SwiftUI

// MARK: - Edit Groups Sheet

struct EditGroupsSheet: View {
    @EnvironmentObject var vm:         ExpenseViewModel
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var editingCategory: Category? = nil
    @State private var showAddGroup:    Bool       = false
    @State private var showPaywall:     Bool       = false

    private var isAtFreeLimit: Bool {
        !subManager.isProUser && vm.categories.count >= ExpenseViewModel.freeCategoryLimit
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                List {
                    Section {
                        ForEach(vm.categories) { cat in
                            GroupRow(category: cat, onEdit: { editingCategory = cat })
                                .environmentObject(vm)
                                .listRowBackground(VeloceTheme.surface)
                                .listRowSeparatorTint(VeloceTheme.divider)
                        }
                        .onMove { vm.reorderCategories(from: $0, to: $1) }
                    } header: {
                        Text(String(localized: "groups.reorder_hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(VeloceTheme.textTertiary)
                            .textCase(nil)
                    } footer: {
                        if !subManager.isProUser {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill").font(.system(size: 10))
                                Text(String(localized: "groups.free_limit",
                                            defaultValue: "Free plan: \(vm.categories.count)/\(ExpenseViewModel.freeCategoryLimit) groups · Upgrade for unlimited"))

                            }
                            .font(.system(size: 11))
                            .foregroundStyle(VeloceTheme.textTertiary)
                        }
                    }

                    // Add Group button row
                    Section {
                        Button(action: handleAddGroup) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(VeloceTheme.accentBg)
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(VeloceTheme.accent)
                                }
                                Text(String(localized: "groups.new"))

                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(VeloceTheme.accent)
                                Spacer()
                                if isAtFreeLimit {
                                    HStack(spacing: 3) {
                                        Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                                        Text(String(localized: "common.pro"))
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundStyle(VeloceTheme.accent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(VeloceTheme.accentBg, in: Capsule())
                                }
                            }
                        }
                        .listRowBackground(VeloceTheme.surface)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle(String(localized: "groups.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
                        dismiss()
                    }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .adaptiveSheet(item: $editingCategory) { cat in
            GroupEditSheet(category: cat)
                .environmentObject(vm)
                .environmentObject(subManager)
        }
        .adaptiveSheet(isPresented: $showAddGroup) {
            NewGroupSheet()
                .environmentObject(vm)
                .environmentObject(subManager)
        }
        .adaptiveSheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subManager)
        }
    }

    private func handleAddGroup() {
        if isAtFreeLimit {
            showPaywall = true
        } else {
            showAddGroup = true
        }
    }
}

// MARK: - Group Row

private struct GroupRow: View {
    @EnvironmentObject var vm: ExpenseViewModel
    let category: Category
    let onEdit: () -> Void

    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: category.colorHex).opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: category.colorHex))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(category.isHidden ? VeloceTheme.textTertiary : VeloceTheme.textPrimary)
                Text("\(category.spent.toCompactCurrency()) of \(category.budget.toCompactCurrency())")
                    .font(.system(size: 12))
                    .foregroundStyle(VeloceTheme.textTertiary)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(VeloceTheme.accent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button(action: { vm.toggleCategoryVisibility(id: category.id) }) {
                Image(systemName: category.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(category.isHidden ? VeloceTheme.textTertiary : VeloceTheme.accent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button(action: { confirmingDelete = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                String(localized: "groups.delete.confirm_title", defaultValue: "Delete \"\(category.name)\"?"),
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button(String(localized: "groups.delete.action"), role: .destructive) {
                    vm.deleteCategory(id: category.id)
                }
            } message: {
                Text(String(localized: "groups.delete.message"))
            }
        }
        .padding(.vertical, 4)
        .opacity(category.isHidden ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: category.isHidden)
    }
}

// MARK: - Group Edit Sheet

private struct GroupEditSheet: View {
    @EnvironmentObject var vm:         ExpenseViewModel
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let category: Category

    @State private var selectedColorHex: String
    @State private var selectedIcon:     String
    @State private var budgetText:       String
    @State private var showIconPicker    = false
    @State private var showPaywall       = false
    // FIX: backing state for the native ColorPicker — kept in sync with
    // selectedColorHex so the picker always reflects the active colour.
    @State private var customColor: Color

    init(category: Category) {
        self.category     = category
        _selectedColorHex = State(initialValue: category.colorHex.uppercased())
        _selectedIcon     = State(initialValue: category.icon)
        _budgetText       = State(initialValue: "\(Int(category.budget))")
        _customColor      = State(initialValue: Color(hex: category.colorHex))
    }

    private let presetColors: [String] = [
        "E07A5F", "E8945A", "D4A853", "7BAF5B",
        "5BA88C", "4B9FA8", "5B8DB8", "7B6CF0",
        "9B84D0", "C97BA8", "E86B8B", "8A95A8"
    ]

    private var budgetPresets: [(label: String, value: Double)] {
        AppCurrency.current.budgetPresets
    }

    private var parsedBudget: Double? { Double(budgetText.filter { $0.isNumber }) }
    private var isValid: Bool { (parsedBudget ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerCard
                        budgetSection
                        colorSection
                        saveButton
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(String(localized: "edit_group_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "cancel")) { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .adaptiveSheet(isPresented: $showIconPicker) {
            IconPickerSheet(selectedIcon: $selectedIcon)
        }
        .adaptiveSheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subManager)
        }
    }

    // MARK: - Header (icon tap → picker for Pro, paywall for Free)

    private var headerCard: some View {
        HStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if subManager.isProUser {
                    showIconPicker = true
                } else {
                    showPaywall = true
                }
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color(hex: selectedColorHex).opacity(0.14))
                        .frame(width: 64, height: 64)

                    Image(systemName: selectedIcon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color(hex: selectedColorHex))
                        .frame(width: 64, height: 64)
                        // Dim slightly when locked
                        .opacity(subManager.isProUser ? 1.0 : 0.55)

                    // Badge: pencil for Pro, lock for Free
                    ZStack {
                        Circle()
                            .fill(subManager.isProUser ? VeloceTheme.accent : VeloceTheme.textSecondary)
                            .frame(width: 20, height: 20)
                        Image(systemName: subManager.isProUser ? "pencil" : "lock.fill")
                            .font(.system(size: subManager.isProUser ? 10 : 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.28), value: selectedColorHex)
            .animation(.spring(response: 0.28), value: selectedIcon)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(VeloceTheme.textPrimary)

                if subManager.isProUser {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.tap.fill").font(.system(size: 10))
                        Text(String(localized: "tap_icon_customize"))
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(VeloceTheme.accent.opacity(0.8))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.system(size: 9))
                        Text(String(localized: "premium_unlock_icon_color"))
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
            Spacer()
        }
        .veloceCard()
    }

    // MARK: - Budget Section

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "spending_limit"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VeloceTheme.textSecondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(budgetPresets, id: \.label) { preset in
                    let isSelected = parsedBudget == preset.value
                    Button { budgetText = "\(Int(preset.value))" } label: {
                        Text(preset.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : VeloceTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(isSelected ? VeloceTheme.accent : VeloceTheme.surfaceRaised)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(
                                                isSelected ? VeloceTheme.accent : VeloceTheme.divider,
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.2), value: isSelected)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(VeloceTheme.textTertiary)
                TextField(String(localized: "custom_amount_placeholder"), text: $budgetText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(VeloceTheme.textPrimary)
                    .tint(VeloceTheme.accent)
                if let val = parsedBudget, val > 0 {
                    Text(val.toCompactCurrency())
                        .font(.system(size: 13))
                        .foregroundStyle(VeloceTheme.textTertiary)
                        .transition(.opacity)
                }
                Text(AppCurrency.current.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(VeloceTheme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(VeloceTheme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(VeloceTheme.accent.opacity(0.35), lineWidth: 1.5)
                    )
            )
            .animation(.spring(response: 0.25), value: parsedBudget)
        }
        .veloceCard()
    }

    // MARK: - Color Section (locked for Free users)

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row with Premium badge when locked
            HStack {
                Text(String(localized: "color"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VeloceTheme.textSecondary)
                Spacer()
                if !subManager.isProUser {
                    Button(action: { showPaywall = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                            Text(String(localized: "premium"))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(VeloceTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(VeloceTheme.accentBg, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Color grid — interactive for Pro, blurred + locked for Free
            ZStack {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                    spacing: 10
                ) {
                    ForEach(presetColors, id: \.self) { hex in
                        let isSelected = selectedColorHex.uppercased() == hex.uppercased()
                        Button {
                            guard subManager.isProUser else { return }
                            selectedColorHex = hex.uppercased()
                            // FIX: keep the native ColorPicker in sync with the preset choice
                            // so it shows the correct colour when the user opens it next.
                            customColor = Color(hex: hex)
                        } label: {
                            ZStack {
                                Circle().fill(Color(hex: hex))
                                if isSelected {
                                    Circle().strokeBorder(.white, lineWidth: 3)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.2), value: isSelected)
                    }
                }
                .blur(radius: subManager.isProUser ? 0 : 3)
                .opacity(subManager.isProUser ? 1.0 : 0.35)
                .allowsHitTesting(subManager.isProUser)

                // Locked overlay tap target
                if !subManager.isProUser {
                    Button(action: { showPaywall = true }) {
                        Color.clear
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // FIX: Custom colour picker for Pro users — placed below the preset grid.
            // Uses the native SwiftUI ColorPicker (HSB wheel + hex input on iOS).
            // onChange converts the picked Color → 6-char hex and updates selectedColorHex
            // so all downstream views (header circle, save button, etc.) stay consistent.
            // Not shown for free users to avoid UI clutter when the feature is locked.
            if subManager.isProUser {
                Divider()
                    .padding(.top, 4)
                HStack {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 13))
                        .foregroundStyle(VeloceTheme.textSecondary)
                    Text(String(localized: "custom"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VeloceTheme.textSecondary)
                    Spacer()
                    ColorPicker("", selection: $customColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: customColor) { _, newColor in
                            // Convert Color → hex and propagate to selectedColorHex.
                            // This deselects all presets (no checkmark) — expected behaviour.
                            selectedColorHex = newColor.toHex()
                        }
                }
            }
        }
        .veloceCard()
    }

    // MARK: - Save

    private var saveButton: some View {
        Button(action: save) {
            Text(String(localized: "save_changes"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isValid ? VeloceTheme.accent : VeloceTheme.divider)
                )
        }
        .disabled(!isValid)
        .animation(.easeInOut(duration: 0.2), value: isValid)
    }

    private func save() {
        guard isValid, let budget = parsedBudget else { return }
        var updated      = category
        updated.budget   = budget
        // Only persist icon/color if Pro; otherwise keep the originals
        updated.colorHex = subManager.isProUser ? selectedColorHex : category.colorHex
        updated.icon     = subManager.isProUser ? selectedIcon      : category.icon
        vm.updateCategory(updated)
        dismiss()
    }
}

// MARK: - New Group Sheet

private struct NewGroupSheet: View {
    @EnvironmentObject var vm:         ExpenseViewModel
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var name       = ""
    @State private var budgetText = AppCurrency.current.defaultBudgetText
    @State private var selectedColorHex = "7B6CF0"
    @State private var selectedIcon     = "folder.fill"
    @State private var showIconPicker   = false
    // FIX: backing state for the native ColorPicker (same pattern as GroupEditSheet)
    @State private var customColor: Color = Color(hex: "7B6CF0")

    private let presetColors: [String] = [
        "E07A5F", "E8945A", "D4A853", "7BAF5B",
        "5BA88C", "4B9FA8", "5B8DB8", "7B6CF0",
        "9B84D0", "C97BA8", "E86B8B", "8A95A8"
    ]

    private var parsedBudget: Double? { Double(budgetText.filter { $0.isNumber }) }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (parsedBudget ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Icon + name
                        VStack(spacing: 14) {
                            Button { showIconPicker = true } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: selectedColorHex).opacity(0.14))
                                        .frame(width: 68, height: 68)
                                    Image(systemName: selectedIcon)
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundStyle(Color(hex: selectedColorHex))
                                }
                            }
                            .buttonStyle(.plain)

                            TextField(String(localized: "group_name_placeholder"), text: $name)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(VeloceTheme.textPrimary)
                                .multilineTextAlignment(.center)
                                .tint(VeloceTheme.accent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .veloceCard()

                        // Budget
                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "monthly_budget"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(VeloceTheme.textSecondary)
                            HStack {
                                Image(systemName: "pencil").foregroundStyle(VeloceTheme.textTertiary)
                                TextField(String(localized: "amount_placeholder"), text: $budgetText)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(VeloceTheme.textPrimary)
                                    .tint(VeloceTheme.accent)
                                    .onChange(of: budgetText) { _, v in
                                        let d = v.filter { $0.isNumber }
                                        if d != budgetText { budgetText = d }
                                    }
                                if let b = parsedBudget, b > 0 {
                                    Text(b.toCompactCurrency())
                                        .font(.system(size: 13))
                                        .foregroundStyle(VeloceTheme.textTertiary)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(VeloceTheme.surfaceRaised)
                                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(VeloceTheme.accent.opacity(0.35), lineWidth: 1.5))
                            )
                        }
                        .veloceCard()

                        // Color picker (Pro only for full grid; everyone gets a color)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(localized: "color"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(VeloceTheme.textSecondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                                ForEach(presetColors, id: \.self) { hex in
                                    let sel = selectedColorHex.uppercased() == hex.uppercased()
                                    Button {
                                        selectedColorHex = hex
                                        // FIX: keep the native picker in sync when a preset is chosen
                                        customColor = Color(hex: hex)
                                    } label: {
                                        ZStack {
                                            Circle().fill(Color(hex: hex))
                                            if sel {
                                                Circle().strokeBorder(.white, lineWidth: 3)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // FIX: Custom colour picker available to all users in NewGroupSheet
                            // (no Pro gate — group creation doesn't gatekeep colour choice).
                            Divider()
                                .padding(.top, 4)
                            HStack {
                                Image(systemName: "eyedropper")
                                    .font(.system(size: 13))
                                    .foregroundStyle(VeloceTheme.textSecondary)
                                Text(String(localized: "custom"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(VeloceTheme.textSecondary)
                                Spacer()
                                ColorPicker("", selection: $customColor, supportsOpacity: false)
                                    .labelsHidden()
                                    .onChange(of: customColor) { _, newColor in
                                        // Propagate custom pick to selectedColorHex and
                                        // deselect all presets visually.
                                        selectedColorHex = newColor.toHex()
                                    }
                            }
                        }
                        .veloceCard()

                        Button(action: save) {
                            Text(String(localized: "create_group"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isValid ? VeloceTheme.accent : VeloceTheme.divider)
                                )
                        }
                        .disabled(!isValid)
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(String(localized: "new_group_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "cancel")) { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .adaptiveSheet(isPresented: $showIconPicker) {
            IconPickerSheet(selectedIcon: $selectedIcon)
        }
    }

    private func save() {
        guard isValid, let budget = parsedBudget else { return }
        let newCat = Category(
            name:     name.trimmingCharacters(in: .whitespaces),
            icon:     selectedIcon,
            budget:   budget,
            colorHex: selectedColorHex
        )
        print("[NewGroupSheet] save() — creating '\(newCat.name)'")
        // addCategory() appends with animation AND synchronously commits to disk
        // before this function returns — safe against an immediate force-kill.
        vm.addCategory(newCat)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    EditGroupsSheet()
        .environmentObject(ExpenseViewModel())
        .environmentObject(SubscriptionManager.shared)
}
