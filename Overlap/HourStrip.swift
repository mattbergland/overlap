import SwiftUI

/// One place's row: left info column + 24 hour cells + context menu.
/// Columns are hours of the HOME date; cell color/label use the place's
/// LOCAL hour at that instant.
struct PlaceRow: View {
    let place: Place
    let date: Date          // selected home date
    let now: Date
    let home: TimeZone
    let use24: Bool
    let isToday: Bool
    @Binding var hoverHour: Int?
    @Binding var selection: ClosedRange<Int>?

    @Environment(PlaceStore.self) private var store
    @State private var rowHover = false
    @State private var dragAnchor: Int? = nil

    private var tz: TimeZone { place.timeZone }

    private var dayBadge: String? {
        let off = TimeMath.dayOffset(of: now, target: tz, home: home)
        if off > 0 { return "+\(off) day" }
        if off < 0 { return "−\(abs(off)) day" }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: ContentView.columnGap) {
            leftColumn
            HourStrip(place: place,
                      date: date,
                      now: now,
                      home: home,
                      use24: use24,
                      isToday: isToday,
                      hoverHour: $hoverHour,
                      selection: $selection,
                      dragAnchor: $dragAnchor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(place.isHome ? Color.white.opacity(0.06) : (rowHover ? Color.white.opacity(0.05) : Color.white.opacity(0.028)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(place.isHome ? Theme.accentA.opacity(0.35) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .onHover { rowHover = $0 }
        .contextMenu {
            if !place.isHome {
                Button("Set as Home") { store.setHome(place) }
            }
            Button("Move Up") { store.move(place, direction: -1) }
            Button("Move Down") { store.move(place, direction: 1) }
            Divider()
            Button("Remove", role: .destructive) { store.remove(place) }
                .disabled(store.places.count <= 1)
        }
    }

    private var leftColumn: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if place.isHome {
                        Image(systemName: "house.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.accentB)
                    }
                    Text(place.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(place.name)
                    if let badge = dayBadge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.accentA.opacity(0.3), in: Capsule())
                    }
                    if rowHover && !place.isHome {
                        Button { store.remove(place) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(place.offsetLabel(at: date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if !place.isHome, let diff = place.hourOffset(from: home, at: date) {
                        Text(diff)
                            .font(.system(size: 8, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }
            }
            .frame(width: 140, alignment: .leading)
            LocalClock(place: place, use24: use24, now: now)
        }
        .frame(width: ContentView.leftColumn, alignment: .leading)
    }
}

/// Right-aligned local clock for a place.
private struct LocalClock: View {
    let place: Place
    let use24: Bool
    let now: Date

    var body: some View {
        let comps = TimeMath.localComponents(of: now, in: place.timeZone)
        let h24 = comps.hour ?? 0
        let m = comps.minute ?? 0
        if use24 {
            Text(String(format: "%d:%02d", h24, m))
                .font(.system(.title3, design: .rounded, weight: .medium))
                .monospacedDigit()
        } else {
            let h12 = h24 % 12 == 0 ? 12 : h24 % 12
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%d:%02d", h12, m))
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .monospacedDigit()
                Text(h24 < 12 ? "AM" : "PM")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The 24-cell strip shared by every row.
struct HourStrip: View {
    let place: Place
    let date: Date
    let now: Date
    let home: TimeZone
    let use24: Bool
    let isToday: Bool
    @Binding var hoverHour: Int?
    @Binding var selection: ClosedRange<Int>?
    @Binding var dragAnchor: Int?

    private var tz: TimeZone { place.timeZone }

    /// Fractional position (0...24) of "now" in home-hour columns.
    private var nowFraction: Double? {
        guard isToday else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = home
        let midnight = cal.startOfDay(for: date)
        return now.timeIntervalSince(midnight) / 3600
    }

    private var total: CGFloat { ContentView.stripWidth }
    private var cellW: CGFloat { ContentView.cellWidth }
    private var colPitch: CGFloat { total / 24 }

    private func column(atX x: CGFloat) -> Int {
        max(0, min(23, Int(x / colPitch)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: ContentView.cellSpacing) {
                ForEach(0..<24, id: \.self) { h in
                    cell(h)
                        .frame(width: cellW, height: ContentView.cellHeight)
                }
            }

            // Selection band
            if let sel = selection {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.accent.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.accentB.opacity(0.5), lineWidth: 1))
                    .frame(width: CGFloat(sel.count) * colPitch,
                           height: ContentView.cellHeight)
                    .offset(x: CGFloat(sel.lowerBound) * colPitch)
                    .allowsHitTesting(false)
            }

            // Hover column ring
            if let h = hoverHour {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    .frame(width: cellW, height: ContentView.cellHeight)
                    .offset(x: CGFloat(h) * colPitch)
                    .allowsHitTesting(false)
            }

            // Now indicator
            if let frac = nowFraction, frac >= 0 && frac <= 24 {
                Capsule()
                    .fill(Theme.accentVertical)
                    .frame(width: 2, height: ContentView.cellHeight)
                    .offset(x: CGFloat(frac) * colPitch - 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: total, height: ContentView.cellHeight)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let loc):
                hoverHour = column(atX: loc.x)
            case .ended:
                hoverHour = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let h = column(atX: v.location.x)
                    if dragAnchor == nil {
                        dragAnchor = column(atX: v.startLocation.x)
                    }
                    let a = dragAnchor ?? h
                    selection = min(a, h)...max(a, h)
                }
                .onEnded { _ in dragAnchor = nil }
        )
    }

    private func tierAt(_ h: Int) -> TimeMath.Tier {
        let inst = TimeMath.instant(homeHour: h, on: date, home: home)
        return TimeMath.tier(localHour: TimeMath.localHour(of: inst, in: tz))
    }

    @ViewBuilder
    private func cell(_ h: Int) -> some View {
        let inst = TimeMath.instant(homeHour: h, on: date, home: home)
        let comps = TimeMath.localComponents(of: inst, in: tz)
        let localH = comps.hour ?? 0
        let tier = TimeMath.tier(localHour: localH)
        let isMidnight = localH == 0
        let hovered = hoverHour == h
        // Contiguous same-tier cells merge: square off shared edges and
        // bleed half the inter-cell gap so runs read as one block.
        let leftJoin = h > 0 && tierAt(h - 1) == tier
        let rightJoin = h < 23 && tierAt(h + 1) == tier

        ZStack {
            UnevenRoundedRectangle(cornerRadii: .init(
                    topLeading: leftJoin ? 0 : 5,
                    bottomLeading: leftJoin ? 0 : 5,
                    bottomTrailing: rightJoin ? 0 : 5,
                    topTrailing: rightJoin ? 0 : 5))
                .fill(Theme.fill(for: tier).opacity(hovered ? 1 : 0.95))
                .padding(.leading, leftJoin ? -ContentView.cellSpacing / 2 : 0)
                .padding(.trailing, rightJoin ? -ContentView.cellSpacing / 2 : 0)
            if isMidnight {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 1.5)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text(cellLabel(h: localH, comps: comps, hovered: hovered))
                .font(.system(size: isMidnight ? 8.5 : 9.5,
                              weight: hovered || isMidnight ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.text(for: tier).opacity(hovered ? 1 : 0.9))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }

    private func cellLabel(h: Int, comps: DateComponents, hovered: Bool) -> String {
        if h == 0 {
            // day boundary marker: abbreviated weekday
            let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return weekdays[(comps.weekday ?? 1) - 1]
        }
        if hovered {
            return use24 ? String(format: "%02d:00", h)
                         : "\(h % 12 == 0 ? 12 : h % 12)\(h < 12 ? "a" : "p")"
        }
        if use24 { return "\(h)" }
        if h == 0 { return "12a" }
        if h < 12 { return "\(h)" }
        if h == 12 { return "12p" }
        return "\(h - 12)"
    }

}

/// Thin track above the rows showing good-window segments.
struct BestWindowsBar: View {
    let store: PlaceStore
    let date: Date
    let home: TimeZone
    @Binding var selection: ClosedRange<Int>?

    @AppStorage("use24Hour") private var use24 = false

    private var windows: (work: [ClosedRange<Int>], okay: [ClosedRange<Int>]) {
        TimeMath.goodWindows(places: store.places, on: date, home: home)
    }

    private var bestEffort: [ClosedRange<Int>] {
        TimeMath.bestEffortWindows(places: store.places, on: date, home: home)
    }

    private func fmt(_ r: ClosedRange<Int>) -> String {
        func h(_ v: Int) -> String {
            let v = v % 24
            if use24 { return "\(v)" }
            return "\(v % 12 == 0 ? 12 : v % 12)\(v < 12 ? "a" : "p")"
        }
        return "\(h(r.lowerBound))–\(h(r.upperBound + 1))"
    }

    var body: some View {
        let w = windows
        let none = w.work.isEmpty && w.okay.isEmpty
        let effort = none ? bestEffort : []
        HStack(spacing: ContentView.columnGap) {
            Group {
                if none {
                    Text("Best windows · none")
                } else {
                    Text("Best windows · \(w.work.count + w.okay.count)")
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: ContentView.leftColumn, alignment: .leading)

            let unit = ContentView.stripWidth / 24
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                ForEach(effort, id: \.self) { r in
                    segment(r, unit: unit, color: Theme.okayAmber.opacity(0.5))
                }
                ForEach(w.okay, id: \.self) { r in
                    segment(r, unit: unit, color: Theme.okayAmber)
                }
                ForEach(w.work, id: \.self) { r in
                    segment(r, unit: unit, color: Theme.goodGreen)
                }
                if none {
                    Text("No shared working hours — closest: \(effort.map(fmt).joined(separator: ", "))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: ContentView.stripWidth, height: 12)
        }
        .padding(.horizontal, 10)
        .frame(height: 14)
    }

    private func segment(_ r: ClosedRange<Int>, unit: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color.opacity(0.85))
            .shadow(color: color.opacity(0.8), radius: 4)
            .frame(width: CGFloat(r.count) * unit)
            .offset(x: CGFloat(r.lowerBound) * unit)
            .onTapGesture { selection = r }
    }
}
