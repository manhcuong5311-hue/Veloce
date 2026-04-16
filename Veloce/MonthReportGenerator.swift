import UIKit
import SwiftUI

// MARK: - Month Report Generator
//
// Builds a one-page A4 PDF summarising the current month's budget performance.
// Uses UIGraphicsPDFRenderer (no external dependencies).
//
// Usage:
//   if let url = MonthReportGenerator.generate(vm: vm) {
//       // present ShareSheet(activityItems: [url])
//   }

enum MonthReportGenerator {

    // MARK: - Public entry point

    static func generate(vm: ExpenseViewModel) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)   // A4 72dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let currency = AppCurrency.current

        // Snapshot data on caller's thread (main).
        let totalBudget  = vm.totalBudget
        let totalSpent   = vm.totalSpent
        let remaining    = totalBudget - totalSpent
        let savingRate   = vm.monthlyIncome > 0
            ? max(0, (vm.monthlyIncome - totalSpent) / vm.monthlyIncome * 100)
            : 0
        let categories   = vm.visibleCategories
        let monthLabel   = monthYearLabel()
        let generatedOn  = formattedDate(Date())

        let fileName = "veloce_report_\(isoMonthTag()).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                let cgCtx = ctx.cgContext
                var y: CGFloat = 0

                y = drawHeader(cgCtx, pageRect: pageRect, monthLabel: monthLabel)
                y = drawSummaryCards(cgCtx, y: y, pageRect: pageRect,
                                     budget: totalBudget, spent: totalSpent,
                                     remaining: remaining, savingRate: savingRate,
                                     currency: currency)
                y = drawCategoryTable(cgCtx, y: y, pageRect: pageRect,
                                      categories: categories, currency: currency)
                drawFooter(cgCtx, pageRect: pageRect, generatedOn: generatedOn)
            }
        } catch {
            print("[MonthReportGenerator] PDF write error: \(error)")
            return nil
        }

        return url
    }

    // MARK: - Header

    @discardableResult
    private static func drawHeader(_ ctx: CGContext, pageRect: CGRect, monthLabel: String) -> CGFloat {
        let margin: CGFloat = 40
        var y: CGFloat = margin

        // Gradient banner background
        let bannerRect = CGRect(x: 0, y: 0, width: pageRect.width, height: 100)
        let colors = [
            UIColor(red: 0.19, green: 0.53, blue: 0.93, alpha: 1).cgColor,
            UIColor(red: 0.44, green: 0.27, blue: 0.90, alpha: 1).cgColor
        ]
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0, 1]
        )!
        ctx.saveGState()
        ctx.clip(to: bannerRect)
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: 0),
                               end:   CGPoint(x: pageRect.width, y: 0),
                               options: [])
        ctx.restoreGState()

        // App name
        let appAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        "Veloce".draw(at: CGPoint(x: margin, y: 28), withAttributes: appAttrs)

        // Month label
        let monthAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85)
        ]
        "Month in Review · \(monthLabel)".draw(at: CGPoint(x: margin, y: 56), withAttributes: monthAttrs)

        y = 120
        return y
    }

    // MARK: - Summary Cards

    @discardableResult
    private static func drawSummaryCards(_ ctx: CGContext, y: CGFloat, pageRect: CGRect,
                                         budget: Double, spent: Double, remaining: Double,
                                         savingRate: Double, currency: AppCurrency) -> CGFloat {
        let margin: CGFloat     = 40
        let cardW: CGFloat      = (pageRect.width - margin * 2 - 12) / 2
        let cardH: CGFloat      = 72
        let cards: [(String, String, UIColor)] = [
            ("Total Budget",  format(budget,    currency: currency), UIColor(red: 0.19, green: 0.53, blue: 0.93, alpha: 1)),
            ("Total Spent",   format(spent,     currency: currency), UIColor(red: 0.92, green: 0.32, blue: 0.32, alpha: 1)),
            ("Remaining",     format(remaining, currency: currency), remaining >= 0
                ? UIColor(red: 0.24, green: 0.71, blue: 0.55, alpha: 1)
                : UIColor(red: 0.92, green: 0.32, blue: 0.32, alpha: 1)),
            ("Saving Rate",   String(format: "%.1f%%", savingRate),  UIColor(red: 0.93, green: 0.71, blue: 0.20, alpha: 1)),
        ]

        let curY = y + 12
        for (i, (title, value, color)) in cards.enumerated() {
            let col  = i % 2
            let row  = i / 2
            let x    = margin + CGFloat(col) * (cardW + 12)
            let rect = CGRect(x: x, y: curY + CGFloat(row) * (cardH + 10), width: cardW, height: cardH)

            // Card background
            ctx.saveGState()
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 10).cgPath
            ctx.addPath(path)
            ctx.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
            ctx.fillPath()

            // Accent left strip
            let strip = CGRect(x: rect.minX, y: rect.minY, width: 4, height: rect.height)
            let stripPath = UIBezierPath(roundedRect: strip,
                                         byRoundingCorners: [.topLeft, .bottomLeft],
                                         cornerRadii: CGSize(width: 10, height: 10)).cgPath
            ctx.addPath(stripPath)
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor.secondaryLabel
            ]
            title.draw(at: CGPoint(x: rect.minX + 16, y: rect.minY + 14), withAttributes: titleAttrs)

            // Value
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: color
            ]
            value.draw(at: CGPoint(x: rect.minX + 16, y: rect.minY + 32), withAttributes: valueAttrs)
        }

        return curY + CGFloat((cards.count + 1) / 2) * (cardH + 10) + 16
    }

    // MARK: - Category Table

    @discardableResult
    private static func drawCategoryTable(_ ctx: CGContext, y: CGFloat, pageRect: CGRect,
                                          categories: [Category], currency: AppCurrency) -> CGFloat {
        let margin: CGFloat = 40
        var curY            = y + 8

        // Section heading
        let headAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        "Category Breakdown".draw(at: CGPoint(x: margin, y: curY), withAttributes: headAttrs)
        curY += 22

        // Column widths
        let nameW:  CGFloat = 160
        let numW:   CGFloat = (pageRect.width - margin * 2 - nameW) / 3

        // Table header
        let colAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let headerY = curY
        "Category".draw(at: CGPoint(x: margin,              y: headerY), withAttributes: colAttrs)
        "Budget".draw(  at: CGPoint(x: margin + nameW,       y: headerY), withAttributes: colAttrs)
        "Spent".draw(   at: CGPoint(x: margin + nameW + numW, y: headerY), withAttributes: colAttrs)
        "Used".draw(    at: CGPoint(x: margin + nameW + numW * 2, y: headerY), withAttributes: colAttrs)
        curY += 18

        // Divider
        ctx.setStrokeColor(UIColor.separator.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to:    CGPoint(x: margin, y: curY))
        ctx.addLine(to: CGPoint(x: pageRect.width - margin, y: curY))
        ctx.strokePath()
        curY += 8

        // Rows
        let rowH: CGFloat = 28
        for (index, cat) in categories.enumerated() {
            let rowRect = CGRect(x: margin - 4, y: curY - 4,
                                 width: pageRect.width - margin * 2 + 8, height: rowH)
            if index % 2 == 0 {
                ctx.saveGState()
                let path = UIBezierPath(roundedRect: rowRect, cornerRadius: 4).cgPath
                ctx.addPath(path)
                ctx.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }

            let ratio     = cat.budget > 0 ? cat.spent / cat.budget : 0
            let usedColor = ratio < 0.75
                ? UIColor(red: 0.24, green: 0.71, blue: 0.55, alpha: 1)
                : ratio < 1.0
                    ? UIColor(red: 0.93, green: 0.71, blue: 0.20, alpha: 1)
                    : UIColor(red: 0.92, green: 0.32, blue: 0.32, alpha: 1)

            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor.label
            ]
            let numAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.label
            ]
            let pctAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: usedColor
            ]

            cat.name.draw(       at: CGPoint(x: margin, y: curY),                       withAttributes: nameAttrs)
            format(cat.budget, currency: currency).draw(
                at: CGPoint(x: margin + nameW, y: curY),                                withAttributes: numAttrs)
            format(cat.spent, currency: currency).draw(
                at: CGPoint(x: margin + nameW + numW, y: curY),                         withAttributes: numAttrs)
            String(format: "%.0f%%", ratio * 100).draw(
                at: CGPoint(x: margin + nameW + numW * 2, y: curY),                     withAttributes: pctAttrs)

            curY += rowH
        }

        return curY + 12
    }

    // MARK: - Footer

    private static func drawFooter(_ ctx: CGContext, pageRect: CGRect, generatedOn: String) {
        let margin: CGFloat = 40
        let footerY = pageRect.height - 36
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        "Generated by Veloce · \(generatedOn)".draw(
            at: CGPoint(x: margin, y: footerY), withAttributes: attrs)

        ctx.setStrokeColor(UIColor.separator.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to:    CGPoint(x: margin, y: footerY - 8))
        ctx.addLine(to: CGPoint(x: pageRect.width - margin, y: footerY - 8))
        ctx.strokePath()
    }

    // MARK: - Helpers

    private static func format(_ amount: Double, currency: AppCurrency) -> String {
        let f = NumberFormatter()
        f.numberStyle          = .currency
        f.currencyCode         = currency.rawValue
        f.maximumFractionDigits = currency == .vnd || currency == .krw || currency == .jpy ? 0 : 2
        return f.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }

    private static func monthYearLabel() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: Date())
    }

    private static func isoMonthTag() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    private static func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
