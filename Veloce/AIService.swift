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
            return AIInsight(message: String(format: String(localized: "ai_insight_over_budget_fmt"), over), kind: .alert)
        }
        if ratio > 0.85 {
            let left = category.remainingBudget.toCompactCurrency()
            return AIInsight(message: String(format: String(localized: "ai_insight_near_limit_fmt"), left), kind: .warning)
        }
        if previousSpent > 0 {
            let growth = (category.spent - previousSpent) / previousSpent
            if growth > 0.3 {
                return AIInsight(message: String(format: String(localized: "ai_insight_up_pct_fmt"), Int(growth * 100)), kind: .warning)
            }
            if growth < -0.2 {
                return AIInsight(message: String(format: String(localized: "ai_insight_down_pct_fmt"), Int(abs(growth) * 100)), kind: .positive)
            }
        }
        if ratio < 0.25 && category.spent > 0 {
            return AIInsight(message: String(localized: "ai_insight_well_under"), kind: .positive)
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
                suggestion: String(localized: "ai_advice_on_track"),
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
                    suggestion: String(format: String(localized: "ai_advice_reduce_fmt"), cat.name, cut.toCompactCurrency()),
                    potentialSaving: cut
                )
            }

        return candidates.isEmpty
            ? [AIAdvice(category: "General", suggestion: String(localized: "ai_advice_cut_discretionary"), potentialSaving: totalSpent * 0.15)]
            : candidates
    }

    // MARK: - Amount extraction
    // Handles: 50k, 1.5tr, 1tr5, 50.000, 50000, word numbers ("twenty five", "một trăm nghìn"), 50 (fallback)

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
        // Word-based spoken numbers: "twenty five dollars", "một trăm nghìn", "50 nghìn"
        // Must run before the 1-3 digit fallback so "50 nghìn" → 50_000, not 50.
        if let v = SpokenNumberParser.parse(text), v > 0 { return v }
        // small fallback 1-3 digits (assume đồng)
        if let m = regexFirst(text, #"\b(\d{1,3})\b"#), let v = Double(m) { return v }
        return nil
    }

    // MARK: - Category detection
    // Returns nil when no keyword matches — caller should ask user to pick a group.

    private static func detectCategory(from text: String) -> String? {
        // Priority-ordered keyword rules covering all 10 app languages:
        // Vietnamese, English (US/UK), Chinese (Simplified), Japanese,
        // Korean, French, Spanish, Thai, German.
        let rules: [(String, [String])] = [
            ("Food", [
                // 🇻🇳 Vietnamese
                "ăn", "cơm", "phở", "bún", "cháo", "bánh", "bún bò", "bún chả",
                "café", "cafe", "coffee", "trà", "trà sữa", "boba", "matcha",
                "pizza", "burger", "sushi", "lẩu", "gà", "hải sản", "cá",
                "mì", "hủ tiếu", "bánh mì", "xôi", "chè", "nước", "nước ngọt",
                "siêu thị", "kfc", "mcdonald", "jollibee", "snack", "kem",
                // 🇺🇸🇬🇧 English
                "eat", "food", "drink", "restaurant", "grocery", "market",
                "breakfast", "lunch", "dinner", "milk tea", "bubble tea",
                // 🇨🇳 Chinese
                "吃", "饭", "餐", "咖啡", "早餐", "午餐", "晚餐", "零食", "超市",
                "奶茶", "外卖", "火锅", "面", "饮料",
                // 🇯🇵 Japanese
                "食べ", "ランチ", "ご飯", "カフェ", "コーヒー", "レストラン",
                "朝食", "昼食", "夕食", "スーパー", "弁当", "お茶", "居酒屋",
                // 🇰🇷 Korean
                "식사", "밥", "카페", "커피", "점심", "저녁", "아침", "음식", "마트",
                "분식", "치킨", "삼겹살", "라면",
                // 🇫🇷 French
                "manger", "repas", "déjeuner", "dîner", "petit-déjeuner",
                "épicerie", "boulangerie", "brasserie",
                // 🇪🇸 Spanish
                "comer", "comida", "almuerzo", "cena", "desayuno",
                "supermercado", "taquería",
                // 🇹🇭 Thai
                "อาหาร", "กาแฟ", "ข้าว", "ร้านอาหาร", "ตลาด", "ชา", "ข้าวมันไก่",
                // 🇩🇪 German
                "essen", "mahlzeit", "kaffee", "frühstück", "mittagessen",
                "abendessen", "supermarkt", "bäckerei",
            ]),
            ("Transport", [
                // 🇻🇳 Vietnamese
                "grab", "gojek", "be ", "xe ôm", "xeom",
                "buýt", "tàu", "tàu điện", "metro", "vé tàu", "vé xe",
                "xăng", "đổ xăng", "bãi xe", "máy bay", "vé máy bay",
                // 🇺🇸🇬🇧 English
                "uber", "lyft", "taxi", "bus", "subway", "train", "flight",
                "petrol", "gas", "fuel", "parking", "fare", "transport",
                "grab bike", "grab car",
                // 🇨🇳 Chinese
                "打车", "地铁", "公交", "出租车", "加油", "滴滴", "高铁", "机票",
                // 🇯🇵 Japanese
                "電車", "バス", "タクシー", "地下鉄", "ガソリン", "新幹線", "飛行機代",
                // 🇰🇷 Korean
                "택시", "버스", "지하철", "주유", "기차", "항공",
                // 🇫🇷 French
                "transport", "métro", "essence", "train", "avion", "vélo",
                // 🇪🇸 Spanish
                "transporte", "gasolina", "autobús", "metro", "vuelo",
                // 🇹🇭 Thai
                "รถ", "แท็กซี่", "รถไฟ", "น้ำมัน", "mrt", "bts", "สกายทรัน",
                // 🇩🇪 German
                "bahn", "benzin", "tankstelle", "flug", "ubahn",
            ]),
            ("Shopping", [
                // 🇻🇳 Vietnamese
                "mua", "shop", "quần", "áo", "giày", "dép", "túi", "ví",
                "lazada", "shopee", "tiki", "đồng hồ", "nhẫn", "trang sức",
                "phụ kiện", "case phone",
                // 🇺🇸🇬🇧 English
                "buy", "purchase", "clothes", "clothing", "fashion", "shoes",
                "amazon", "order", "haul", "zara", "h&m", "uniqlo", "muji",
                // 🇨🇳 Chinese
                "买", "购物", "衣服", "鞋", "淘宝", "京东", "天猫", "包",
                // 🇯🇵 Japanese
                "買い物", "ショッピング", "服", "靴", "バッグ", "楽天", "アマゾン",
                // 🇰🇷 Korean
                "쇼핑", "옷", "신발", "구매", "쿠팡",
                // 🇫🇷 French
                "shopping", "acheter", "vêtements", "chaussures", "sac",
                // 🇪🇸 Spanish
                "compras", "comprar", "ropa", "zapatos", "bolsa",
                // 🇹🇭 Thai
                "ช้อปปิ้ง", "เสื้อผ้า", "รองเท้า", "กระเป๋า",
                // 🇩🇪 German
                "einkaufen", "kleidung", "schuhe", "tasche",
            ]),
            ("Bills", [
                // 🇻🇳 Vietnamese
                "điện", "wifi", "internet", "4g", "5g",
                "hoá đơn", "thuê nhà", "phòng trọ", "bảo hiểm", "tiền nhà",
                // 🇺🇸🇬🇧 English
                "bill", "rent", "insurance", "subscription", "electric",
                "utility", "water bill", "phone bill", "icloud", "google one",
                // 🇨🇳 Chinese
                "电费", "网费", "租金", "房租", "保险", "话费", "水费", "物业",
                // 🇯🇵 Japanese
                "電気代", "ネット代", "家賃", "保険", "携帯代", "水道代",
                // 🇰🇷 Korean
                "전기세", "인터넷", "집세", "보험", "휴대폰", "관리비",
                // 🇫🇷 French
                "facture", "loyer", "électricité", "assurance", "abonnement",
                // 🇪🇸 Spanish
                "factura", "alquiler", "electricidad", "seguro", "suscripción",
                // 🇹🇭 Thai
                "ค่าไฟ", "ค่าน้ำ", "ค่าเช่า", "ประกัน", "อินเทอร์เน็ต",
                // 🇩🇪 German
                "rechnung", "miete", "strom", "versicherung", "abonnement",
            ]),
            ("Health", [
                // 🇻🇳 Vietnamese
                "gym", "thể dục", "yoga", "pilates",
                "thuốc", "bác sĩ", "bệnh viện", "khám", "nhà thuốc",
                "vitamin", "supplement", "thực phẩm chức năng",
                // 🇺🇸🇬🇧 English
                "fitness", "hospital", "doctor", "clinic", "pharmacy",
                "medicine", "dental", "health",
                // 🇨🇳 Chinese
                "健身", "医院", "药店", "看病", "医生", "药", "体检",
                // 🇯🇵 Japanese
                "ジム", "病院", "薬局", "医者", "薬", "歯医者", "健康診断",
                // 🇰🇷 Korean
                "헬스장", "병원", "약국", "의사", "약", "치과",
                // 🇫🇷 French
                "hôpital", "médecin", "pharmacie", "médicament", "dentiste",
                // 🇪🇸 Spanish
                "gimnasio", "hospital", "médico", "farmacia", "medicina",
                // 🇹🇭 Thai
                "ฟิตเนส", "โรงพยาบาล", "หมอ", "ยา", "ร้านขายยา",
                // 🇩🇪 German
                "fitnessstudio", "krankenhaus", "arzt", "apotheke", "medikament",
            ]),
            ("Entertainment", [
                // 🇻🇳 Vietnamese
                "phim", "cinema", "bhd", "lotte", "karaoke",
                "game", "giải trí", "sách", "vé", "bowling", "billiards",
                // 🇺🇸🇬🇧 English
                "movie", "music", "concert", "show", "ticket", "book",
                "netflix", "spotify", "steam", "disney", "youtube premium",
                "entertainment",
                // 🇨🇳 Chinese
                "电影", "游戏", "音乐", "演唱会", "书", "ktv",
                // 🇯🇵 Japanese
                "映画", "ゲーム", "音楽", "コンサート", "カラオケ", "本",
                // 🇰🇷 Korean
                "영화", "게임", "음악", "콘서트", "노래방", "책",
                // 🇫🇷 French
                "cinéma", "jeu", "musique", "concert", "livre",
                // 🇪🇸 Spanish
                "cine", "juego", "música", "concierto", "libro",
                // 🇹🇭 Thai
                "หนัง", "เกม", "เพลง", "คอนเสิร์ต", "หนังสือ",
                // 🇩🇪 German
                "kino", "spiel", "musik", "konzert", "buch",
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
