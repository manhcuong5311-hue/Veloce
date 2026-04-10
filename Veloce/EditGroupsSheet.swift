import SwiftUI

// MARK: - Edit Groups Sheet

struct EditGroupsSheet: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VeloceTheme.bg.ignoresSafeArea()

                List {
                    Section {
                        ForEach(vm.categories) { cat in
                            GroupRow(category: cat)
                                .environmentObject(vm)
                                .listRowBackground(VeloceTheme.surface)
                                .listRowSeparatorTint(VeloceTheme.divider)
                        }
                        .onMove { vm.reorderCategories(from: $0, to: $1) }
                    } header: {
                        Text("Drag to reorder · tap eye to show/hide")
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
    }
}

// MARK: - Group Row

private struct GroupRow: View {
    @EnvironmentObject var vm: ExpenseViewModel
    let category: Category

    var body: some View {
        HStack(spacing: 14) {
            // Category icon
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

// MARK: - Preview

#Preview {
    EditGroupsSheet()
        .environmentObject(ExpenseViewModel())
}
