// VeloceWidget.swift
// WidgetKit extension — displays remaining budget on the home screen / lock screen.
//
// Setup checklist (do once in Xcode):
//   1. File → New → Target → Widget Extension → name it "VeloceWidget".
//   2. Signing & Capabilities: add App Group "group.com.veloce.shared" to BOTH
//      the main Veloce target AND the VeloceWidget target.
//   3. Add this file to the VeloceWidget target (not the main app target).
//      Also add VeloceWidgetData (from PersistenceStore.swift) — easiest via a
//      shared Swift Package or by duplicating the struct in a shared file.
//   4. Build & run.

import WidgetKit
import SwiftUI

// MARK: - Shared data model (mirror of PersistenceStore.VeloceWidgetData)
// Keep in sync with the struct in PersistenceStore.swift.

private struct VeloceWidgetData: Codable {
    let totalBudget: Double
    let totalSpent:  Double
    let currency:    String
    let updatedAt:   Date

    var remaining: Double { totalBudget - totalSpent }
    var ratio:     Double { totalBudget > 0 ? min(totalSpent / totalBudget, 1) : 0 }
}

// MARK: - Timeline Entry

private struct VeloceEntry: TimelineEntry {
    let date:   Date
    let data:   VeloceWidgetData?
}

// MARK: - Timeline Provider

private struct VeloceProvider: TimelineProvider {

    // App Group shared container
    private let appGroupID = "group.com.veloce.shared"

    func placeholder(in context: Context) -> VeloceEntry {
        VeloceEntry(date: Date(), data: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (VeloceEntry) -> Void) {
        completion(VeloceEntry(date: Date(), data: loadWidgetData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VeloceEntry>) -> Void) {
        let entry    = VeloceEntry(date: Date(), data: loadWidgetData())
        // Refresh every 15 minutes in case the user switches apps mid-session.
        let nextDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextDate))
        completion(timeline)
    }

    // MARK: Private

    private func loadWidgetData() -> VeloceWidgetData? {
        guard
            let url  = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
                .appendingPathComponent("veloce_widget_data.json"),
            FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(VeloceWidgetData.self, from: data)
    }
}

// MARK: - Currency formatting (standalone — no app-side code imported)

private func currencySymbol(for code: String) -> String {
    switch code {
    case "VND": return "₫"
    case "USD": return "$"
    case "EUR": return "€"
    case "JPY": return "¥"
    case "GBP": return "£"
    case "KRW": return "₩"
    case "SGD": return "S$"
    case "THB": return "฿"
    default:    return code
    }
}

private func formatAmount(_ amount: Double, currency: String) -> String {
    let sym = currencySymbol(for: currency)
    if currency == "VND" || currency == "KRW" || currency == "JPY" {
        let v = Int(amount.rounded())
        // Compact formatting for large VND amounts
        if abs(v) >= 1_000_000 {
            let m = Double(v) / 1_000_000
            return "\(sym)\(String(format: m == m.rounded() ? "%.0f" : "%.1f", m))M"
        }
        if abs(v) >= 1_000 {
            return "\(sym)\(v / 1_000)K"
        }
        return "\(sym)\(v)"
    }
    return String(format: "\(sym)%.2f", amount)
}

// MARK: - Small Widget View

private struct SmallWidgetView: View {

    let entry: VeloceEntry

    private var data: VeloceWidgetData? { entry.data }

    var body: some View {
        if let d = data {
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: "v.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor(ratio: d.ratio))
                    Text("Veloce")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Remaining amount (hero)
                let remaining = d.remaining
                Text(formatAmount(remaining, currency: d.currency))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(remaining >= 0 ? .primary : .red)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("remaining")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemFill))
                            .frame(height: 5)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(accentColor(ratio: d.ratio))
                            .frame(width: max(0, geo.size.width * (1 - d.ratio)), height: 5)
                    }
                }
                .frame(height: 5)

                // Spent / Budget
                Text("\(formatAmount(d.totalSpent, currency: d.currency)) of \(formatAmount(d.totalBudget, currency: d.currency))")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(14)
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "v.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Open Veloce\nto load data")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Medium Widget View

private struct MediumWidgetView: View {

    let entry: VeloceEntry

    private var data: VeloceWidgetData? { entry.data }

    var body: some View {
        if let d = data {
            HStack(spacing: 0) {
                // Left: remaining hero
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "v.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accentColor(ratio: d.ratio))
                        Text("Veloce")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    let remaining = d.remaining
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatAmount(remaining, currency: d.currency))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(remaining >= 0 ? .primary : .red)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)

                        Text("remaining this month")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.systemFill))
                                .frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(accentColor(ratio: d.ratio))
                                .frame(width: max(0, geo.size.width * (1 - d.ratio)), height: 5)
                        }
                    }
                    .frame(height: 5)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Divider
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 0.5)
                    .padding(.vertical, 12)

                // Right: stats
                VStack(spacing: 0) {
                    statRow(label: "Budget",  value: formatAmount(d.totalBudget, currency: d.currency))
                    Divider().padding(.horizontal, 12)
                    statRow(label: "Spent",   value: formatAmount(d.totalSpent,  currency: d.currency))
                    Divider().padding(.horizontal, 12)
                    statRow(label: "Usage",   value: "\(Int(d.ratio * 100))%")
                }
                .frame(maxWidth: 130)
                .padding(.vertical, 12)
            }
        } else {
            SmallWidgetView(entry: entry)
        }
    }

    private func statRow(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Color helper (shared)

private func accentColor(ratio: Double) -> Color {
    switch ratio {
    case ..<0.75: return Color(red: 0.24, green: 0.71, blue: 0.55) // green
    case ..<1.0:  return Color(red: 0.93, green: 0.71, blue: 0.20) // amber
    default:      return Color(red: 0.92, green: 0.32, blue: 0.32) // red
}
}

// MARK: - Widget Entry View (dispatches to size-specific layouts)

private struct VeloceWidgetEntryView: View {

    @Environment(\.widgetFamily) private var family
    let entry: VeloceEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        case .systemMedium:
            MediumWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        default:
            SmallWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
    }
}

// MARK: - Widget Declaration

@main
struct VeloceWidget: Widget {

    let kind = "VeloceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VeloceProvider()) { entry in
            VeloceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Veloce Budget")
        .description("See your remaining monthly budget at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    VeloceWidget()
} timeline: {
    VeloceEntry(date: .now, data: VeloceWidgetData(
        totalBudget: 11_500_000,
        totalSpent:   7_200_000,
        currency:    "VND",
        updatedAt:   .now
    ))
    VeloceEntry(date: .now, data: VeloceWidgetData(
        totalBudget: 11_500_000,
        totalSpent:  11_800_000,
        currency:    "VND",
        updatedAt:   .now
    ))
}
