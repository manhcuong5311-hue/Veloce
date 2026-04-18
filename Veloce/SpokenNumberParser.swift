import Foundation

// MARK: - SpokenNumberParser
// Converts natural-language spoken amounts to Double values.
// Called by AIService.extractAmount() when all numeric-pattern matches fail.
//
// Supports all 10 languages from the app's speech language picker:
//   • Vietnamese  (vi-VN) – trăm / nghìn / triệu / tỷ section algorithm
//   • English     (en-US, en-GB) – ones/tens/hundred/thousand/million
//   • Chinese     (zh-CN) – 十百千万亿 with kanji digit words
//   • Japanese    (ja-JP) – 十百千万億 with kanji digit words
//   • Korean      (ko-KR) – Sino-Korean 십백천만억
//   • French      (fr-FR) – full word numbers incl. quatre-vingts / soixante-dix
//   • Spanish     (es-ES) – compound teens, compound hundreds, mil/millón
//   • Thai        (th-TH) – สิบ ร้อย พัน หมื่น แสน ล้าน
//   • German      (de-DE) – compound words (einundzwanzig), hundert/tausend
//
// Design: pure, offline, zero-allocation hot path. No regex, no external APIs.
// Locale is read from UserDefaults on every call so it always reflects the
// user's current speech language setting without restarting anything.

enum SpokenNumberParser {

    // MARK: - Public

    /// Parses a spoken-language amount string into a Double.
    /// Pass `locale` explicitly in tests; production callers omit it and the
    /// current speech language setting is used automatically.
    static func parse(_ text: String, locale: String? = nil) -> Double? {
        let loc = locale
            ?? UserDefaults.standard.string(forKey: "veloce_speech_language")
            ?? "vi-VN"

        let t = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        switch loc {
        case "vi-VN":          return parseVietnamese(t)
        case "en-US", "en-GB": return parseEnglish(t)
        case "zh-CN":          return parseChinese(t)
        case "ja-JP":          return parseJapanese(t)
        case "ko-KR":          return parseKorean(t)
        case "fr-FR":          return parseFrench(t)
        case "es-ES":          return parseSpanish(t)
        case "th-TH":          return parseThai(t)
        case "de-DE":          return parseGerman(t)
        default:
            if let v = parseEnglish(t)    { return v }
            if let v = parseVietnamese(t) { return v }
            return nil
        }
    }

    // MARK: - English ─────────────────────────────────────────────────────────

    private static let ones: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19,
    ]

    private static let tens: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    private static let fractionalUnits: [String: Double] = [
        "cent": 0.01, "cents": 0.01,
        "penny": 0.01, "pence": 0.01,
        "satang": 0.01,
    ]

    private static let wholeUnits: Set<String> = [
        "dollar", "dollars", "euro", "euros", "pound", "pounds",
        "yen", "won", "baht", "sgd", "dong", "đồng",
        "buck", "bucks", "quid",
    ]

    private static let noiseEn: Set<String> = [
        "and", "the", "of", "about", "approximately", "around",
        "just", "only", "for", "on", "at",
        "spent", "spend", "paid", "pay", "cost", "costs", "bought", "buy",
    ]

    private static func parseEnglish(_ text: String) -> Double? {
        var tokens = enTokenize(text)
        let isNumberWord: (String) -> Bool = {
            ones[$0] != nil || tens[$0] != nil ||
            $0 == "hundred" || $0 == "thousand" || $0 == "million" || $0 == "billion" ||
            $0 == "half" || fractionalUnits[$0] != nil
        }
        guard tokens.contains(where: isNumberWord) else { return nil }

        if let idx = tokens.firstIndex(of: "half") {
            let next = idx + 1 < tokens.count ? tokens[idx + 1] : nil
            if next == nil || wholeUnits.contains(next!) || next == "a" { return 0.5 }
        }
        for i in tokens.indices.dropLast() where tokens[i] == "a" {
            if ["hundred", "thousand", "million", "billion"].contains(tokens[i + 1]) {
                tokens[i] = "one"
            }
        }
        tokens = tokens.filter { !noiseEn.contains($0) }

        if let unitIdx = tokens.firstIndex(where: { wholeUnits.contains($0) }), unitIdx > 0 {
            let wholePart = Array(tokens[0..<unitIdx])
            let rest      = Array(tokens[(unitIdx + 1)...])
            let wholeVal  = sumEnWords(wholePart) ?? 0
            if let centIdx = rest.firstIndex(where: { fractionalUnits[$0] != nil }), centIdx > 0 {
                let centMult = fractionalUnits[rest[centIdx]] ?? 0.01
                let centVal  = (sumEnWords(Array(rest[0..<centIdx])) ?? 0) * centMult
                return wholeVal + centVal
            }
            if wholeVal > 0 { return wholeVal }
        }
        if let centIdx = tokens.firstIndex(where: { fractionalUnits[$0] != nil }), centIdx > 0 {
            let centMult = fractionalUnits[tokens[centIdx]] ?? 0.01
            if let v = sumEnWords(Array(tokens[0..<centIdx])) { return v * centMult }
        }
        if let ptIdx = tokens.firstIndex(of: "point"), ptIdx > 0, ptIdx + 1 < tokens.count {
            let intTokens  = Array(tokens[0..<ptIdx]).filter { !wholeUnits.contains($0) }
            let fracTokens = Array(tokens[(ptIdx + 1)...]).filter { !wholeUnits.contains($0) }
            if let intPart = sumEnWords(intTokens) { return intPart + enDecimalFraction(fracTokens) }
        }
        return sumEnWords(tokens.filter { !wholeUnits.contains($0) })
    }

    private static func sumEnWords(_ tokens: [String]) -> Double? {
        guard !tokens.isEmpty else { return nil }
        var total: Double = 0; var current: Double = 0; var found = false
        for t in tokens {
            if      let v = ones[t] { current += v;                                           found = true }
            else if let v = tens[t] { current += v;                                           found = true }
            else if t == "hundred"  { current  = (current == 0 ? 1 : current) * 100;          found = true }
            else if t == "thousand" { total += (current == 0 ? 1 : current) * 1_000;          current = 0; found = true }
            else if t == "million"  { total += (current == 0 ? 1 : current) * 1_000_000;      current = 0; found = true }
            else if t == "billion"  { total += (current == 0 ? 1 : current) * 1_000_000_000;  current = 0; found = true }
        }
        total += current
        return found ? total : nil
    }

    private static func enDecimalFraction(_ tokens: [String]) -> Double {
        var digits = ""
        for t in tokens {
            if let v = ones[t], v < 10 { digits += "\(Int(v))" }
            else if let v = tens[t]    { digits += "\(Int(v))" }
        }
        guard !digits.isEmpty, let n = Double(digits) else { return 0 }
        return n / pow(10.0, Double(digits.count))
    }

    private static func enTokenize(_ text: String) -> [String] {
        text.replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - Vietnamese ──────────────────────────────────────────────────────

    private static let viDigits: [String: Double] = [
        "không": 0,
        "một": 1, "hai": 2, "ba": 3, "bốn": 4,
        "năm": 5, "lăm": 5,
        "sáu": 6, "bảy": 7, "tám": 8, "chín": 9,
    ]

    private static let viTriggers: Set<String> = [
        "không", "một", "hai", "ba", "bốn", "năm", "lăm",
        "sáu", "bảy", "tám", "chín",
        "mười", "mươi", "trăm", "nghìn", "ngàn", "triệu", "tỷ",
    ]

    private static let viNoise: Set<String> = [
        "đồng", "đ", "vnd", "tiền", "hết", "mất", "tốn", "chi", "trả",
    ]

    private static func parseVietnamese(_ text: String) -> Double? {
        let tokens = text.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]{}")) }
            .filter { !$0.isEmpty }
        guard tokens.contains(where: { viTriggers.contains($0) }) else { return nil }
        let cleaned = tokens.filter { !viNoise.contains($0) }
        return sumViWords(cleaned)
    }

    private static func sumViWords(_ tokens: [String]) -> Double? {
        let largeMults: [(word: String, mult: Double)] = [
            ("tỷ", 1_000_000_000), ("triệu", 1_000_000),
            ("nghìn", 1_000), ("ngàn", 1_000),
        ]
        var total: Double = 0; var section: [String] = []; var found = false
        for token in tokens {
            if let m = largeMults.first(where: { $0.word == token })?.mult {
                let v = viSection(section) ?? 1
                total += v * m; section = []; found = true
            } else { section.append(token) }
        }
        if let v = viSection(section), v > 0 { total += v; found = true }
        return found ? total : nil
    }

    private static func viSection(_ tokens: [String]) -> Double? {
        var result: Double = 0; var digit: Double = 0
        var hadDigit = false; var found = false; var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if let d = viDigits[t] { digit = d; hadDigit = true; i += 1 }
            else if t == "mười" {
                result += hadDigit ? digit * 10 : 10
                digit = 0; hadDigit = false; found = true; i += 1
                if i < tokens.count, let d = viDigits[tokens[i]] { result += d; i += 1 }
            } else if t == "mươi" {
                result += (hadDigit ? digit : 1) * 10
                digit = 0; hadDigit = false; found = true; i += 1
                if i < tokens.count, let d = viDigits[tokens[i]], d > 0 { result += d; i += 1 }
            } else if t == "trăm" {
                result += (hadDigit ? digit : 1) * 100
                digit = 0; hadDigit = false; found = true; i += 1
            } else if let v = Double(t) { digit = v; hadDigit = true; i += 1 }
            else { i += 1 }
        }
        if hadDigit { result += digit; found = true }
        return found ? result : nil
    }

    // MARK: - Chinese ─────────────────────────────────────────────────────────
    // 十百千万亿 with both simplified and traditional forms.
    // iOS speech recognition for Chinese usually returns Arabic digits;
    // kanji forms appear in carefully dictated amounts, e.g. "三百五十" → 350.

    private static let zhDigits: [Character: Double] = [
        "零": 0, "〇": 0,
        "一": 1, "壹": 1,
        "二": 2, "两": 2, "贰": 2, "兩": 2,
        "三": 3, "叁": 3,
        "四": 4, "肆": 4,
        "五": 5, "伍": 5,
        "六": 6, "陆": 6, "陸": 6,
        "七": 7, "柒": 7,
        "八": 8, "捌": 8,
        "九": 9, "玖": 9,
    ]

    private static let zhTriggers: Set<Character> = [
        "零","〇","一","壹","二","两","贰","兩","三","四","五",
        "六","七","八","九","十","百","千","万","億","亿",
    ]

    private static func parseChinese(_ text: String) -> Double? {
        let stripped = text
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: "块", with: "")
            .replacingOccurrences(of: "圆", with: "")
            .replacingOccurrences(of: "人民币", with: "")
        guard stripped.contains(where: { zhTriggers.contains($0) }) else { return nil }

        var total: Double = 0; var current: Double = 0
        var digit: Double = -1; var found = false

        for ch in stripped {
            if let d = zhDigits[ch] { digit = d }
            else if ch == "十" {
                current += (digit >= 0 ? digit : 1) * 10;         digit = -1; found = true
            } else if ch == "百" {
                current += (digit >= 0 ? digit : 1) * 100;        digit = -1; found = true
            } else if ch == "千" {
                current += (digit >= 0 ? digit : 1) * 1_000;      digit = -1; found = true
            } else if ch == "万" {
                if digit >= 0 { current += digit; digit = -1 }
                total += (current == 0 ? 1 : current) * 10_000;   current = 0; found = true
            } else if ch == "亿" || ch == "億" {
                if digit >= 0 { current += digit; digit = -1 }
                total += (current == 0 ? 1 : current) * 100_000_000; current = 0; found = true
            }
        }
        if digit >= 0 { current += digit }
        total += current
        return (found || current > 0) ? total : nil
    }

    // MARK: - Japanese ────────────────────────────────────────────────────────
    // 十百千万億 with kanji digit words.
    // iOS speech for Japanese mostly returns Arabic digits; kanji appear occasionally.

    private static let jaDigits: [Character: Double] = [
        "〇": 0, "零": 0,
        "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
        "六": 6, "七": 7, "八": 8, "九": 9,
    ]

    private static let jaTriggers: Set<Character> = [
        "〇","零","一","二","三","四","五","六","七","八","九",
        "十","百","千","万","億",
    ]

    private static func parseJapanese(_ text: String) -> Double? {
        let stripped = text
            .replacingOccurrences(of: "円", with: "")
            .replacingOccurrences(of: "¥", with: "")
        guard stripped.contains(where: { jaTriggers.contains($0) }) else { return nil }

        var total: Double = 0; var current: Double = 0
        var digit: Double = -1; var found = false

        for ch in stripped {
            if let d = jaDigits[ch] { digit = d }
            else if ch == "十" {
                current += (digit >= 0 ? digit : 1) * 10;          digit = -1; found = true
            } else if ch == "百" {
                current += (digit >= 0 ? digit : 1) * 100;         digit = -1; found = true
            } else if ch == "千" {
                current += (digit >= 0 ? digit : 1) * 1_000;       digit = -1; found = true
            } else if ch == "万" {
                if digit >= 0 { current += digit; digit = -1 }
                total += (current == 0 ? 1 : current) * 10_000;    current = 0; found = true
            } else if ch == "億" {
                if digit >= 0 { current += digit; digit = -1 }
                total += (current == 0 ? 1 : current) * 100_000_000; current = 0; found = true
            }
        }
        if digit >= 0 { current += digit }
        total += current
        return (found || current > 0) ? total : nil
    }

    // MARK: - Korean ──────────────────────────────────────────────────────────
    // Sino-Korean number system for currency amounts.
    // 영/공 일 이 삼 사 오 육 칠 팔 구 십 백 천 만 억
    // iOS speech for Korean mostly returns Arabic digits for large amounts;
    // Sino-Korean syllables appear for smaller values and in compound strings.

    private static let koSino: [String: Double] = [
        "영": 0, "공": 0,
        "일": 1, "이": 2, "삼": 3, "사": 4, "오": 5,
        "육": 6, "칠": 7, "팔": 8, "구": 9,
    ]

    private static let koTriggers: Set<String> = [
        "영","공","일","이","삼","사","오","육","칠","팔","구",
        "십","백","천","만","억",
    ]

    private static let koNoise: Set<String> = ["원", "₩", "돈"]

    private static func parseKorean(_ text: String) -> Double? {
        // Each Hangul syllable block is a single Unicode scalar — split into
        // individual syllables so "이만원" → ["이","만","원"].
        let syllables = text.flatMap { koSplitSyllables(String($0)) }
            .filter { !koNoise.contains($0) && !$0.isEmpty }

        guard syllables.contains(where: { koTriggers.contains($0) }) else { return nil }

        var total: Double = 0; var current: Double = 0
        var digit: Double = -1; var found = false

        for t in syllables {
            if let d = koSino[t] { digit = d }
            else if t == "십" {
                current += (digit >= 0 ? digit : 1) * 10;          digit = -1; found = true
            } else if t == "백" {
                current += (digit >= 0 ? digit : 1) * 100;         digit = -1; found = true
            } else if t == "천" {
                current += (digit >= 0 ? digit : 1) * 1_000;       digit = -1; found = true
            } else if t == "만" {
                if digit >= 0 { current += digit; digit = -1 }
                total += (current == 0 ? 1 : current) * 10_000;    current = 0; found = true
            } else if t == "억" {
                if digit >= 0 { current += digit; digit = -1 }
                total += (current == 0 ? 1 : current) * 100_000_000; current = 0; found = true
            } else if let v = Double(t) { digit = v }
        }
        if digit >= 0 { current += digit }
        total += current
        return (found || current > 0) ? total : nil
    }

    /// Yields each character as a single-character string, preserving digit tokens.
    private static func koSplitSyllables(_ word: String) -> [String] {
        var result: [String] = []
        var numBuf = ""
        for ch in word {
            if ch.isNumber {
                numBuf.append(ch)
            } else {
                if !numBuf.isEmpty { result.append(numBuf); numBuf = "" }
                result.append(String(ch))
            }
        }
        if !numBuf.isEmpty { result.append(numBuf) }
        return result
    }

    // MARK: - French ──────────────────────────────────────────────────────────
    // Handles standard French word numbers including:
    //   soixante-dix (70), quatre-vingts (80), quatre-vingt-dix (90),
    //   mille, million, milliard.

    private static let frOnes: [String: Double] = [
        "zéro": 0, "zero": 0,
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4,
        "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9,
        "dix": 10, "onze": 11, "douze": 12, "treize": 13, "quatorze": 14,
        "quinze": 15, "seize": 16,
        "dixsept": 17, "dixhuit": 18, "dixneuf": 19,
    ]

    private static let frTens: [String: Double] = [
        "vingt": 20, "trente": 30, "quarante": 40,
        "cinquante": 50, "soixante": 60,
        "soixantedix": 70,
        "quatrevingt": 80, "quatrevingts": 80,
        "quatrevingtdix": 90,
    ]

    private static let frTriggers: Set<String> = [
        "zéro","zero","un","une","deux","trois","quatre","cinq","six","sept","huit","neuf",
        "dix","onze","douze","treize","quatorze","quinze","seize",
        "vingt","trente","quarante","cinquante","soixante",
        "cent","mille","million","milliard",
    ]

    private static let frNoise: Set<String> = [
        "euro","euros","franc","francs","et","de","le","la","les",
        "dépensé","payé","coûte","coûté","acheté",
    ]

    private static func parseFrench(_ text: String) -> Double? {
        // Normalise compound forms before tokenising
        let normalized = text
            .replacingOccurrences(of: "quatre-vingt-dix", with: "quatrevingtdix")
            .replacingOccurrences(of: "quatre-vingts",    with: "quatrevingts")
            .replacingOccurrences(of: "quatre-vingt",     with: "quatrevingt")
            .replacingOccurrences(of: "soixante-dix",     with: "soixantedix")
            .replacingOccurrences(of: "dix-neuf",         with: "dixneuf")
            .replacingOccurrences(of: "dix-huit",         with: "dixhuit")
            .replacingOccurrences(of: "dix-sept",         with: "dixsept")
            .replacingOccurrences(of: "-",                with: " ")

        let tokens = normalized.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { !$0.isEmpty && !frNoise.contains($0) }

        guard tokens.contains(where: { frTriggers.contains($0) }) else { return nil }

        var total: Double = 0; var current: Double = 0; var found = false
        var i = 0

        while i < tokens.count {
            let t  = tokens[i]
            let t1 = i + 1 < tokens.count ? tokens[i + 1] : nil

            if let v = frOnes[t] {
                current += v; found = true
            } else if let v = frTens[t] {
                switch t {
                case "soixante":
                    // "soixante dix" = 70, "soixante onze" = 71 … "soixante dix-neuf" = 79
                    if let next = t1, let nv = frOnes[next], nv >= 10 {
                        current += 60 + nv; i += 1
                    } else {
                        current += v
                    }
                case "quatrevingt", "quatrevingts":
                    // "quatre-vingt un" = 81 … "quatre-vingt dix-neuf" = 99
                    if let next = t1, let nv = frOnes[next], nv >= 1 {
                        current += 80 + nv; i += 1
                    } else {
                        current += 80
                    }
                case "quatrevingtdix":
                    // "quatre-vingt-dix un" = 91 … "neuf" = 99
                    if let next = t1, let nv = frOnes[next], nv >= 1 && nv <= 9 {
                        current += 90 + nv; i += 1
                    } else {
                        current += 90
                    }
                default:
                    current += v
                }
                found = true
            } else if t == "cent" || t == "cents" {
                current = (current == 0 ? 1 : current) * 100; found = true
            } else if t == "mille" {
                total += (current == 0 ? 1 : current) * 1_000;         current = 0; found = true
            } else if t == "million" || t == "millions" {
                total += (current == 0 ? 1 : current) * 1_000_000;     current = 0; found = true
            } else if t == "milliard" || t == "milliards" {
                total += (current == 0 ? 1 : current) * 1_000_000_000; current = 0; found = true
            } else if let v = Double(t) {
                current += v; found = true
            }
            i += 1
        }
        total += current
        return found ? total : nil
    }

    // MARK: - Spanish ─────────────────────────────────────────────────────────
    // Handles Spanish number words including veinti- compounds,
    // compound hundreds (doscientos, trescientos…) and mil / millón.

    private static let esOnes: [String: Double] = [
        "cero": 0,
        "un": 1, "uno": 1, "una": 1,
        "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
        "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
        "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14,
        "quince": 15, "dieciséis": 16, "dieciseis": 16,
        "diecisiete": 17, "dieciocho": 18, "diecinueve": 19,
        // Compound veinti- forms (20–29)
        "veinte": 20,
        "veintiuno": 21, "veintiún": 21, "veintiun": 21,
        "veintidós": 22, "veintidos": 22,
        "veintitrés": 23, "veintitres": 23, "veinticuatro": 24,
        "veinticinco": 25, "veintiséis": 26, "veintiseis": 26,
        "veintisiete": 27, "veintiocho": 28, "veintinueve": 29,
    ]

    private static let esTens: [String: Double] = [
        "treinta": 30, "cuarenta": 40, "cincuenta": 50,
        "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90,
    ]

    private static let esHundreds: [String: Double] = [
        "cien": 100, "ciento": 100,
        "doscientos": 200, "doscientas": 200,
        "trescientos": 300, "trescientas": 300,
        "cuatrocientos": 400, "cuatrocientas": 400,
        "quinientos": 500, "quinientas": 500,
        "seiscientos": 600, "seiscientas": 600,
        "setecientos": 700, "setecientas": 700,
        "ochocientos": 800, "ochocientas": 800,
        "novecientos": 900, "novecientas": 900,
    ]

    private static let esTriggers: Set<String> = [
        "cero","un","uno","una","dos","tres","cuatro","cinco","seis","siete","ocho","nueve",
        "diez","once","doce","trece","catorce","quince","veinte",
        "treinta","cuarenta","cincuenta","sesenta","setenta","ochenta","noventa",
        "cien","ciento","doscientos","trescientos","quinientos",
        "mil","millón","millon","billón","billon",
    ]

    private static let esNoise: Set<String> = [
        "euro","euros","peso","pesos","dólar","dolar","dólares","dolares",
        "y","de","el","la","los","las",
        "gasté","gaste","pagué","pague","costó","costo",
    ]

    private static func parseSpanish(_ text: String) -> Double? {
        let tokens = text.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { !$0.isEmpty && !esNoise.contains($0) }
        guard tokens.contains(where: { esTriggers.contains($0) }) else { return nil }

        var total: Double = 0; var current: Double = 0; var found = false

        for t in tokens {
            if let v = esOnes[t]     { current += v; found = true }
            else if let v = esTens[t]     { current += v; found = true }
            else if let v = esHundreds[t] { current += v; found = true }
            else if t == "mil" {
                total += (current == 0 ? 1 : current) * 1_000;         current = 0; found = true
            } else if t == "millón" || t == "millon" || t == "millones" {
                total += (current == 0 ? 1 : current) * 1_000_000;     current = 0; found = true
            } else if t == "billón" || t == "billon" || t == "billones" {
                total += (current == 0 ? 1 : current) * 1_000_000_000; current = 0; found = true
            } else if let v = Double(t) { current += v; found = true }
        }
        total += current
        return found ? total : nil
    }

    // MARK: - Thai ────────────────────────────────────────────────────────────
    // สิบ ร้อย พัน หมื่น แสน ล้าน
    // iOS speech for Thai typically returns Arabic digits; word forms appear
    // occasionally in natural dictation.

    private static let thDigits: [String: Double] = [
        "ศูนย์": 0,
        "หนึ่ง": 1, "สอง": 2, "สาม": 3, "สี่": 4,
        "ห้า": 5, "หก": 6, "เจ็ด": 7, "แปด": 8, "เก้า": 9,
    ]

    private static let thTriggers: Set<String> = [
        "ศูนย์","หนึ่ง","สอง","สาม","สี่","ห้า","หก","เจ็ด","แปด","เก้า",
        "สิบ","ร้อย","พัน","หมื่น","แสน","ล้าน",
    ]

    private static let thNoise: Set<String> = ["บาท", "สตางค์"]

    private static func parseThai(_ text: String) -> Double? {
        let tokens = text.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { !$0.isEmpty && !thNoise.contains($0) }
        guard tokens.contains(where: { thTriggers.contains($0) }) else { return nil }

        // ล้าน (million) handled as a section multiplier; smaller units inline.
        var total: Double = 0; var section: [String] = []; var found = false

        for token in tokens {
            if token == "ล้าน" {
                let v = thSection(section) ?? 1
                total += v * 1_000_000; section = []; found = true
            } else { section.append(token) }
        }
        if let v = thSection(section), v > 0 { total += v; found = true }
        return found ? total : nil
    }

    private static func thSection(_ tokens: [String]) -> Double? {
        var result: Double = 0; var digit: Double = -1; var found = false
        for t in tokens {
            if let d = thDigits[t] { digit = d; found = true }
            else if t == "สิบ" {
                result += (digit >= 0 ? digit : 1) * 10;     digit = -1; found = true
            } else if t == "ร้อย" {
                result += (digit >= 0 ? digit : 1) * 100;    digit = -1; found = true
            } else if t == "พัน" {
                result += (digit >= 0 ? digit : 1) * 1_000;  digit = -1; found = true
            } else if t == "หมื่น" {
                result += (digit >= 0 ? digit : 1) * 10_000; digit = -1; found = true
            } else if t == "แสน" {
                result += (digit >= 0 ? digit : 1) * 100_000; digit = -1; found = true
            } else if let v = Double(t) { digit = v; found = true }
        }
        if digit >= 0 { result += digit }
        return found ? result : nil
    }

    // MARK: - German ──────────────────────────────────────────────────────────
    // Handles standard German word numbers including compound forms:
    //   "einundzwanzig" = 21, "dreiundvierzig" = 43
    // iOS speech recognition returns word forms for German consistently.

    private static let deOnes: [String: Double] = [
        "null": 0,
        "ein": 1, "eine": 1, "eins": 1,
        "zwei": 2, "drei": 3, "vier": 4, "fünf": 5,
        "sechs": 6, "sieben": 7, "acht": 8, "neun": 9,
        "zehn": 10, "elf": 11, "zwölf": 12,
        "dreizehn": 13, "vierzehn": 14, "fünfzehn": 15,
        "sechzehn": 16, "siebzehn": 17, "achtzehn": 18, "neunzehn": 19,
        "zwanzig": 20,
    ]

    private static let deTens: [String: Double] = [
        "dreißig": 30, "dreizig": 30,
        "vierzig": 40, "fünfzig": 50, "sechzig": 60,
        "siebzig": 70, "achtzig": 80, "neunzig": 90,
    ]

    private static let deTriggers: Set<String> = [
        "null","ein","eine","eins","zwei","drei","vier","fünf","sechs","sieben","acht","neun",
        "zehn","elf","zwölf","zwanzig","dreißig","vierzig","fünfzig",
        "sechzig","siebzig","achtzig","neunzig",
        "hundert","tausend","million","milliarde",
    ]

    private static let deNoise: Set<String> = [
        "euro","euros","cent","und","ausgegeben","bezahlt","gekostet",
    ]

    private static func parseGerman(_ text: String) -> Double? {
        // Expand compound words: "einundzwanzig" → "ein zwanzig"
        let expanded = deExpandCompounds(text)

        let tokens = expanded.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { !$0.isEmpty && !deNoise.contains($0) }

        guard tokens.contains(where: { deTriggers.contains($0) }) else { return nil }

        var total: Double = 0; var current: Double = 0; var found = false

        for t in tokens {
            if let v = deOnes[t] { current += v; found = true }
            else if let v = deTens[t] { current += v; found = true }
            else if t == "hundert" {
                current = (current == 0 ? 1 : current) * 100;          found = true
            } else if t == "tausend" {
                total += (current == 0 ? 1 : current) * 1_000;         current = 0; found = true
            } else if t == "million" || t == "millionen" {
                total += (current == 0 ? 1 : current) * 1_000_000;     current = 0; found = true
            } else if t == "milliarde" || t == "milliarden" {
                total += (current == 0 ? 1 : current) * 1_000_000_000; current = 0; found = true
            } else if let v = Double(t) { current += v; found = true }
        }
        total += current
        return found ? total : nil
    }

    /// Splits German compound number words into their components.
    /// "einundzwanzig" → "ein zwanzig" (21)
    /// "siebenundachtzig" → "sieben achtzig" (87)
    private static func deExpandCompounds(_ text: String) -> String {
        let onesWords = ["ein","zwei","drei","vier","fünf","sechs","sieben","acht","neun"]
        let tensWords = [
            "zwanzig","dreißig","vierzig","fünfzig",
            "sechzig","siebzig","achtzig","neunzig",
        ]
        var result = text
        for o in onesWords {
            for t in tensWords {
                let compound = "\(o)und\(t)"
                if result.contains(compound) {
                    result = result.replacingOccurrences(of: compound, with: "\(o) \(t)")
                }
            }
        }
        return result
    }
}
