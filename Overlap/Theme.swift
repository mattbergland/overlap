import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

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

    /// Continuous sky ramp keyed on a place's LOCAL hour — day cells
    /// merge into one bright block, night into deep indigo.
    static func skyFill(localHour h: Int) -> Color {
        switch h {
        case 0...4:  return Color(hex: 0x12172A)
        case 5:      return Color(hex: 0x232A4A)
        case 6:      return Color(hex: 0x5B4A7A)
        case 7:      return Color(hex: 0xD9A066)
        case 8:      return Color(hex: 0xEFDDC2)
        case 9...16: return Color(hex: 0xF6F1E8)
        case 17:     return Color(hex: 0xF0C27A)
        case 18:     return Color(hex: 0xD9895C)
        case 19:     return Color(hex: 0x7A5C8A)
        case 20:     return Color(hex: 0x3A3B63)
        default:     return Color(hex: 0x161B30)   // 21–23
        }
    }

    static func skyText(localHour h: Int) -> Color {
        switch h {
        case 5:      return Color.white.opacity(0.5)
        case 6:      return Color.white.opacity(0.85)
        case 7:      return Color(hex: 0x1A1410)
        case 8...18: return base
        case 19:     return Color.white.opacity(0.9)
        case 20:     return Color.white.opacity(0.6)
        default:     return Color.white.opacity(0.35)
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
