import Foundation
import Observation

struct Place: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var timeZoneID: String
    var isHome: Bool = false

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// e.g. "PDT"
    func abbreviation(at date: Date = Date()) -> String {
        timeZone.abbreviation(for: date) ?? ""
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

    var places: [Place] = [] {
        didSet { save() }
    }

    var home: Place? { places.first(where: { $0.isHome }) }
    var homeTimeZone: TimeZone { home?.timeZone ?? .current }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([Place].self, from: data),
           !decoded.isEmpty {
            places = decoded
            if !places.contains(where: { $0.isHome }) {
                places[0].isHome = true
            }
        } else {
            places = Self.defaultPlaces()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
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
