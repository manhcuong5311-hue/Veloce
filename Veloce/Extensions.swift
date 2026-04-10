import SwiftUI

// MARK: - Currency

enum AppCurrency: String, CaseIterable, Identifiable {
    case vnd = "VND"
    case usd = "USD"
    case eur = "EUR"
    case jpy = "JPY"
    case gbp = "GBP"
    case krw = "KRW"
    case sgd = "SGD"
    case thb = "THB"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .vnd: return "đ"
        case .usd: return "$"
        case .eur: return "€"
        case .jpy: return "¥"
        case .gbp: return "£"
        case .krw: return "₩"
        case .sgd: return "S$"
        case .thb: return "฿"
        }
    }

    var displayName: String {
        switch self {
        case .vnd: return "VNĐ  đ"
        case .usd: return "USD  $"
        case .eur: return "EUR  €"
        case .jpy: return "JPY  ¥"
        case .gbp: return "GBP  £"
        case .krw: return "KRW  ₩"
        case .sgd: return "SGD  S$"
        case .thb: return "THB  ฿"
        }
    }

    /// Thousands separator: VND / KRW use "." (100.000), others use "," (100,000)
    var thousandsSep: String {
        switch self {
        case .vnd, .krw: return "."
        default:         return ","
        }
    }

    /// Whether the symbol goes before the number
    var symbolLeading: Bool {
        switch self {
        case .vnd: return false   // 100.000đ
        default:   return true    // $1,000
        }
    }

    /// VND / JPY / KRW display as whole numbers only
    var showsDecimals: Bool {
        switch self {
        case .vnd, .jpy, .krw: return false
        default:                return true
        }
    }

    static var current: AppCurrency {
        AppCurrency(rawValue: UserDefaults.standard.string(forKey: "veloce_currency") ?? "VND") ?? .vnd
    }
}

// MARK: - Speech Language

struct SpeechLanguage: Identifiable, Hashable {
    let code: String   // BCP-47 locale identifier
    let flag: String
    let name: String
    var id: String { code }

    static let all: [SpeechLanguage] = [
        .init(code: "vi-VN", flag: "🇻🇳", name: "Tiếng Việt"),
        .init(code: "en-US", flag: "🇺🇸", name: "English (US)"),
        .init(code: "en-GB", flag: "🇬🇧", name: "English (UK)"),
        .init(code: "zh-CN", flag: "🇨🇳", name: "中文 (简体)"),
        .init(code: "ja-JP", flag: "🇯🇵", name: "日本語"),
        .init(code: "ko-KR", flag: "🇰🇷", name: "한국어"),
        .init(code: "fr-FR", flag: "🇫🇷", name: "Français"),
        .init(code: "es-ES", flag: "🇪🇸", name: "Español"),
        .init(code: "th-TH", flag: "🇹🇭", name: "ภาษาไทย"),
        .init(code: "de-DE", flag: "🇩🇪", name: "Deutsch"),
    ]

    static var current: SpeechLanguage {
        let code = UserDefaults.standard.string(forKey: "veloce_speech_language") ?? "vi-VN"
        return all.first { $0.code == code } ?? all[0]
    }
}

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
        let c = AppCurrency.current
        func place(_ s: String) -> String {
            c.symbolLeading ? "\(c.symbol)\(s)" : "\(s)\(c.symbol)"
        }
        if self >= 1_000_000 {
            let m = self / 1_000_000
            let s = m.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fM", m)
                : String(format: "%.1fM", m)
            return place(s)
        }
        if self >= 1_000 {
            let k = self / 1_000
            let s = k.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fk", k)
                : String(format: "%.1fk", k)
            return place(s)
        }
        let s = c.showsDecimals
            ? String(format: "%.2f", self)
            : "\(Int(self))"
        return place(s)
    }

    func toCurrencyString() -> String {
        let c = AppCurrency.current
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator    = c.thousandsSep
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = c.showsDecimals ? 2 : 0
        f.minimumFractionDigits = 0
        let s = f.string(from: NSNumber(value: self)) ?? "\(Int(self))"
        return c.symbolLeading ? "\(c.symbol)\(s)" : "\(s)\(c.symbol)"
    }

    /// Formats a raw digit string with the correct thousands separator while typing.
    static func formatAmountInput(_ digits: String) -> String {
        guard !digits.isEmpty, let val = Double(digits) else { return digits }
        let c = AppCurrency.current
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator    = c.thousandsSep
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: val)) ?? digits
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
