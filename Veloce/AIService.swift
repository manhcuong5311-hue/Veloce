import Foundation

// MARK: - AI Service (mock NLP)
// Replace parseExpense() with a real LLM call (Claude, GPT-4o, etc.) for production.

enum AIService {

    // MARK: - Parse natural language → ParsedExpense

    static func parseExpense(_ input: String) -> ParsedExpense? {
        let raw   = input.trimmingCharacters(in: .whitespaces)
        let lower = raw.lowercased()
        guard !lower.isEmpty else { return nil }

        guard let amount = extractAmount(from: lower), amount > 0 else { return nil }

        let categoryName = detectCategory(from: lower)
        let title        = buildTitle(from: raw, lower: lower, fallback: categoryName ?? "Expense")
        let date         = detectDate(from: lower)

        return ParsedExpense(title: title, amount: amount, categoryName: categoryName, date: date)
    }

    // MARK: - Rule-based insight per category

    static func generateInsight(for category: Category, previousSpent: Double) -> AIInsight? {
        let ratio = category.spentRatio

        if ratio > 1.0 {
            let over = (category.spent - category.budget).toCompactCurrency()
            return AIInsight(message: "Over budget by \(over) this month", kind: .alert)
        }
        if ratio > 0.85 {
            let left = category.remainingBudget.toCompactCurrency()
            return AIInsight(message: "Only \(left) left — almost at limit", kind: .warning)
        }
        if previousSpent > 0 {
            let growth = (category.spent - previousSpent) / previousSpent
            if growth > 0.3 {
                return AIInsight(message: "Spending is up \(Int(growth * 100))% vs last week", kind: .warning)
            }
            if growth < -0.2 {
                return AIInsight(message: "Down \(Int(abs(growth) * 100))% vs last week — nice!", kind: .positive)
            }
        }
        if ratio < 0.25 && category.spent > 0 {
            return AIInsight(message: "Well under budget — great discipline!", kind: .positive)
        }
        return nil
    }

    // MARK: - Monthly budget advice

    static func generateAdvice(
        income: Double,
        categories: [Category],
        savingGoal: Double
    ) -> [AIAdvice] {
        let totalSpent = categories.reduce(0) { $0 + $1.spent }
        let surplus    = income - totalSpent

        guard surplus < savingGoal else {
            return [AIAdvice(
                category: "Overview",
                suggestion: "You're on track to meet your savings goal this month.",
                potentialSaving: 0
            )]
        }

        let candidates = categories
            .filter { $0.spentRatio > 0.5 }
            .sorted { $0.spentRatio > $1.spentRatio }
            .prefix(3)
            .map { cat -> AIAdvice in
                let cut = cat.spent * 0.2
                return AIAdvice(
                    category: cat.name,
                    suggestion: "Reduce \(cat.name) by 20% → save \(cut.toCompactCurrency())/month",
                    potentialSaving: cut
                )
            }

        return candidates.isEmpty
            ? [AIAdvice(category: "General", suggestion: "Try cutting discretionary spend by 15%.", potentialSaving: totalSpent * 0.15)]
            : candidates
    }

    // MARK: - Amount extraction
    // Handles: 50k, 1.5tr, 1tr5, 50.000, 50000, 50 (fallback)

    private static func extractAmount(from text: String) -> Double? {
        // "1tr5" → 1,500,000
        if let m1 = regexMatch(text, #"(\d+)tr(\d+)\b"#, captures: 2) {
            if let a = Double(m1[0]), let b = Double(m1[1]) {
                return a * 1_000_000 + b * 100_000
            }
        }
        // "1.5tr", "2tr" → millions
        if let m = regexFirst(text, #"(\d+(?:[.,]\d+)?)\s*tr(?:iệu)?\b"#),
           let v = Double(m.replacingOccurrences(of: ",", with: ".")) {
            return v * 1_000_000
        }
        // "50k", "1.5k"
        if let m = regexFirst(text, #"(\d+(?:[.,]\d+)?)\s*k\b"#),
           let v = Double(m.replacingOccurrences(of: ",", with: ".")) {
            return v * 1_000
        }
        // "50.000" or "50,000" (dot/comma thousands separator)
        if let m = regexFirst(text, #"\b(\d{2,3}[.,]\d{3})\b"#) {
            let clean = m.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
            if let v = Double(clean) { return v }
        }
        // plain 4+ digit number: "50000"
        if let m = regexFirst(text, #"\b(\d{4,})\b"#), let v = Double(m) { return v }
        // small fallback 1-3 digits (assume đồng)
        if let m = regexFirst(text, #"\b(\d{1,3})\b"#), let v = Double(m) { return v }
        return nil
    }

    // MARK: - Category detection
    // Returns nil when no keyword matches — caller should ask user to pick a group.

    private static func detectCategory(from text: String) -> String? {
        // Priority-ordered keyword rules for default category names.
        // The ViewModel layer also fuzzy-matches against user's actual category names.
        let rules: [(String, [String])] = [
            ("Food", [
                "ăn", "cơm", "phở", "bún", "cháo", "bánh", "bún bò", "bún chả",
                "café", "cafe", "coffee", "trà", "trà sữa", "boba", "matcha",
                "pizza", "burger", "sushi", "lẩu", "gà", "hải sản", "cá",
                "mì", "hủ tiếu", "bánh mì", "xôi", "chè", "nước", "nước ngọt",
                "milk tea", "breakfast", "lunch", "dinner", "snack", "kem",
                "siêu thị", "grocery", "market", "kfc", "mcdonald", "jollibee",
                "eat", "food", "drink", "restaurant", "cafe",
            ]),
            ("Transport", [
                "grab", "uber", "taxi", "xe ôm", "xeom", "gojek", "be ",
                "bus", "buýt", "tàu", "tàu điện", "metro", "vé tàu", "vé xe",
                "xăng", "petrol", "gas", "đổ xăng", "bãi xe", "parking",
                "máy bay", "vé máy bay", "flight", "grab bike", "grab car",
                "lyft", "transport", "fare", "fuel",
            ]),
            ("Shopping", [
                "mua", "shop", "quần", "áo", "giày", "dép", "túi", "ví",
                "fashion", "clothes", "clothing", "zara", "h&m", "uniqlo", "muji",
                "lazada", "shopee", "tiki", "amazon", "order", "haul",
                "đồng hồ", "nhẫn", "trang sức", "phụ kiện", "case phone",
                "buy", "purchase",
            ]),
            ("Bills", [
                "điện", "wifi", "internet", "4g", "5g",
                "bill", "hoá đơn", "rent", "thuê nhà", "phòng trọ",
                "phone bill", "bảo hiểm", "tiền nhà",
                "insurance", "subscription", "icloud", "google one",
                "electric", "utility", "water bill",
            ]),
            ("Health", [
                "gym", "fitness", "yoga", "pilates", "thể dục",
                "thuốc", "bác sĩ", "bệnh viện", "khám", "khám bệnh",
                "hospital", "doctor", "clinic", "pharmacy", "nhà thuốc",
                "vitamin", "supplement", "thực phẩm chức năng",
                "medicine", "dental", "health",
            ]),
            ("Entertainment", [
                "phim", "cinema", "bhd", "lotte", "movie",
                "game", "steam", "netflix", "spotify", "youtube premium",
                "concert", "show", "karaoke", "bowling", "billiards",
                "vé", "ticket", "giải trí", "sách", "book",
                "entertainment", "music", "disney",
            ]),
        ]

        var bestMatch: String? = nil
        var bestScore = 0

        for (category, keywords) in rules {
            var score = 0
            for kw in keywords {
                if text.contains(kw) { score += kw.count } // longer keyword = higher confidence
            }
            if score > bestScore {
                bestScore = score
                bestMatch = category
            }
        }

        // Require at least one keyword character matched; otherwise unknown
        return bestScore > 0 ? bestMatch : nil
    }

    // MARK: - Title cleanup

    private static func buildTitle(from raw: String, lower: String, fallback: String) -> String {
        // Try to extract the most meaningful phrase from the raw input
        var s = lower

        // Strip amount tokens
        let strips = [
            #"\d+tr\d+\b"#,
            #"\d+(?:[.,]\d+)?\s*tr(?:iệu)?\b"#,
            #"\d+(?:[.,]\d+)?\s*k\b"#,
            #"\b\d{2,3}[.,]\d{3}\b"#,
            #"\b\d{4,}\b"#,
            #"\bhôm nay\b"#, #"\bhôm qua\b"#, #"\bnay\b"#,
            #"\bsáng\b"#, #"\btrưa\b"#, #"\bchiều\b"#, #"\btối\b"#,
            #"\bbuổi\b"#, #"\bvừa\b"#, #"\bcho\b"#, #"\bmình\b"#,
        ]
        for pattern in strips {
            if let re = try? NSRegularExpression(pattern: pattern) {
                s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
            }
        }

        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let re = try? NSRegularExpression(pattern: #"\s{2,}"#) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }

        // Prefer the original casing from raw input
        if s.count >= 2 {
            // Map cleaned lower back to original
            if let range = raw.lowercased().range(of: s) {
                let original = String(raw[range])
                return original.prefix(1).uppercased() + original.dropFirst()
            }
            return s.prefix(1).uppercased() + s.dropFirst()
        }
        return fallback
    }

    // MARK: - Date detection

    private static func detectDate(from text: String) -> Date {
        let now = Date()
        let cal = Calendar.current

        if text.contains("hôm qua") || text.contains("yesterday") || text.contains("qua ") {
            return cal.date(byAdding: .day, value: -1, to: now) ?? now
        }
        if text.contains("2 ngày") || text.contains("hai ngày") {
            return cal.date(byAdding: .day, value: -2, to: now) ?? now
        }

        var hour: Int?
        if text.contains("sáng") || text.contains("morning")              { hour = 8  }
        else if text.contains("trưa") || text.contains("noon")            { hour = 12 }
        else if text.contains("chiều") || text.contains("afternoon")      { hour = 15 }
        else if text.contains("tối") || text.contains("evening") ||
                text.contains("đêm") || text.contains("night")            { hour = 20 }

        if let h = hour {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = h; comps.minute = 0
            return cal.date(from: comps) ?? now
        }
        return now
    }

    // MARK: - Regex helpers

    private static func regexFirst(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m  = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r  = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func regexMatch(_ text: String, _ pattern: String, captures: Int) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m  = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        var results: [String] = []
        for i in 1...captures {
            guard let r = Range(m.range(at: i), in: text) else { return nil }
            results.append(String(text[r]))
        }
        return results
    }
}
