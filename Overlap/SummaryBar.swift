import SwiftUI
import AppKit
import EventKit

/// Simple left-to-right wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// Bar shown below the rows when a home-hour range is selected:
/// wrapping chips per city with local equivalent time + Copy / clear.
struct SummaryBar: View {
    let date: Date
    let home: TimeZone
    let places: [Place]
    let selection: ClosedRange<Int>
    let use24: Bool
    let onClear: () -> Void
    let onToast: () -> Void

    @Environment(CalendarService.self) private var calendar
    @AppStorage("overlap.copyFormat") private var lastFormat = InviteFormatter.Format.plain.rawValue
    @State private var eventTitle = ""

    private var headerDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        f.timeZone = home
        return f.string(from: TimeMath.instant(homeHour: selection.lowerBound, on: date, home: home))
    }

    private func range(for place: Place) -> (String, TimeMath.Tier) {
        let start = TimeMath.instant(homeHour: selection.lowerBound, on: date, home: home)
        // Range sel covers hours lo...hi, so the meeting ends at hi+1.
        let end = TimeMath.instant(homeHour: selection.upperBound + 1, on: date, home: home)
        let f = DateFormatter()
        f.timeZone = place.timeZone
        f.dateFormat = use24 ? "H:mm" : "h:mm a"
        let s = f.string(from: start)
        let e = f.string(from: end)
        var worst = TimeMath.Tier.work
        for h in selection {
            let t = TimeMath.tier(for: place, homeHour: h, on: date, home: home)
            if t < worst { worst = t }
        }
        return ("\(s) – \(e)", worst)
    }

    private var selStart: Date {
        TimeMath.instant(homeHour: selection.lowerBound, on: date, home: home)
    }
    private var selEnd: Date {
        TimeMath.instant(homeHour: selection.upperBound + 1, on: date, home: home)
    }

    private var conflicts: [BusyBlock] {
        guard calendar.enabled else { return [] }
        return calendar.busy.filter { $0.start < selEnd && $0.end > selStart }
    }

    private var copyFormat: InviteFormatter.Format {
        InviteFormatter.Format(rawValue: lastFormat) ?? .plain
    }

    private func copyText(_ format: InviteFormatter.Format) -> String {
        InviteFormatter.format(format, date: date, places: places,
                               selection: selection, home: home, use24: use24)
    }

    private func copy(_ format: InviteFormatter.Format) {
        lastFormat = format.rawValue
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText(format), forType: .string)
    }

    private func createEvent() {
        let title = eventTitle.isEmpty ? "Call" : eventTitle
        let notes = copyText(.plain)
        let start = selStart, end = selEnd
        Task { @MainActor in
            if await calendar.ensureAccess() {
                do {
                    try calendar.createEvent(title: title, start: start, end: end, notes: notes)
                    onToast()
                    return
                } catch { }
            }
            openICS(title: title, start: start, end: end, notes: notes)
        }
    }

    /// Fallback when EventKit access is denied: hand a .ics to Calendar.app.
    private func openICS(title: String, start: Date, end: Date, notes: String) {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\n", with: "\\n")
             .replacingOccurrences(of: ",", with: "\\,")
             .replacingOccurrences(of: ";", with: "\\;")
        }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd'T'HHmmss"
        df.timeZone = home
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        stamp.timeZone = TimeZone(identifier: "UTC")
        let ics = """
            BEGIN:VCALENDAR\r
            VERSION:2.0\r
            PRODID:-//Overlap//EN\r
            BEGIN:VEVENT\r
            UID:\(UUID().uuidString)@overlap\r
            DTSTAMP:\(stamp.string(from: Date()))\r
            DTSTART;TZID=\(home.identifier):\(df.string(from: start))\r
            DTEND;TZID=\(home.identifier):\(df.string(from: end))\r
            SUMMARY:\(esc(title))\r
            DESCRIPTION:\(esc(notes))\r
            END:VEVENT\r
            END:VCALENDAR\r
            """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlap-event.ics")
        try? ics.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(headerDate)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            FlowLayout(spacing: 6) {
                ForEach(places) { p in
                    let (r, tier) = range(for: p)
                    Text("\(r) \(p.name)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.tierTint(tier).opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(Theme.tierTint(tier), lineWidth: 1))
                        .lineLimit(1)
                        .fixedSize()
                }

                let conflicts = conflicts
                if let first = conflicts.first {
                    Text(conflicts.count > 1
                         ? "Conflicts: \(first.title) +\(conflicts.count - 1)"
                         : "Conflicts: \(first.title)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.badRed.opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(Theme.badRed, lineWidth: 1))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Call", text: $eventTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 64)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.07), in: Capsule())
                        .onSubmit { }

                    Button(action: createEvent) {
                        Label("Create event", systemImage: "calendar.badge.plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accentB)
                }

                HStack(spacing: 8) {
                    Menu {
                        Button("Plain") { copy(.plain) }
                        Button("Slack") { copy(.slack) }
                        Button("Markdown") { copy(.markdown) }
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                    } primaryAction: {
                        copy(copyFormat)
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .foregroundStyle(Theme.accentB)

                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 3)
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
    }
}
