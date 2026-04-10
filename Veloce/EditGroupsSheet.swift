import SwiftUI

// MARK: - Edit Groups Sheet

struct EditGroupsSheet: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editingCategory: Category? = nil

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
                        Text("Drag to reorder  ·  tap ✏️ to edit limit & color")
                            .font(.system(size: 11))
                            .foregroundStyle(VeloceTheme.textTertiary)
                            .textCase(nil)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle("Edit Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VeloceTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
        .sheet(item: $editingCategory) { cat in
            GroupEditSheet(category: cat)
                .environmentObject(vm)
        }
    }
}

// MARK: - Group Row

private struct GroupRow: View {
    @EnvironmentObject var vm: ExpenseViewModel
    let category: Category
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: category.colorHex).opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: category.colorHex))
            }

            // Name + budget
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(category.isHidden
                                     ? VeloceTheme.textTertiary
                                     : VeloceTheme.textPrimary)
                Text("\(category.spent.toCompactCurrency()) of \(category.budget.toCompactCurrency())")
                    .font(.system(size: 12))
                    .foregroundStyle(VeloceTheme.textTertiary)
            }

            Spacer()

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(VeloceTheme.accent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            // Visibility toggle
            Button(action: { vm.toggleCategoryVisibility(id: category.id) }) {
                Image(systemName: category.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(category.isHidden
                                     ? VeloceTheme.textTertiary
                                     : VeloceTheme.accent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .opacity(category.isHidden ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: category.isHidden)
    }
}

// MARK: - Group Edit Sheet

private struct GroupEditSheet: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    let category: Category

    @State private var selectedColorHex: String
    @State private var budgetText: String

    init(category: Category) {
        self.category = category
        _selectedColorHex = State(initialValue: category.colorHex.uppercased())
        _budgetText       = State(initialValue: "\(Int(category.budget))")
    }

    // MARK: - Presets

    private let presetColors: [String] = [
        "E07A5F", "E8945A", "D4A853", "7BAF5B",
        "5BA88C", "4B9FA8", "5B8DB8", "7B6CF0",
        "9B84D0", "C97BA8", "E86B8B", "8A95A8"
    ]

    private let budgetPresets: [(label: String, value: Double)] = [
        ("500K",   500_000),
        ("1 tr",   1_000_000),
        ("1.5 tr", 1_500_000),
        ("2 tr",   2_000_000),
        ("3 tr",   3_000_000),
        ("5 tr",   5_000_000),
        ("10 tr",  10_000_000),
    ]

    private var parsedBudget: Double? {
        Double(budgetText.filter { $0.isNumber })
    }

    private var isValid: Bool { (parsedBudget ?? 0) > 0 }

    // MARK: - Body

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
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VeloceTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VeloceTheme.bg)
        .preferredColorScheme(.light)
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: selectedColorHex).opacity(0.14))
                    .frame(width: 60, height: 60)
                Image(systemName: category.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color(hex: selectedColorHex))
            }
            .animation(.spring(response: 0.3), value: selectedColorHex)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(VeloceTheme.textPrimary)
                Text("Set a spending limit and pick a color")
                    .font(.system(size: 13))
                    .foregroundStyle(VeloceTheme.textSecondary)
            }
            Spacer()
        }
        .veloceCard()
    }

    // MARK: - Budget Section

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Spending Limit")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VeloceTheme.textSecondary)

            // Preset chips grid (4 per row)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(budgetPresets, id: \.label) { preset in
                    let isSelected = parsedBudget == preset.value
                    Button {
                        budgetText = "\(Int(preset.value))"
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : VeloceTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(isSelected
                                          ? VeloceTheme.accent
                                          : VeloceTheme.surfaceRaised)
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

            // Custom amount input
            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(VeloceTheme.textTertiary)

                TextField("Custom amount", text: $budgetText)
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

                Text("₫")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VeloceTheme.textTertiary)
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

    // MARK: - Color Section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Color")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VeloceTheme.textSecondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                spacing: 10
            ) {
                ForEach(presetColors, id: \.self) { hex in
                    let isSelected = selectedColorHex.uppercased() == hex.uppercased()
                    Button {
                        selectedColorHex = hex.uppercased()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: hex))
                            if isSelected {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 3)
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
        }
        .veloceCard()
    }

    // MARK: - Save

    private var saveButton: some View {
        Button(action: save) {
            Text("Save Changes")
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
        var updated        = category
        updated.budget     = budget
        updated.colorHex   = selectedColorHex
        vm.updateCategory(updated)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    EditGroupsSheet()
        .environmentObject(ExpenseViewModel())
}
