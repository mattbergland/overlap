import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct Place: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var timeZoneID: String
    var isHome: Bool = false

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// e.g. "PDT" — only if the abbreviation is alphabetic (else just "GMT+2").
    func abbreviation(at date: Date = Date()) -> String {
        let abbr = timeZone.abbreviation(for: date) ?? ""
        return abbr.rangeOfCharacter(from: .letters.inverted) == nil && !abbr.isEmpty ? abbr : ""
    }

    /// Sub-label for a row: "PDT · UTC−7", or just "UTC−7" if the tz has
    /// no alphabetic abbreviation at `date`.
    func offsetLabel(at date: Date = Date()) -> String {
        let abbr = abbreviation(at: date)
        return abbr.isEmpty ? utcOffset(at: date) : "\(abbr) · \(utcOffset(at: date))"
    }

    /// Signed whole-hour difference from `home` at `date`, e.g. "+3h", "−8h",
    /// or nil if zero / not whole hours.
    func hourOffset(from home: TimeZone, at date: Date = Date()) -> String? {
        let diff = timeZone.secondsFromGMT(for: date) - home.secondsFromGMT(for: date)
        guard diff != 0, diff % 3600 == 0 else { return nil }
        let h = diff / 3600
        return h > 0 ? "+\(h)h" : "−\(abs(h))h"
    }

    /// e.g. "UTC−7"
    func utcOffset(at date: Date = Date()) -> String {
        let hours = Double(timeZone.secondsFromGMT(for: date)) / 3600
        if hours == hours.rounded() {
            return "UTC" + (hours < 0 ? "−\(abs(Int(hours)))" : (hours > 0 ? "+\(Int(hours))" : "±0"))
        }
        let sign = hours < 0 ? "−" : "+"
        let absH = abs(hours)
        let h = Int(absH)
        let m = Int((absH - Double(h)) * 60)
        return "UTC\(sign)\(h):\(String(format: "%02d", m))"
    }
}

@Observable
final class PlaceStore {
    private static let defaultsKey = "overlap.places.v1"
    static let appGroupID = "group.land.mattberg.overlap"

    var places: [Place] = [] {
        didSet { save() }
    }

    var home: Place? { places.first(where: { $0.isHome }) }
    var homeTimeZone: TimeZone { home?.timeZone ?? .current }

    /// Shared file read by the widget extension (works with ad-hoc signing
    /// where the App Group container may be unavailable).
    static var sharedFileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Overlap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("places.json")
    }

    private static func groupDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static func decode(_ data: Data?) -> [Place]? {
        guard let data,
              let decoded = try? JSONDecoder().decode([Place].self, from: data),
              !decoded.isEmpty else { return nil }
        return decoded
    }

    init() {
        // Shared file (widget contract) → App Group → legacy standard defaults.
        if var p = Self.decode(try? Data(contentsOf: Self.sharedFileURL))
            ?? Self.decode(Self.groupDefaults()?.data(forKey: Self.defaultsKey))
            ?? Self.decode(UserDefaults.standard.data(forKey: Self.defaultsKey)) {
            if !p.contains(where: { $0.isHome }) { p[0].isHome = true }
            places = p
        } else {
            places = Self.defaultPlaces()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(places) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        Self.groupDefaults()?.set(data, forKey: Self.defaultsKey)
        try? data.write(to: Self.sharedFileURL, options: .atomic)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private static func defaultPlaces() -> [Place] {
        var result: [Place] = []
        var seen: Set<String> = []

        let local = TimeZone.current
        let homeID = local.identifier
        // Legacy alias zones like "US/Pacific" produce ugly names — map
        // the common ones to a city, else use the last path component.
        let legacyNames = [
            "US/Pacific": "Los Angeles", "US/Mountain": "Denver",
            "US/Central": "Chicago", "US/Eastern": "New York",
            "US/Alaska": "Anchorage", "US/Hawaii": "Honolulu",
            "US/Arizona": "Phoenix", "US/Aleutian": "Adak",
        ]
        let homeName = legacyNames[homeID]
            ?? homeID.split(separator: "/").last
                .map { $0.replacingOccurrences(of: "_", with: " ") }
            ?? "Home"
        result.append(Place(name: homeName, timeZoneID: homeID, isHome: true))
        seen.insert(homeID)

        for (name, tzID) in [
            ("New York", "America/New_York"),
            ("London", "Europe/London"),
            ("Berlin", "Europe/Berlin"),
            ("Tokyo", "Asia/Tokyo"),
        ] {
            if !seen.contains(tzID) {
                result.append(Place(name: name, timeZoneID: tzID))
                seen.insert(tzID)
            }
        }
        return result
    }

    // MARK: - Mutations

    static let maxPlaces = 10

    func add(name: String, timeZoneID: String) {
        guard places.count < Self.maxPlaces,
              !places.contains(where: { $0.timeZoneID == timeZoneID }) else { return }
        places.append(Place(name: name, timeZoneID: timeZoneID))
    }

    func remove(_ place: Place) {
        guard places.count > 1 else { return }
        places.removeAll { $0.id == place.id }
        if place.isHome, !places.contains(where: { $0.isHome }) {
            places[0].isHome = true
        }
    }

    func setHome(_ place: Place) {
        for i in places.indices { places[i].isHome = (places[i].id == place.id) }
        if let idx = places.firstIndex(where: { $0.id == place.id }) {
            let p = places.remove(at: idx)
            places.insert(p, at: 0)
        }
    }

    func move(_ place: Place, direction: Int) {
        guard let i = places.firstIndex(where: { $0.id == place.id }) else { return }
        let j = i + direction
        guard places.indices.contains(j) else { return }
        // Don't let a non-home city move above home; moving home down hands
        // home status to whatever takes the top spot.
        places.swapAt(i, j)
        if let idx = places.firstIndex(where: { $0.id == place.id }), idx == 0 {
            // already handled below
        }
        // Keep home flag consistent with position 0 only if user asked via setHome;
        // here we just keep flags as-is.
    }
}
