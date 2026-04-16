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

    /// Snap increment used by the budget drag gesture.
    /// Must be << typical budget values so round(raw / snapStep) doesn't always
    /// return 0. Rule of thumb: ~1/100 of a typical monthly budget per currency.
    var budgetSnapStep: Double {
        switch self {
        case .vnd: return 100_000   // 100 k₫  (~$4)
        case .jpy: return 500       // ¥500     (~$3)
        case .krw: return 1_000     // ₩1,000   (~$0.75)
        case .usd: return 1         // $1
        case .eur: return 1         // €1
        case .gbp: return 1         // £1
        case .sgd: return 1         // S$1
        case .thb: return 10        // ฿10      (~$0.28)
        }
    }

    static var current: AppCurrency {
        AppCurrency(rawValue: UserDefaults.standard.string(forKey: "veloce_currency") ?? "VND") ?? .vnd
    }

    /// Sensible default budget string for the "New Group" sheet, in this currency's units.
    var defaultBudgetText: String {
        switch self {
        case .vnd: return "1000000"
        case .usd: return "200"
        case .eur: return "200"
        case .jpy: return "20000"
        case .gbp: return "150"
        case .krw: return "200000"
        case .sgd: return "200"
        case .thb: return "5000"
        }
    }

    /// Quick-pick preset budgets shown in the group edit sheet, localised per currency.
    var budgetPresets: [(label: String, value: Double)] {
        switch self {
        case .vnd:
            return [
                ("500K",    500_000), ("1 tr",   1_000_000), ("1.5 tr", 1_500_000),
                ("2 tr",  2_000_000), ("3 tr",   3_000_000), ("5 tr",   5_000_000),
                ("10 tr", 10_000_000)
            ]
        case .usd:
            return [
                ("$50",    50), ("$100",   100), ("$200",   200),
                ("$300",  300), ("$500",   500), ("$1K",  1_000),
                ("$2K", 2_000)
            ]
        case .eur:
            return [
                ("€50",    50), ("€100",   100), ("€200",   200),
                ("€300",  300), ("€500",   500), ("€1K",  1_000),
                ("€2K", 2_000)
            ]
        case .jpy:
            return [
                ("¥2K",   2_000), ("¥5K",   5_000), ("¥10K",  10_000),
                ("¥20K", 20_000), ("¥30K", 30_000), ("¥50K",  50_000),
                ("¥100K", 100_000)
            ]
        case .gbp:
            return [
                ("£50",    50), ("£100",   100), ("£200",   200),
                ("£300",  300), ("£500",   500), ("£1K",  1_000),
                ("£2K", 2_000)
            ]
        case .krw:
            return [
                ("₩20K",   20_000), ("₩50K",   50_000), ("₩100K", 100_000),
                ("₩200K", 200_000), ("₩300K", 300_000), ("₩500K", 500_000),
                ("₩1M", 1_000_000)
            ]
        case .sgd:
            return [
                ("S$50",    50), ("S$100",   100), ("S$200",   200),
                ("S$300",  300), ("S$500",   500), ("S$1K",  1_000),
                ("S$2K", 2_000)
            ]
        case .thb:
            return [
                ("฿500",   500), ("฿1K",   1_000), ("฿2K",   2_000),
                ("฿3K",  3_000), ("฿5K",   5_000), ("฿10K", 10_000),
                ("฿20K", 20_000)
            ]
        }
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

// MARK: - Category Localization

/// Localised category names and locale-based currency detection for first launch.
/// The English keys ("Food", "Transport" …) are treated as stable system identifiers
/// stored in the Category model; display names are derived from this table.
enum CategoryLocalization {

    // MARK: Name lookup

    /// Returns the display name for an English category key in the given BCP-47 language code.
    /// Falls back to the English key if no translation exists.
    static func name(for key: String, langCode: String) -> String {
        let lang = langCode.count >= 2 ? String(langCode.prefix(2)) : langCode
        return table[key]?[lang] ?? key
    }

    /// All known names for a key (English + every translation).
    /// Used by `resolveCategory` to match a detected English key against
    /// a category that may be stored with a localised name.
    static func allNames(for key: String) -> [String] {
        var names: [String] = [key]
        if let translations = table[key] { names.append(contentsOf: translations.values) }
        return names
    }

    // MARK: Locale → currency

    /// Infers the best default `AppCurrency` from the device region.
    /// Only called on first launch (when no currency key is saved yet).
    static func defaultCurrency() -> AppCurrency {
        let region = Locale.current.region?.identifier ?? ""
        switch region {
        case "VN":                              return .vnd
        case "JP":                              return .jpy
        case "KR":                              return .krw
        case "TH":                              return .thb
        case "SG":                              return .sgd
        case "GB":                              return .gbp
        case "US", "CA", "AU", "NZ",
             "PH", "IN", "MX", "BR",
             "AR", "CL", "CO", "PE":           return .usd
        default:
            // Euro-zone countries
            let euroZone: Set<String> = [
                "DE","FR","ES","IT","NL","BE","PT","AT","FI",
                "GR","IE","LU","SI","SK","EE","LV","LT","CY","MT"
            ]
            return euroZone.contains(region) ? .eur : .usd
        }
    }

    /// Infers the best default speech-recognition language code from the device locale.
    static func defaultSpeechCode() -> String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier ?? ""
        switch lang {
        case "vi": return "vi-VN"
        case "zh": return "zh-CN"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "fr": return "fr-FR"
        case "es": return "es-ES"
        case "th": return "th-TH"
        case "de": return "de-DE"
        case "en": return region == "GB" ? "en-GB" : "en-US"
        default:   return "en-US"
        }
    }

    // MARK: Default budgets per currency

    /// Sensible default monthly budgets (rounded to local-feeling amounts).
    /// Order: Food, Transport, Shopping, Bills, Health, Entertainment, Other
    static func defaultBudgets(for currency: AppCurrency) -> [Double] {
        switch currency {
        case .vnd: return [3_000_000, 1_500_000, 2_000_000, 2_500_000, 1_000_000, 1_000_000,   500_000]
        case .usd: return [      300,       150,       200,       250,       100,       100,        50]
        case .eur: return [      280,       140,       180,       230,        90,        90,        45]
        case .jpy: return [   36_000,    18_000,    24_000,    30_000,    12_000,    12_000,     6_000]
        case .gbp: return [      240,       120,       160,       200,        80,        80,        40]
        case .krw: return [  400_000,   200_000,   260_000,   330_000,   130_000,   130_000,    65_000]
        case .sgd: return [      400,       200,       270,       340,       135,       135,        65]
        case .thb: return [   10_000,     5_000,     7_000,     8_500,     3_500,     3_500,     1_750]
        }
    }

    // MARK: Translation table
    // key: English system name   inner key: 2-letter ISO 639-1 language code

    private static let table: [String: [String: String]] = [
        "Food": [
            "vi": "Ăn uống",
            "zh": "餐饮",
            "ja": "食費",
            "ko": "식비",
            "fr": "Alimentation",
            "es": "Comida",
            "th": "อาหาร",
            "de": "Essen",
        ],
        "Transport": [
            "vi": "Di chuyển",
            "zh": "交通",
            "ja": "交通費",
            "ko": "교통비",
            "fr": "Transport",
            "es": "Transporte",
            "th": "การเดินทาง",
            "de": "Transport",
        ],
        "Shopping": [
            "vi": "Mua sắm",
            "zh": "购物",
            "ja": "ショッピング",
            "ko": "쇼핑",
            "fr": "Shopping",
            "es": "Compras",
            "th": "ช้อปปิ้ง",
            "de": "Einkaufen",
        ],
        "Bills": [
            "vi": "Hoá đơn",
            "zh": "账单",
            "ja": "光熱費",
            "ko": "공과금",
            "fr": "Factures",
            "es": "Facturas",
            "th": "ค่าบิล",
            "de": "Rechnungen",
        ],
        "Health": [
            "vi": "Sức khoẻ",
            "zh": "健康",
            "ja": "医療費",
            "ko": "건강",
            "fr": "Santé",
            "es": "Salud",
            "th": "สุขภาพ",
            "de": "Gesundheit",
        ],
        "Entertainment": [
            "vi": "Giải trí",
            "zh": "娱乐",
            "ja": "娯楽",
            "ko": "여가",
            "fr": "Loisirs",
            "es": "Entretenimiento",
            "th": "บันเทิง",
            "de": "Unterhaltung",
        ],
        "Other": [
            "vi": "Khác",
            "zh": "其他",
            "ja": "その他",
            "ko": "기타",
            "fr": "Autre",
            "es": "Otros",
            "th": "อื่นๆ",
            "de": "Sonstiges",
        ],
    ]
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

    // Accent — reads from UserDefaults so AccentColorPickerSheet takes effect on next launch
    static var accent: Color {
        Color(hex: UserDefaults.standard.string(forKey: "veloce_accent_hex") ?? "7B6CF0")
    }
    static var accentBg: Color { accent.opacity(0.12) }

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

    /// Convert a SwiftUI Color to a 6-character uppercase hex string (no alpha).
    /// Uses UIColor bridging to reliably extract sRGB components.
    /// Falls back to Veloce accent purple if components cannot be resolved.
    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "7B6CF0" }
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }

    // Pastel tint of any color (80% white blend)
    func pastel(opacity: Double = 0.15) -> Color { self.opacity(opacity) }
}

// MARK: - Flow Layout
// Arranges children horizontally, wrapping to the next line when they overflow.

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, in: proposal.width ?? 0).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, in: bounds.width)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var origins: [CGPoint]
        var size:    CGSize
    }

    private func layout(subviews: Subviews, in width: CGFloat) -> LayoutResult {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }

        return LayoutResult(
            origins: origins,
            size:    CGSize(width: width, height: y + rowH)
        )
    }
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
        f.locale = Locale.current
        if cal.isDateInToday(self) {
            f.dateFormat = "HH:mm"
            return f.string(from: self)
        }
        if cal.isDateInYesterday(self) {
            f.dateFormat = "HH:mm"
            return String(format: String(localized: "date_yesterday_time_fmt"), f.string(from: self))
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
        f.locale = Locale.current
        if cal.isDateInToday(self)     { return String(localized: "date_today") }
        if cal.isDateInYesterday(self) { return String(localized: "date_yesterday") }
        f.dateFormat = "EEEE, d MMM"
        return f.string(from: self)
    }
}
