import WidgetKit
import SwiftUI

// MARK: - Shared data

struct WidgetEntry: TimelineEntry {
    let date: Date
    let places: [Place]
}

private func loadPlaces() -> [Place] {
    let store = PlaceStore()
    return store.places
}

private func homeTZ(_ places: [Place]) -> TimeZone {
    places.first(where: { $0.isHome })?.timeZone ?? .current
}

// MARK: - Clocks widget

struct ClocksProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), places: loadPlaces())
    }
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: Date(), places: loadPlaces()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        // Text(date, style: .time) keeps itself current — no rolling entries.
        completion(Timeline(entries: [WidgetEntry(date: Date(), places: loadPlaces())],
                            policy: .never))
    }
}

struct ClocksWidgetView: View {
    let entry: WidgetEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    var body: some View {
        let places = entry.places
        let home = places.first(where: { $0.isHome }) ?? places.first
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                if let home {
                    Text(home.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.date, style: .time)
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .environment(\.timeZone, home.timeZone)
                }
                ForEach(places.filter { !$0.isHome }.prefix(2)) { p in
                    HStack(spacing: 6) {
                        Text(p.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(entry.date, style: .time)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .environment(\.timeZone, p.timeZone)
                    }
                }
            }
            .padding(4)
        default: // medium: 2×2 sky tiles
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(places.prefix(4)) { p in
                    let localH = TimeMath.localHour(of: entry.date, in: p.timeZone)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(p.name)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            if let badge = dayBadge(p) {
                                Text(badge)
                                    .font(.system(size: 7, weight: .bold))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(.black.opacity(0.25), in: Capsule())
                            }
                        }
                        Text(entry.date, style: .time)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .environment(\.timeZone, p.timeZone)
                    }
                    .foregroundStyle(Theme.skyText(localHour: localH))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Theme.skyFill(localHour: localH),
                                in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(4)
        }
    }

    private func dayBadge(_ p: Place) -> String? {
        let off = TimeMath.dayOffset(of: entry.date, target: p.timeZone,
                                     home: homeTZ(entry.places))
        return off == 0 ? nil : (off > 0 ? "+\(off)" : "−\(abs(off))")
    }
}

struct ClocksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClocksWidget", provider: ClocksProvider()) { entry in
            ClocksWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.base }
        }
        .configurationDisplayName("Clocks")
        .description("Current time in your cities.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Overlap strip widget

struct StripProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), places: loadPlaces())
    }
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: Date(), places: loadPlaces()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let now = Date()
        let places = loadPlaces()
        let entries = (0..<8).map {
            WidgetEntry(date: now.addingTimeInterval(TimeInterval($0 * 15 * 60)),
                        places: places)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct StripWidgetView: View {
    let entry: WidgetEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    private var home: TimeZone { homeTZ(entry.places) }
    private var maxRows: Int { family == .systemLarge ? 8 : 4 }

    /// Fractional hour of `date` in home columns (0...24).
    private var nowFrac: Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = home
        return entry.date.timeIntervalSince(cal.startOfDay(for: entry.date)) / 3600
    }

    var body: some View {
        let places = Array(entry.places.prefix(maxRows))
        VStack(spacing: 4) {
            ForEach(places) { p in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(p.name)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                        Text(entry.date, style: .time)
                            .font(.system(size: 9, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .environment(\.timeZone, p.timeZone)
                    }
                    .frame(width: 72, alignment: .leading)

                    GeometryReader { geo in
                        let pitch = geo.size.width / 24
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(
                                    stops: (0..<24).map { h in
                                        let lh = TimeMath.localComponents(
                                            of: TimeMath.instant(homeHour: h, on: entry.date, home: home),
                                            in: p.timeZone).hour ?? 0
                                        return Gradient.Stop(
                                            color: Theme.skyFill(localHour: lh),
                                            location: (Double(h) + 0.5) / 24)
                                    },
                                    startPoint: .leading, endPoint: .trailing))
                            if p.isHome {
                                Capsule()
                                    .fill(Theme.accentVertical)
                                    .frame(width: 1.5)
                                    .offset(x: CGFloat(nowFrac) * pitch - 0.75)
                            }
                        }
                    }
                    .frame(height: 16)
                }
            }

            if family == .systemLarge {
                SharedHoursBar(places: places, date: entry.date, home: home)
                    .padding(.leading, 80)
            }
        }
        .padding(6)
    }
}

/// Green "Shared hours" segments under the rows (large widget only).
private struct SharedHoursBar: View {
    let places: [Place]
    let date: Date
    let home: TimeZone

    var body: some View {
        let w = TimeMath.goodWindows(places: places, on: date, home: home)
        GeometryReader { geo in
            let unit = geo.size.width / 24
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                ForEach(w.okay, id: \.self) { r in
                    Capsule().fill(Theme.okayAmber.opacity(0.8))
                        .frame(width: CGFloat(r.count) * unit)
                        .offset(x: CGFloat(r.lowerBound) * unit)
                }
                ForEach(w.work, id: \.self) { r in
                    Capsule().fill(Theme.goodGreen.opacity(0.9))
                        .shadow(color: Theme.goodGreen.opacity(0.6), radius: 3)
                        .frame(width: CGFloat(r.count) * unit)
                        .offset(x: CGFloat(r.lowerBound) * unit)
                }
            }
        }
        .frame(height: 6)
    }
}

struct OverlapStripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OverlapWidget", provider: StripProvider()) { entry in
            StripWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.base }
        }
        .configurationDisplayName("Overlap")
        .description("Sky bands for your cities' local hours.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Bundle

@main
struct OverlapWidgets: WidgetBundle {
    var body: some Widget {
        ClocksWidget()
        OverlapStripWidget()
    }
}
