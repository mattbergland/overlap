import SwiftUI

enum Theme {
    /// Deep near-black base.
    static let base = Color(red: 0.043, green: 0.055, blue: 0.078)   // #0B0E14
    static let card = Color.white.opacity(0.055)

    static let accentA = Color(red: 0.45, green: 0.42, blue: 1.00)   // indigo
    static let accentB = Color(red: 0.25, green: 0.85, blue: 0.95)   // cyan

    static var accent: LinearGradient {
        LinearGradient(colors: [accentA, accentB],
                       startPoint: .leading, endPoint: .trailing)
    }
    static var accentVertical: LinearGradient {
        LinearGradient(colors: [accentA, accentB],
                       startPoint: .top, endPoint: .bottom)
    }

    // Hour cell fills by tier. Work pops as a bright block with dark text;
    // fringe is a mid whisper; night recedes to near-nothing.
    static func fill(for tier: TimeMath.Tier) -> Color {
        switch tier {
        case .work:  return Color.white.opacity(0.88)
        case .okay:  return Color.white.opacity(0.12)
        case .night: return Color.white.opacity(0.04)
        }
    }
    static func text(for tier: TimeMath.Tier) -> Color {
        switch tier {
        case .work:  return base
        case .okay:  return Color.white.opacity(0.60)
        case .night: return Color.white.opacity(0.30)
        }
    }

    static let goodGreen = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let okayAmber = Color(red: 0.95, green: 0.70, blue: 0.30)
    static let badRed    = Color(red: 0.95, green: 0.40, blue: 0.40)

    static func tierTint(_ tier: TimeMath.Tier) -> Color {
        switch tier {
        case .work:  return goodGreen
        case .okay:  return okayAmber
        case .night: return badRed
        }
    }
}

extension TimeZone {
    /// "America/Los_Angeles" -> "Los Angeles"
    var cityName: String {
        identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
    }
}
