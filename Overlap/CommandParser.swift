import Foundation

/// Result of parsing a command-bar query.
struct ParsedCommand: Equatable {
    struct MonthDay: Equatable {
        var month: Int
        var day: Int
        init(_ month: Int, _ day: Int) { self.month = month; self.day = day }
    }
    enum Intent: Equatable {
        /// Bare city list: add each place.
        case addPlaces([CityCatalog.Entry])
        /// A time (optionally in a city, on a date): jump the view there.
        case jump(hour: Int, minute: Int,
                  city: CityCatalog.Entry?,
                  dayOffset: Int?,
                  weekday: Int?,
                  monthDay: MonthDay?)
    }
    var intent: Intent
}

/// Natural-language parser for the command bar. Pure; no UI deps.
enum CommandParser {
    private static let fillers: Set<String> = [
        "call", "with", "and", "in", "at", "meeting", "the", "a", "on",
    ]
    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]
    private static let weekdays: [String: Int] = [
        "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7,
    ]

    static func parse(_ input: String, catalog: CityCatalog,
                      referenceDate: Date, homeTZ: TimeZone) -> ParsedCommand? {
        let tokens = input.lowercased()
            .components(separatedBy: CharacterSet.whitespaces.union(.init(charactersIn: ",")))
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }

        var time: (hour: Int, minute: Int)?
        var dayOffset: Int?
        var weekday: Int?
        var monthDay: ParsedCommand.MonthDay?
        var nextFlag = false
        var consumed = Set<Int>()

        // Time tokens (merged digits+suffix first, then split "3 pm").
        for (i, t) in tokens.enumerated() where time == nil {
            if t == "noon" { time = (12, 0); consumed.insert(i); break }
            if t == "midnight" { time = (0, 0); consumed.insert(i); break }
            if let p = parseTime(t) { time = p; consumed.insert(i); break }
            // "3" followed by "pm"/"a"/"p"
            if let h = Int(t), (0...23).contains(h), i + 1 < tokens.count,
               let suffix = ampm(tokens[i + 1]) {
                let hh = h == 12 ? (suffix == .am ? 0 : 12)
                                : h + (suffix == .pm && h < 12 ? 12 : 0)
                time = (hh, 0)
                consumed.formUnion([i, i + 1])
                break
            }
        }

        /// First token index after `i` that is unconsumed and numeric in 1...31.
        func nextDayNum(after i: Int) -> (Int, Int)? {
            for j in (i + 1)..<tokens.count where !consumed.contains(j) {
                if let d = Int(tokens[j]), (1...31).contains(d) { return (j, d) }
            }
            return nil
        }
        /// First token index after `i` that is an unconsumed month name.
        func nextMonth(after i: Int) -> (Int, Int)? {
            for j in (i + 1)..<tokens.count where !consumed.contains(j) {
                if let m = months[tokens[j]] { return (j, m) }
            }
            return nil
        }

        // Date tokens.
        for (i, t) in tokens.enumerated() where !consumed.contains(i) {
            switch t {
            case "today":     dayOffset = 0; consumed.insert(i)
            case "tomorrow":  dayOffset = 1; consumed.insert(i)
            case "yesterday": dayOffset = -1; consumed.insert(i)
            case "next":      nextFlag = true; consumed.insert(i)
            default:
                if let w = weekdays[t], weekday == nil {
                    weekday = w; consumed.insert(i)
                } else if let m = months[t], monthDay == nil,
                          let (j, d) = nextDayNum(after: i) {
                    // "sep 25"
                    monthDay = .init(m, d); consumed.formUnion([i, j])
                } else if monthDay == nil, let d = Int(t), (1...31).contains(d),
                          let (j, m) = nextMonth(after: i) {
                    // "25 sep"
                    monthDay = .init(m, d); consumed.formUnion([i, j])
                } else if monthDay == nil, t.contains("/"),
                          let m = parseNumericDate(t) {
                    monthDay = .init(m.0, m.1); consumed.insert(i)
                }
            }
        }

        // Resolve weekday tokens to a day offset from the reference date:
        // plain "tue" → next occurrence; "next tue" → the one after that.
        if let w = weekday, dayOffset == nil {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = homeTZ
            let refW = cal.component(.weekday, from: referenceDate)
            dayOffset = ((w - refW + 6) % 7) + 1 + (nextFlag ? 7 : 0)
        }

        // Strip fillers; whatever remains are city candidates.
        var cityTokens = tokens.enumerated()
            .filter { !consumed.contains($0.offset) && !fillers.contains($0.element) }
            .map(\.element)

        var cities: [CityCatalog.Entry] = []
        while !cityTokens.isEmpty {
            // greedy: longest run of up to 3 words that strong-matches
            var matched = false
            for len in stride(from: min(3, cityTokens.count), through: 1, by: -1) {
                let phrase = cityTokens.prefix(len).joined(separator: " ")
                if let hit = catalog.bestMatch(phrase) {
                    cities.append(hit)
                    cityTokens.removeFirst(len)
                    matched = true
                    break
                }
            }
            if !matched { cityTokens.removeFirst() }
        }

        if let (h, m) = time {
            return ParsedCommand(intent: .jump(
                hour: h, minute: m, city: cities.first,
                dayOffset: dayOffset, weekday: weekday,
                monthDay: monthDay))
        }
        if !cities.isEmpty {
            return ParsedCommand(intent: .addPlaces(cities))
        }
        return nil
    }

    private enum AMPM { case am, pm }

    private static func ampm(_ t: String) -> AMPM? {
        switch t {
        case "am", "a": return .am
        case "pm", "p": return .pm
        default: return nil
        }
    }

    /// "3pm", "3:30pm", "15:00", "9a", "9p" — needs an explicit suffix or colon.
    private static func parseTime(_ t: String) -> (Int, Int)? {
        let pattern = #"^(\d{1,2})(?::(\d{2}))?(am|pm|a|p)$"#
        if let r = t.range(of: pattern, options: .regularExpression) {
            let s = String(t[r])
            let digits = s.prefix(while: { $0.isNumber })
            guard let h = Int(digits), (0...12).contains(h) else { return nil }
            let minPart = s.dropFirst(digits.count)
                .prefix(while: { $0.isNumber })
            let m = Int(minPart) ?? 0
            let pm = s.hasSuffix("pm") || s.hasSuffix("p")
            return (h == 12 ? (pm ? 12 : 0) : h + (pm ? 12 : 0), m)
        }
        // "15:00" / "9:30" (24h, colon required)
        let p2 = #"^(\d{1,2}):(\d{2})$"#
        if let r = t.range(of: p2, options: .regularExpression) {
            let s = String(t[r]).split(separator: ":")
            if let h = Int(s[0]), let m = Int(s[1]), (0...23).contains(h), (0...59).contains(m) {
                return (h, m)
            }
        }
        return nil
    }

    /// "9/25" or "09/25" → (month, day).
    private static func parseNumericDate(_ t: String) -> (Int, Int)? {
        let parts = t.split(separator: "/")
        guard parts.count == 2, let m = Int(parts[0]), let d = Int(parts[1]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return (m, d)
    }
}

