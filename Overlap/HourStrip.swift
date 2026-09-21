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
                      home: home,
                      use24: use24,
                      hoverHour: $hoverHour,
                      selection: $selection,
                      dragAnchor: $dragAnchor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(rowHover ? 0.07 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(place.isHome ? Theme.accentA.opacity(0.5) : Color.white.opacity(0.05), lineWidth: 1)
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
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.5)
            }
        }
    }
}

/// The 24-cell strip shared by every row.
struct HourStrip: View {
    let place: Place
    let date: Date
    let home: TimeZone
    let use24: Bool
    @Binding var hoverHour: Int?
    @Binding var selection: ClosedRange<Int>?
    @Binding var dragAnchor: Int?

    private var tz: TimeZone { place.timeZone }

    private var total: CGFloat { ContentView.stripWidth }
    private var colPitch: CGFloat { total / 24 }

    private func column(atX x: CGFloat) -> Int {
        max(0, min(23, Int(x / colPitch)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // One continuous sky band: base + clipped cell fills
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: 0x12172A))
            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { h in
                    cell(h)
                        .frame(width: colPitch, height: ContentView.cellHeight)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Selection band
            if let sel = selection {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.accent.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.accentB.opacity(0.6), lineWidth: 1))
                    .frame(width: CGFloat(sel.count) * colPitch,
                           height: ContentView.cellHeight)
                    .offset(x: CGFloat(sel.lowerBound) * colPitch)
                    .allowsHitTesting(false)
            }

            // Hover column ring
            if let h = hoverHour {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    .frame(width: colPitch - 1, height: ContentView.cellHeight)
                    .offset(x: CGFloat(h) * colPitch + 0.5)
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

    @ViewBuilder
    private func cell(_ h: Int) -> some View {
        let inst = TimeMath.instant(homeHour: h, on: date, home: home)
        let comps = TimeMath.localComponents(of: inst, in: tz)
        let localH = comps.hour ?? 0
        let isMidnight = localH == 0
        let hovered = hoverHour == h

        ZStack {
            Theme.skyFill(localHour: localH)
            // hairline divider between cells; stronger at local midnight
            if h > 0 {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(isMidnight ? 0.35 : 0.06))
                        .frame(width: 1)
                    Spacer()
                }
            }
            Text(cellLabel(h: localH, comps: comps, hovered: hovered))
                .font(.system(size: isMidnight ? 8.5 : 9.5,
                              weight: hovered || isMidnight ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.skyText(localHour: localH).opacity(hovered ? 1 : 0.9))
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
            Label("Shared hours · \(w.work.count + w.okay.count)",
                  systemImage: "person.2.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: ContentView.leftColumn, alignment: .leading)

            let unit = ContentView.stripWidth / 24
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                ForEach(effort, id: \.self) { r in
                    Capsule()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .foregroundStyle(Theme.okayAmber.opacity(0.7))
                        .frame(width: CGFloat(r.count) * unit)
                        .offset(x: CGFloat(r.lowerBound) * unit)
                }
                ForEach(w.okay, id: \.self) { r in
                    segment(r, unit: unit, color: Theme.okayAmber)
                }
                ForEach(w.work, id: \.self) { r in
                    segment(r, unit: unit, color: Theme.goodGreen)
                }
                if none {
                    Text("No shared 9–6 · closest \(effort.map(fmt).joined(separator: ", "))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 6)
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
