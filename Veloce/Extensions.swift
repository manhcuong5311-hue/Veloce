import SwiftUI

// MARK: - Design Tokens

enum VeloceTheme {
    // Backgrounds
    static let bg          = Color(hex: "F5F3EF")   // warm off-white
    static let surface     = Color(hex: "FFFFFF")
    static let surfaceRaised = Color(hex: "F0EDE8") // slightly deeper

    // Text
    static let textPrimary   = Color(hex: "1C1B1A")
    static let textSecondary = Color(hex: "8A8680")
    static let textTertiary  = Color(hex: "C2BEB8")

    // Accent
    static let accent   = Color(hex: "7B6CF0")   // soft indigo
    static let accentBg = Color(hex: "EEECFc")   // light indigo wash

    // Status (muted)
    static let ok      = Color(hex: "6BBF8E")    // sage green
    static let caution = Color(hex: "E8B86D")    // warm amber
    static let over    = Color(hex: "E88A7A")    // dusty coral

    // Divider
    static let divider = Color(hex: "ECEAE5")

    // Shadow base
    static func shadow(_ radius: CGFloat = 12, y: CGFloat = 4) -> some View { EmptyView() }
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3:  (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (200, 200, 200)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    // Pastel tint of any color (80% white blend)
    func pastel(opacity: Double = 0.15) -> Color { self.opacity(opacity) }
}

// MARK: - View modifiers

struct VeloceCard: ViewModifier {
    var radius: CGFloat = 18
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(VeloceTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.055), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.025), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func veloceCard(radius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        modifier(VeloceCard(radius: radius, padding: padding))
    }
}

// MARK: - Number formatting

extension Double {
    func toCompactCurrency() -> String {
        if self >= 1_000_000 {
            let m = self / 1_000_000
            let s = m.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fM", m)
                : String(format: "%.1fM", m)
            return s + "đ"
        }
        if self >= 1_000 {
            let k = self / 1_000
            let s = k.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fk", k)
                : String(format: "%.1fk", k)
            return s + "đ"
        }
        return "\(Int(self))đ"
    }

    func toCurrencyString() -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: self)) ?? "\(Int(self))") + "đ"
    }
}

// MARK: - Date formatting

extension Date {
    func toRelativeDateString() -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        if cal.isDateInToday(self) {
            f.dateFormat = "HH:mm"
            return f.string(from: self)
        }
        if cal.isDateInYesterday(self) {
            f.dateFormat = "HH:mm"
            return "Yesterday · \(f.string(from: self))"
        }
        f.dateFormat = "dd/MM · HH:mm"
        return f.string(from: self)
    }

    func toTimeString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }

    var dayBucket: String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        if cal.isDateInToday(self)     { return "Today" }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        f.dateFormat = "EEEE, d MMM"
        return f.string(from: self)
    }
}
