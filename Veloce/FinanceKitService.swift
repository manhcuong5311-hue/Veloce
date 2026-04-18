import Foundation
import FinanceKit

// MARK: - PendingImport
//
// A mapped expense waiting for user confirmation, plus metadata used by
// the confirmation UI (duplicate flag, original currency info).

struct PendingImport: Identifiable {
    let id = UUID()
    var expense: Expense
    let originalAmount: Decimal
    let originalCurrencyCode: String
    let wasCurrencyConverted: Bool
    let isDuplicate: Bool
}

// MARK: - FinanceKitService

@MainActor
final class FinanceKitService {

    static let shared = FinanceKitService()
    private init() {}

    // MARK: Availability

    var isAvailable: Bool {
        FinanceStore.isDataAvailable(.financialData)
    }

    // MARK: Mapping

    /// Maps FinanceKit transactions to PendingImport list.
    /// Filters out income types (deposits, dividends), refunds, and rejected statuses.
    func mapToPendingImports(
        _ transactions: [FinanceKit.Transaction],
        categories: [Category],
        existingExpenses: [Expense]
    ) -> [PendingImport] {

        let currentCurrency = AppCurrency.current

        return transactions.compactMap { tx -> PendingImport? in

            // 1. Only import expense-type transactions
            guard Self.isExpenseType(tx.transactionType) else { return nil }
            // 2. Skip rejected/cancelled
            guard tx.status != .rejected else { return nil }
            // 3. Amount must be positive (debits)
            guard tx.transactionAmount.amount > 0 else { return nil }

            let originalAmount = tx.transactionAmount.amount
            let originalCode   = tx.transactionAmount.currencyCode
            let rawDouble      = (originalAmount as NSDecimalNumber).doubleValue

            // 4. Currency conversion
            let (convertedAmount, wasCurrencyConverted) = convertAmount(
                rawDouble,
                fromCode: originalCode,
                to: currentCurrency
            )

            // 5. Category auto-match
            let categoryId = bestCategory(
                mcc: tx.merchantCategoryCode.map { Int($0.rawValue) },
                description: tx.originalTransactionDescription,
                categories: categories
            )

            // 6. Build note — append original currency if converted
            let note = wasCurrencyConverted
                ? "\(String(localized: "apple_pay_note")) · \(originalCode)"
                : String(localized: "apple_pay_note")

            let expense = Expense(
                title: tx.originalTransactionDescription,
                amount: convertedAmount,
                categoryId: categoryId,
                date: tx.transactionDate,
                note: note
            )

            // 7. Duplicate detection: same title + same amount (±1) + same calendar day
            let isDuplicate = existingExpenses.contains { e in
                e.title == expense.title &&
                abs(e.amount - expense.amount) < 1.0 &&
                Calendar.current.isDate(e.date, inSameDayAs: expense.date)
            }

            return PendingImport(
                expense: expense,
                originalAmount: originalAmount,
                originalCurrencyCode: originalCode,
                wasCurrencyConverted: wasCurrencyConverted,
                isDuplicate: isDuplicate
            )
        }
    }

    // MARK: - Private helpers

    private func convertAmount(
        _ amount: Double,
        fromCode: String,
        to target: AppCurrency
    ) -> (amount: Double, converted: Bool) {
        guard fromCode != target.rawValue else { return (amount, false) }
        guard let source = AppCurrency(rawValue: fromCode) else { return (amount, false) }
        return (CurrencyManager.shared.convert(amount, from: source, to: target), true)
    }

    /// Returns true for transaction types that represent an outgoing expense.
    /// Excludes income (deposit, directDeposit, dividend, interest), refunds, and unknowns.
    private static func isExpenseType(_ type: FinanceKit.TransactionType) -> Bool {
        switch type {
        case .pointOfSale, .atm, .billPayment, .fee, .withdrawal,
             .standingOrder, .directDebit, .check:
            return true
        case .deposit, .directDeposit, .dividend, .interest,
             .refund, .adjustment, .loan, .unknown:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Category matching

    /// Resolves the best category UUID using MCC code first, then multi-language
    /// keyword scanning, then falls back to the last category ("Other").
    private func bestCategory(
        mcc: Int?,
        description: String,
        categories: [Category]
    ) -> UUID {
        // 1. MCC → English category key
        if let mcc, let key = mccCategoryKey(mcc),
           let id = findCategory(byKey: key, in: categories) {
            return id
        }

        // 2. Multi-language keyword scan on merchant name
        let lower = description.lowercased()
        for (words, key) in Self.keywordTable {
            if words.contains(where: { lower.contains($0) }),
               let id = findCategory(byKey: key, in: categories) {
                return id
            }
        }

        // 3. Fallback → "Other" category by name, then last resort
        return findCategory(byKey: "Other", in: categories)
            ?? categories.last?.id
            ?? categories[0].id
    }

    /// Finds a category by its English system key ("Food", "Transport", …)
    /// using `CategoryLocalization.allNames` so it works regardless of whether
    /// the user's categories are stored in English or a localized language.
    private func findCategory(byKey key: String, in categories: [Category]) -> UUID? {
        let knownNames = Set(CategoryLocalization.allNames(for: key).map { $0.lowercased() })
        return categories.first { knownNames.contains($0.name.lowercased()) }?.id
    }

    // MARK: - Multi-language keyword table
    //
    // Each entry: ([keywords…], englishCategoryKey)
    // Keywords are lowercase. Matching uses String.contains — works for all scripts
    // (Thai, Chinese, Japanese, Korean have no word boundaries, so contains is correct).
    // Keep keywords specific enough to avoid false positives on short common words.
    //
    // Languages covered: EN (US/UK), VI, ZH, JA, KO, FR, ES, TH, DE

    private static let keywordTable: [([String], String)] = [

        // ── FOOD ───────────────────────────────────────────────────────────────
        ([
            // Global brands / generic EN
            "restaurant", "cafe", "coffee", "bakery", "pizza", "burger", "sushi",
            "ramen", "noodle", "grocery", "deli", "brunch", "takeaway", "takeout",
            "kfc", "mcdonalds", "mcdonald", "subway", "starbucks", "taco bell",
            "five guys", "chipotle", "domino", "food court", "food hall", "eatery",
            "bistro", "brasserie", "steakhouse", "trattoria", "naan", "kebab",
            "dumpling", "dim sum", "pho", "banh mi", "bubble tea",
            // VI
            "phở", "bún", "cơm", "quán ăn", "cà phê", "trà sữa", "bánh mì",
            "bánh", "nem", "lẩu", "nướng", "chè", "hủ tiếu", "miến", "xôi",
            "bếp", "ăn uống", "nước mía", "cháo", "mì quảng", "bò kho",
            // ZH (Simplified)
            "餐厅", "咖啡", "快餐", "外卖", "火锅", "烧烤", "早餐", "午餐",
            "晚餐", "便利店", "奶茶", "点心", "面条", "小吃", "饺子", "包子",
            "米饭", "食堂", "蛋糕", "面包",
            // JA
            "レストラン", "カフェ", "コーヒー", "食堂", "弁当", "ラーメン",
            "寿司", "うどん", "居酒屋", "コンビニ", "ランチ", "定食", "そば",
            "天ぷら", "焼肉", "パン", "スーパー",
            // KO
            "식당", "카페", "커피", "편의점", "치킨", "삼겹살", "떡볶이",
            "라면", "냉면", "배달", "점심", "저녁", "아침", "분식", "국밥",
            // FR
            "boulangerie", "pâtisserie", "épicerie", "déjeuner", "dîner",
            "petit-déjeuner", "traiteur", "crêperie", "fromagerie", "supérette",
            // ES
            "restaurante", "cafetería", "panadería", "almuerzo", "cena",
            "desayuno", "taquería", "frutería",
            // TH
            "ร้านอาหาร", "กาแฟ", "ข้าว", "ก๋วยเตี๋ยว", "ส้มตำ", "ต้มยำ",
            "ชานม", "อาหาร", "ผัดไทย", "หมูกระทะ",
            // DE
            "bäckerei", "metzgerei", "mittagessen", "abendessen", "frühstück",
            "imbiss", "döner", "bratwurst", "konditorei", "lebensmittel",
        ], "Food"),

        // ── TRANSPORT ─────────────────────────────────────────────────────────
        ([
            // Global brands / generic EN
            "grab", "uber", "lyft", "taxi", "bus ", "mrt", "train", "metro",
            "parking", "petrol", "fuel", "toll", "ferry", "tram",
            "bolt", "gojek", "transit", "bts", "skytrain", "sky train",
            "rideshare", "car hire", "car rental", "airport", "airline",
            "flight", "highway", "expressway",
            // VI
            "xăng", "bãi xe", "vé xe", "gojek", "be app", "vinbus",
            "xe bus", "xe ôm", "đỗ xe", "bến xe", "sân bay", "vé máy bay",
            "cao tốc",
            // ZH
            "出租车", "地铁", "公交", "滴滴", "加油", "停车", "高铁", "打车",
            "共享单车", "机场", "车费", "交通费", "动车", "大巴",
            // JA
            "タクシー", "電車", "バス", "地下鉄", "駐車場", "ガソリン",
            "新幹線", "交通費", "運賃", "乗車券", "定期券", "高速道路",
            // KO
            "택시", "지하철", "버스", "주차", "기름", "ktx", "기차",
            "교통비", "지하철비", "고속도로", "톨게이트",
            // FR
            "métro", "essence", "tramway", "péage", "autoroute", "vélib",
            "sncf", "ratp", "navigo",
            // ES
            "metro", "autobús", "gasolina", "estacionamiento", "peaje",
            "renfe", "cabify", "blablacar",
            // TH
            "แท็กซี่", "รถไฟ", "บีทีเอส", "น้ำมัน", "จอดรถ",
            "รถเมล์", "โดยสาร", "มรท", "ทางด่วน", "สนามบิน",
            // DE
            "u-bahn", "s-bahn", "bahn", "benzin", "parken", "maut",
            "fahrschein", "öpnv", "autobahn", "tankstelle",
        ], "Transport"),

        // ── SHOPPING ──────────────────────────────────────────────────────────
        ([
            // Global brands / generic EN
            "shopee", "lazada", "amazon", "walmart", "target", "ebay", "etsy",
            "ikea", "zara", "h&m", "uniqlo", "primark", "costco", "sephora",
            "mediamarkt", "mall", "shopping", "boutique", "clothing", "fashion", "apparel",
            "footwear", "sneaker", "jewellery", "jewelry", "electronics",
            "appliance", "hardware store", "department store",
            // VI
            "lazada", "tiki", "siêu thị", "cửa hàng", "chợ", "thời trang",
            "bách hoá xanh", "winmart", "co.opmart",
            // ZH
            "购物", "商场", "淘宝", "京东", "拼多多", "天猫", "百货",
            "服装", "电器", "超市购物", "网购",
            // JA
            "ショッピング", "デパート", "ユニクロ", "通販", "量販店",
            "ドン・キホーテ", "家電", "衣料品",
            // KO
            "쇼핑", "백화점", "쿠팡", "지마켓", "11번가", "의류", "이마트",
            "홈플러스", "코스트코",
            // FR
            "magasin", "galerie", "vêtements", "monoprix", "carrefour",
            "leclerc", "fnac", "decathlon", "bricolage",
            // ES
            "centro comercial", "ropa", "moda", "corte inglés", "mercadona",
            "mediamarkt",
            // TH
            "ห้างสรรพสินค้า", "ร้านค้า", "ตลาด", "เสื้อผ้า", "บิ๊กซี",
            "เซ็นทรัล", "สยาม", "เทสโก้",
            // DE
            "kaufhaus", "drogerie", "kleidung", "mode", "rewe", "saturn",
            "baumarkt", "dm-", "rossmann", "douglas",
        ], "Shopping"),

        // ── BILLS ─────────────────────────────────────────────────────────────
        ([
            // Global / generic EN
            "electric", "electricity", "water bill", "gas bill", "phone bill",
            "internet bill", "broadband", "telecom", "utility", "monthly fee",
            "subscription", "insurance", "rent payment", "mortgage",
            "viettel", "vnpt", "mobifone", "vinaphone", "fpt telecom",
            // VI
            "tiền điện", "tiền nước", "hóa đơn", "wifi", "phí dịch vụ",
            "tiền nhà", "viettel", "vnpt", "fpt",
            // ZH
            "电费", "水费", "网费", "话费", "煤气费", "物业费", "宽带",
            "月租", "中国移动", "中国电信", "中国联通", "电话费",
            // JA
            "電気代", "水道代", "ガス代", "携帯代", "通信費", "電話代",
            "インターネット料", "光熱費", "ドコモ", "ソフトバンク", "au払い",
            // KO
            "전기요금", "수도요금", "가스요금", "인터넷요금", "통신비",
            "관리비", "kt요금", "sk텔레콤", "lg유플러스",
            // FR
            "électricité", "facture eau", "facture gaz", "abonnement",
            "orange", "sfr", "bouygues", "free mobile", "loyer",
            // ES
            "electricidad", "factura agua", "factura gas", "suscripción",
            "movistar", "vodafone", "orange", "endesa", "iberdrola",
            // TH
            "ค่าไฟ", "ค่าน้ำ", "ค่าอินเทอร์เน็ต", "ค่าโทรศัพท์", "ค่าบิล",
            "ทรูมูฟ", "เอไอเอส", "ดีแทค", "ค่าเช่า",
            // DE
            "stromrechnung", "wasserrechnung", "gasrechnung", "telekom",
            "vodafone de", "o2 rechnung", "miete", "nebenkosten",
        ], "Bills"),

        // ── HEALTH ────────────────────────────────────────────────────────────
        ([
            // Global / generic EN
            "hospital", "clinic", "pharmacy", "pharmacist", "doctor", "dental",
            "dentist", "drugstore", "medical", "health", "physio", "physiotherapy",
            "optician", "optometrist", "vet", "veterinary", "cvs", "walgreens", "boots",
            "chemist", "gp visit", "specialist", "radiology", "laboratory",
            // VI
            "thuốc", "bệnh viện", "phòng khám", "bác sĩ", "nha khoa",
            "nhà thuốc", "y tế", "xét nghiệm", "siêu âm",
            // ZH
            "医院", "药房", "诊所", "药店", "牙科", "体检", "医疗",
            "中医", "眼科", "检查费",
            // JA
            "病院", "薬局", "クリニック", "歯科", "健康診断", "調剤",
            "マツモトキヨシ", "ウエルシア", "眼科", "整形外科",
            // KO
            "병원", "약국", "치과", "건강검진", "한의원", "피부과",
            "안과", "정형외과", "내과",
            // FR
            "pharmacie", "médecin", "hôpital", "clinique", "dentiste",
            "médicament", "mutuelle", "infirmier", "kiné",
            // ES
            "farmacia", "médico", "hospital", "clínica", "dentista",
            "medicamento", "fisio", "parafarmacia",
            // TH
            "โรงพยาบาล", "ร้านขายยา", "คลินิก", "หมอ", "ทันตแพทย์",
            "ยา", "สุขภาพ", "บูทส์", "วัคซีน",
            // DE
            "apotheke", "arzt", "krankenhaus", "zahnarzt", "gesundheit",
            "medikament", "dm drogerie", "rossmann", "optiker", "physiotherapie",
        ], "Health"),

        // ── ENTERTAINMENT ─────────────────────────────────────────────────────
        ([
            // Global streaming / gaming / events
            "netflix", "spotify", "disney+", "disney plus", "hulu", "hbo",
            "apple music", "apple tv", "youtube premium", "twitch", "steam",
            "playstation", "xbox", "nintendo", "epic games", "riot games",
            "cinema", "movie ticket", "concert ticket", "event ticket",
            "theme park", "amusement", "bowling", "karaoke", "billiards",
            "escape room", "arcade",
            // VI
            "rạp chiếu", "phim", "trò chơi", "âm nhạc", "ca nhạc",
            "vui chơi", "karaoke", "bida", "game online",
            // ZH
            "电影院", "游戏", "音乐", "演唱会", "优酷", "爱奇艺",
            "腾讯视频", "哔哩哔哩", "ktv", "卡拉ok", "网游",
            // JA
            "映画館", "ゲーム", "コンサート", "カラオケ", "アニメ",
            "漫画", "ライブ", "遊園地", "ゲームセンター",
            // KO
            "영화관", "게임", "콘서트", "노래방", "오락실", "멜론",
            "지니뮤직", "스트리밍", "e스포츠",
            // FR
            "cinéma", "jeux vidéo", "concert", "spectacle", "loisirs",
            "parc d'attractions", "karaoké", "salle de jeux",
            // ES
            "cine", "videojuego", "concierto", "espectáculo", "parque",
            "ocio", "karaoke", "sala juego",
            // TH
            "ภาพยนตร์", "เกม", "คอนเสิร์ต", "สวนสนุก", "คาราโอเกะ",
            "บันเทิง", "สนามกีฬา", "โรงหนัง",
            // DE
            "kino", "spielhalle", "konzert", "freizeitpark", "bowlingbahn",
            "karaokelokal", "videospiel",
        ], "Entertainment"),
    ]

    // MARK: - MCC → category key

    /// ISO 18245 Merchant Category Codes → English category key.
    private func mccCategoryKey(_ mcc: Int) -> String? {
        switch mcc {
        // Food & Dining
        case 5411, 5412,            // grocery stores / supermarkets
             5811, 5812, 5813, 5814, // eating places, bars, fast food
             5441, 5451, 5462,       // candy, dairy, bakeries
             5499, 5422, 5431,       // misc food, meat, fruit
             5921:                   // package stores (beer/wine)
            return "Food"

        // Transport
        case 4111, 4112, 4121, 4131, // local/suburban transit, taxi, bus
             4784,                   // toll bridges
             5541, 5542,             // service stations / automated fuel
             7523,                   // automobile parking
             4415, 4511, 4411,       // water transport, air, cruise
             7512:                   // automobile rentals
            return "Transport"

        // Shopping
        case 5310, 5311, 5331, 5399, // discount stores, department stores, variety
             5600...5699,            // clothing & accessories
             5940...5945,            // sporting goods, hobby, book, music stores
             5946...5999,            // misc retail
             5065, 5045, 5722,       // electronics, computers, appliances
             5200, 5211, 5231, 5251: // home improvement, hardware, paint
            return "Shopping"

        // Bills & Utilities
        case 4812, 4813, 4814, 4816, // phone, fax, cable, computer services
             4899, 4900, 4911, 4924, // communications, utilities, electric, gas/water
             4941,                   // water supply
             6300, 6381, 6399,       // insurance
             6552:                   // land developers / real estate
            return "Bills"

        // Health
        case 8011...8099:            // health practitioners, hospitals, care
            return "Health"

        // Entertainment
        case 7832, 7922, 7929,       // movie theaters, theatrical/ticket agents, bands
             7932, 7933,             // billiard / bowling
             7941, 7991, 7992, 7993, // sports clubs, tourist attractions, golf, video games
             7994...7999,            // gambling, recreation, fitness
             7011, 7012:             // hotels / motels (travel)
            return "Entertainment"

        default:
            return nil
        }
    }
}
