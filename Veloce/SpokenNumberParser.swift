import Foundation

// MARK: - SpokenNumberParser
// Converts natural-language spoken amounts to Double values.
// Called by AIService.extractAmount() when all numeric-pattern matches fail.
//
// iOS speech recognition returns word-form numbers ~80% of the time
// ("twenty five dollars" instead of "25"). This parser bridges that gap.
//
// Language support:
//   • English – full word numbers, currency labels, decimal ("point"), fractions ("half")
//   • Vietnamese – full word numbers with section-based algorithm (trăm/nghìn/triệu/tỷ),
//                  mixed digit+unit ("50 nghìn"), compound forms ("hai mươi lăm")
//
// Design: pure, offline, zero-allocation hot path. No regex, no external APIs.

enum SpokenNumberParser {

    // MARK: - Public

    /// Parses a spoken-language amount string into a Double.
    /// Returns nil when no recognisable amount is found.
    static func parse(_ text: String) -> Double? {
        let t = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if let v = parseEnglish(t)    { return v }
        if let v = parseVietnamese(t) { return v }
        return nil
    }

    // MARK: - English ───────────────────────────────────────────────────────

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

    // Sub-unit fractional multipliers: "fifty cents" → 50 × 0.01 = 0.50
    private static let fractionalUnits: [String: Double] = [
        "cent": 0.01, "cents": 0.01,
        "penny": 0.01, "pence": 0.01,
        "satang": 0.01,   // Thai sub-unit
    ]

    // Currency labels that don't change the magnitude of the preceding number
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

        // Guard: require at least one recognisable English number word so we
        // don't accidentally consume Vietnamese or other-language input.
        let isNumberWord: (String) -> Bool = {
            ones[$0] != nil || tens[$0] != nil ||
            $0 == "hundred" || $0 == "thousand" || $0 == "million" || $0 == "billion" ||
            $0 == "half" || fractionalUnits[$0] != nil
        }
        guard tokens.contains(where: isNumberWord) else { return nil }

        // "half" → 0.5 (e.g. "half dollar", "half a")
        if let idx = tokens.firstIndex(of: "half") {
            let next = idx + 1 < tokens.count ? tokens[idx + 1] : nil
            if next == nil || wholeUnits.contains(next!) || next == "a" {
                return 0.5
            }
        }

        // "a hundred / thousand / …" → treat "a" as "one"
        for i in tokens.indices.dropLast() where tokens[i] == "a" {
            if ["hundred", "thousand", "million", "billion"].contains(tokens[i + 1]) {
                tokens[i] = "one"
            }
        }

        tokens = tokens.filter { !noiseEn.contains($0) }

        // ── Pattern: "X dollars [and Y cents]" ──
        if let unitIdx = tokens.firstIndex(where: { wholeUnits.contains($0) }), unitIdx > 0 {
            let wholePart = Array(tokens[0..<unitIdx])
            let rest      = Array(tokens[(unitIdx + 1)...])

            let wholeVal = sumEnWords(wholePart) ?? 0

            if let centIdx = rest.firstIndex(where: { fractionalUnits[$0] != nil }), centIdx > 0 {
                let centMult = fractionalUnits[rest[centIdx]] ?? 0.01
                let centVal  = (sumEnWords(Array(rest[0..<centIdx])) ?? 0) * centMult
                return wholeVal + centVal
            }
            if wholeVal > 0 { return wholeVal }
        }

        // ── Pattern: "Y cents / pence" (no whole unit) ──
        if let centIdx = tokens.firstIndex(where: { fractionalUnits[$0] != nil }), centIdx > 0 {
            let centMult = fractionalUnits[tokens[centIdx]] ?? 0.01
            if let v = sumEnWords(Array(tokens[0..<centIdx])) { return v * centMult }
        }

        // ── Pattern: "X point Y" decimal ("one point five" → 1.5) ──
        if let ptIdx = tokens.firstIndex(of: "point"), ptIdx > 0, ptIdx + 1 < tokens.count {
            let intTokens  = Array(tokens[0..<ptIdx]).filter { !wholeUnits.contains($0) }
            let fracTokens = Array(tokens[(ptIdx + 1)...]).filter { !wholeUnits.contains($0) }
            if let intPart = sumEnWords(intTokens) {
                return intPart + enDecimalFraction(fracTokens)
            }
        }

        // ── Fallback: plain word number, currency labels stripped ──
        return sumEnWords(tokens.filter { !wholeUnits.contains($0) })
    }

    /// Running-accumulator English word-number sum.
    /// "two thousand three hundred forty five" → 2345
    private static func sumEnWords(_ tokens: [String]) -> Double? {
        guard !tokens.isEmpty else { return nil }
        var total: Double   = 0
        var current: Double = 0
        var found           = false

        for t in tokens {
            if      let v = ones[t]  { current += v;                                          found = true }
            else if let v = tens[t]  { current += v;                                          found = true }
            else if t == "hundred"   { current  = (current == 0 ? 1 : current) * 100;         found = true }
            else if t == "thousand"  { total += (current == 0 ? 1 : current) * 1_000;         current = 0; found = true }
            else if t == "million"   { total += (current == 0 ? 1 : current) * 1_000_000;     current = 0; found = true }
            else if t == "billion"   { total += (current == 0 ? 1 : current) * 1_000_000_000; current = 0; found = true }
        }
        total += current
        return found ? total : nil
    }

    /// Decimal words → fraction: ["five"] → 0.5, ["seven", "five"] → 0.75
    private static func enDecimalFraction(_ tokens: [String]) -> Double {
        var digits = ""
        for t in tokens {
            if let v = ones[t], v < 10 { digits += "\(Int(v))" }
            else if let v = tens[t]    { digits += "\(Int(v))" }
        }
        guard !digits.isEmpty, let n = Double(digits) else { return 0 }
        return n / pow(10.0, Double(digits.count))
    }

    /// Splits on non-letter characters (hyphens become spaces first).
    /// Numeric characters are intentionally excluded so digit+unit combos
    /// ("50 nghìn") don't bleed into the English parser.
    private static func enTokenize(_ text: String) -> [String] {
        text.replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - Vietnamese ────────────────────────────────────────────────────

    private static let viDigits: [String: Double] = [
        "không": 0,
        "một": 1, "hai": 2, "ba": 3, "bốn": 4,
        "năm": 5, "lăm": 5,   // "lăm" = 5 in compound tens position
        "sáu": 6, "bảy": 7, "tám": 8, "chín": 9,
    ]

    // Words that guarantee this is a Vietnamese number context
    private static let viTriggers: Set<String> = [
        "không", "một", "hai", "ba", "bốn", "năm", "lăm",
        "sáu", "bảy", "tám", "chín",
        "mười", "mươi", "trăm", "nghìn", "ngàn", "triệu", "tỷ",
    ]

    // Labels stripped before parsing
    private static let viNoise: Set<String> = [
        "đồng", "đ", "vnd", "tiền", "hết", "mất", "tốn", "chi", "trả",
    ]

    private static func parseVietnamese(_ text: String) -> Double? {
        // Tokenise preserving numeric tokens: "50 nghìn" → ["50", "nghìn"]
        let tokens = text.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]{}")) }
            .filter { !$0.isEmpty }

        // Require at least one Vietnamese trigger word
        guard tokens.contains(where: { viTriggers.contains($0) }) else { return nil }

        let cleaned = tokens.filter { !viNoise.contains($0) }
        return sumViWords(cleaned)
    }

    /// Section-based Vietnamese number sum.
    ///
    /// Splits the token stream on large multipliers (tỷ / triệu / nghìn / ngàn).
    /// Each preceding section is parsed as a ≤999 sub-number, then multiplied.
    ///
    ///   "một triệu hai trăm nghìn" →
    ///     section ["một"] × 1_000_000  = 1_000_000
    ///   + section ["hai", "trăm"] × 1_000 = 200_000
    ///   = 1_200_000
    private static func sumViWords(_ tokens: [String]) -> Double? {
        let largeMults: [(word: String, mult: Double)] = [
            ("tỷ",    1_000_000_000),
            ("triệu", 1_000_000),
            ("nghìn", 1_000),
            ("ngàn",  1_000),
        ]

        var total: Double    = 0
        var section: [String] = []
        var found = false

        for token in tokens {
            if let m = largeMults.first(where: { $0.word == token })?.mult {
                let v = viSection(section) ?? 1   // bare "nghìn" = 1 × 1000
                total += v * m
                section = []
                found = true
            } else {
                section.append(token)
            }
        }

        // Trailing section with no large multiplier (e.g. lone hundreds/tens/ones)
        if let v = viSection(section), v > 0 {
            total += v
            found = true
        }

        return found ? total : nil
    }

    /// Parses a Vietnamese sub-section (0–999 range).
    ///
    ///   ["hai", "trăm", "năm", "mươi"]    → 250
    ///   ["mười", "hai"]                    → 12
    ///   ["50"]                             → 50  (numeric token pass-through)
    private static func viSection(_ tokens: [String]) -> Double? {
        var result: Double = 0
        var digit: Double  = 0
        var hadDigit       = false
        var found          = false
        var i              = 0

        while i < tokens.count {
            let t = tokens[i]

            if let d = viDigits[t] {
                digit = d; hadDigit = true
                i += 1

            } else if t == "mười" {
                // "mười" alone = 10; "mười X" = 10 + X (handles 11–19 within a section)
                result += hadDigit ? digit * 10 : 10
                digit = 0; hadDigit = false; found = true
                i += 1
                if i < tokens.count, let d = viDigits[tokens[i]] {
                    result += d; i += 1
                }

            } else if t == "mươi" {
                // "X mươi" = X × 10, optionally followed by ones digit
                result += (hadDigit ? digit : 1) * 10
                digit = 0; hadDigit = false; found = true
                i += 1
                if i < tokens.count, let d = viDigits[tokens[i]], d > 0 {
                    result += d; i += 1
                }

            } else if t == "trăm" {
                result += (hadDigit ? digit : 1) * 100
                digit = 0; hadDigit = false; found = true
                i += 1

            } else if let v = Double(t) {
                // Numeric token mixed into Vietnamese text ("50 nghìn")
                digit = v; hadDigit = true
                i += 1

            } else {
                // "lẻ" (and), unknown words — skip silently
                i += 1
            }
        }

        if hadDigit { result += digit; found = true }
        return found ? result : nil
    }
}
