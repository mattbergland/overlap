import Foundation

/// Pure time-zone math for the hour strip. Every column is the instant
/// "home-local midnight of `date` + h hours", converted into each place's
/// local components — so DST transitions are handled by `Calendar`, not
/// fixed offsets.
enum TimeMath {

    /// Which "band" a local hour falls into for a participant.
    enum Tier: Int, Comparable {
        case night = 0
        case okay = 1   // fringe: 7–9 and 17–21
        case work = 2   // 9–17

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static let workHours = 9..<18   // 9:00–17:59
    static let okayHours = 7..<21   // 7:00–20:59

    private static func calendar(in tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    /// The instant corresponding to hour `h` (0–23) of the home-local day `date`.
    static func instant(homeHour h: Int, on date: Date, home: TimeZone) -> Date {
        let cal = calendar(in: home)
        let midnight = cal.startOfDay(for: date)
        return cal.date(byAdding: .hour, value: h, to: midnight) ?? midnight
    }

    /// Local hour (0–23) of `instant` in `tz`.
    static func localHour(of instant: Date, in tz: TimeZone) -> Int {
        calendar(in: tz).component(.hour, from: instant)
    }

    /// Whole local-time components in `tz`.
    static func localComponents(of instant: Date, in tz: TimeZone) -> DateComponents {
        calendar(in: tz).dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: instant)
    }

    /// Difference between the local calendar day of `instant` in `target`
    /// and in `home`: -1, 0, or +1 (or more for extreme offsets).
    static func dayOffset(of instant: Date, target: TimeZone, home: TimeZone) -> Int {
        let utc = calendar(in: TimeZone(identifier: "UTC")!)
        let homeDay = utc.date(from: calendar(in: home)
            .dateComponents([.year, .month, .day], from: instant))!
        let targetDay = utc.date(from: calendar(in: target)
            .dateComponents([.year, .month, .day], from: instant))!
        return utc.dateComponents([.day], from: homeDay, to: targetDay).day ?? 0
    }

    /// Tier for a single place at a given instant.
    static func tier(localHour h: Int) -> Tier {
        if workHours.contains(h) { return .work }
        if okayHours.contains(h) { return .okay }
        return .night
    }

    /// The worst tier across all places for home-hour column `h`.
    static func columnTier(homeHour h: Int, on date: Date, home: TimeZone, places: [Place]) -> Tier {
        let inst = instant(homeHour: h, on: date, home: home)
        var worst = Tier.work
        for place in places {
            let t = tier(localHour: localHour(of: inst, in: place.timeZone))
            if t < worst { worst = t }
        }
        return worst
    }

    /// Home-hour ranges (of `date`) where EVERY place is in working hours
    /// (`work`), plus fallback ranges where every place is at least in
    /// `okay` hours but not all are in `work`.
    static func goodWindows(places: [Place], on date: Date, home: TimeZone,
                            busyHomeHours: Set<Int> = [])
        -> (work: [ClosedRange<Int>], okay: [ClosedRange<Int>])
    {
        guard !places.isEmpty else { return ([], []) }
        var tiers = (0..<24).map {
            columnTier(homeHour: $0, on: date, home: home, places: places)
        }
        for h in busyHomeHours where tiers.indices.contains(h) {
            tiers[h] = .night
        }
        return (runs(of: .work, in: tiers), runs(of: .okay, in: tiers))
    }

    private static func runs(of tier: Tier, in tiers: [Tier]) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        var start: Int? = nil
        for (i, t) in tiers.enumerated() {
            if t == tier {
                if start == nil { start = i }
            } else if let s = start {
                result.append(s...(i - 1))
                start = nil
            }
        }
        if let s = start { result.append(s...23) }
        return result
    }

    /// Fallback when no shared work/okay window exists: score each home
    /// hour by how many places are working (×2) or in fringe hours (×1),
    /// then return the contiguous runs of max-scoring columns (≤ 2 runs).
    static func bestEffortWindows(places: [Place], on date: Date, home: TimeZone,
                                  busyHomeHours: Set<Int> = []) -> [ClosedRange<Int>] {
        guard !places.isEmpty else { return [] }
        var scores = [Int](repeating: 0, count: 24)
        for h in 0..<24 {
            if busyHomeHours.contains(h) { continue }
            let inst = instant(homeHour: h, on: date, home: home)
            for place in places {
                switch tier(localHour: localHour(of: inst, in: place.timeZone)) {
                case .work: scores[h] += 2
                case .okay: scores[h] += 1
                case .night: break
                }
            }
        }
        guard let maxScore = scores.max(), maxScore > 0 else { return [] }
        let maxCols = scores.map { $0 == maxScore }
        var runs: [ClosedRange<Int>] = []
        var start: Int? = nil
        for i in 0..<24 {
            if maxCols[i] {
                if start == nil { start = i }
            } else if let s = start {
                runs.append(s...(i - 1)); start = nil
            }
        }
        if let s = start { runs.append(s...23) }
        return Array(runs.prefix(2))
    }

    /// Best (worst-tier) for a selected home-hour range across places —
    /// used to tint summary chips per city instead.
    static func tier(for place: Place, homeHour h: Int, on date: Date, home: TimeZone) -> Tier {
        let inst = instant(homeHour: h, on: date, home: home)
        return tier(localHour: localHour(of: inst, in: place.timeZone))
    }
}
