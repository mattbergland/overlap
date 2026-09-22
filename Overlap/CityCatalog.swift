import Foundation

struct City: Identifiable, Hashable {
    var id: String { identifier }
    let name: String        // "Los Angeles"
    let region: String      // "America"
    let identifier: String  // "America/Los_Angeles"
    let aliases: [String]
}

/// Searchable catalog of IANA time zones, built from
/// `TimeZone.knownTimeZoneIdentifiers`, plus curated aliases.
final class CityCatalog {
    static let shared = CityCatalog()

    let cities: [City]

    /// Curated aliases -> IANA identifier.
    private static let aliasTable: [String: String] = [
        "NYC": "America/New_York",
        "New York City": "America/New_York",
        "SF": "America/Los_Angeles",
        "San Fran": "America/Los_Angeles",
        "Bay Area": "America/Los_Angeles",
        "Silicon Valley": "America/Los_Angeles",
        "Los Angeles": "America/Los_Angeles",
        "London": "Europe/London",
        "Bangalore": "Asia/Kolkata",
        "Bengaluru": "Asia/Kolkata",
        "Sydney": "Australia/Sydney",
        "Singapore": "Asia/Singapore",
        "Dubai": "Asia/Dubai",
        "Paris": "Europe/Paris",
        "Mumbai": "Asia/Kolkata",
        "Toronto": "America/Toronto",
        "Chicago": "America/Chicago",
        "Denver": "America/Denver",
        "Seattle": "America/Los_Angeles",
        "Austin": "America/Chicago",
        "Boston": "America/New_York",
        "Miami": "America/New_York",
        "Tokyo": "Asia/Tokyo",
        "Berlin": "Europe/Berlin",
        "Hong Kong": "Asia/Hong_Kong",
        "Shanghai": "Asia/Shanghai",
        "Beijing": "Asia/Shanghai",
        "Delhi": "Asia/Kolkata",
        "Tel Aviv": "Asia/Jerusalem",
        "Auckland": "Pacific/Auckland",
        "Honolulu": "Pacific/Honolulu",
        "Vancouver": "America/Vancouver",
        "Mexico City": "America/Mexico_City",
        "São Paulo": "America/Sao_Paulo",
        "Sao Paulo": "America/Sao_Paulo",
        "Amsterdam": "Europe/Amsterdam",
        "Madrid": "Europe/Madrid",
        "Rome": "Europe/Rome",
        "Zurich": "Europe/Zurich",
        "Stockholm": "Europe/Stockholm",
        "Oslo": "Europe/Oslo",
        "Dublin": "Europe/Dublin",
        "Lisbon": "Europe/Lisbon",
        "Moscow": "Europe/Moscow",
        "Cape Town": "Africa/Johannesburg",
        "Nairobi": "Africa/Nairobi",
        "Seoul": "Asia/Seoul",
        "Melbourne": "Australia/Melbourne",
    ]

    init() {
        var aliasesByID: [String: [String]] = [:]
        for (alias, id) in Self.aliasTable {
            aliasesByID[id, default: []].append(alias)
        }

        var result: [City] = []
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            let parts = identifier.split(separator: "/")
            guard parts.count >= 2 else { continue }
            let region = String(parts[0])
            if region == "Etc" || region == "SystemV" { continue }
            let name = parts.last!
                .replacingOccurrences(of: "_", with: " ")
            result.append(City(
                name: name,
                region: region,
                identifier: identifier,
                aliases: aliasesByID[identifier] ?? []
            ))
        }
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cities = result
    }

    /// Fuzzy search: case-insensitive contains on name, aliases, identifier.
    /// Prefix matches on name or alias rank first, then other name matches,
    /// then identifier-only matches.
    func search(_ query: String, limit: Int = 8) -> [City] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        var prefix: [City] = []
        var contains: [City] = []
        var idOnly: [City] = []

        for city in cities {
            let name = city.name.lowercased()
            let aliasHit = city.aliases.contains { $0.lowercased().contains(q) }
            let aliasPrefix = city.aliases.contains { $0.lowercased().hasPrefix(q) }

            if name.hasPrefix(q) || aliasPrefix {
                prefix.append(city)
            } else if name.contains(q) || aliasHit {
                contains.append(city)
            } else if city.identifier.lowercased().contains(q) {
                idOnly.append(city)
            }
        }

        return Array((prefix + contains + idOnly).prefix(limit))
    }

    typealias Entry = City

    /// Strong match only: top result must prefix-match a name or alias,
    /// or be an exact alias hit. Nil for weak/fuzzy matches.
    func bestMatch(_ query: String) -> Entry? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        // exact alias wins outright
        for city in cities {
            if city.aliases.contains(where: { $0.lowercased() == q }) { return city }
        }
        for city in cities {
            if city.name.lowercased().hasPrefix(q) ||
               city.aliases.contains(where: { $0.lowercased().hasPrefix(q) }) {
                return city
            }
        }
        return nil
    }
}
