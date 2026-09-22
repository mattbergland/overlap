import Foundation

/// Pure formatting of a selected home-hour range into shareable text.
enum InviteFormatter {
    enum Format: String, CaseIterable {
        case plain, slack, markdown
    }

    private static func calendar(in tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    /// "Mon Sep 21" in the home tz.
    static func header(date: Date, home: TimeZone) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        f.timeZone = home
        return f.string(from: date)
    }

    /// "9:00 – 11:00 AM" / "9:00 – 11:00" in `tz` for the home-hour range.
    static func rangeText(for tz: TimeZone, selection: ClosedRange<Int>,
                          on date: Date, home: TimeZone, use24: Bool) -> String {
        let start = TimeMath.instant(homeHour: selection.lowerBound, on: date, home: home)
        let end = TimeMath.instant(homeHour: selection.upperBound + 1, on: date, home: home)
        let f = DateFormatter()
        f.timeZone = tz
        if use24 {
            f.dateFormat = "H:mm"
            return "\(f.string(from: start)) – \(f.string(from: end))"
        }
        let cal = calendar(in: tz)
        let endH = cal.component(.hour, from: end)
        f.dateFormat = "h:mm"
        return "\(f.string(from: start)) – \(f.string(from: end)) \(endH < 12 ? "AM" : "PM")"
    }

    private static func lines(places: [Place], selection: ClosedRange<Int>,
                              on date: Date, home: TimeZone, use24: Bool) -> [(String, String)] {
        places.map {
            ($0.name, rangeText(for: $0.timeZone, selection: selection,
                                on: date, home: home, use24: use24))
        }
    }

    static func plain(date: Date, places: [Place], selection: ClosedRange<Int>,
                      home: TimeZone, use24: Bool) -> String {
        let h = header(date: date, home: home)
        return lines(places: places, selection: selection, on: date, home: home, use24: use24)
            .map { "\($0.0): \(h) \($0.1)" }
            .joined(separator: "\n")
    }

    static func slack(date: Date, places: [Place], selection: ClosedRange<Int>,
                      home: TimeZone, use24: Bool) -> String {
        var out = "*\(header(date: date, home: home))*"
        for (name, range) in lines(places: places, selection: selection,
                                   on: date, home: home, use24: use24) {
            out += "\n• \(range)  \(name)"
        }
        return out
    }

    static func markdown(date: Date, places: [Place], selection: ClosedRange<Int>,
                         home: TimeZone, use24: Bool) -> String {
        var out = "**\(header(date: date, home: home))**\n\n| City | Local time |\n|---|---|"
        for (name, range) in lines(places: places, selection: selection,
                                   on: date, home: home, use24: use24) {
            out += "\n| \(name) | \(range) |"
        }
        return out
    }

    static func format(_ format: Format, date: Date, places: [Place],
                       selection: ClosedRange<Int>, home: TimeZone, use24: Bool) -> String {
        switch format {
        case .plain:    return plain(date: date, places: places, selection: selection, home: home, use24: use24)
        case .slack:    return slack(date: date, places: places, selection: selection, home: home, use24: use24)
        case .markdown: return markdown(date: date, places: places, selection: selection, home: home, use24: use24)
        }
    }
}
