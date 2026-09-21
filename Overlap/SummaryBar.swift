import SwiftUI
import AppKit

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

    private var copyText: String {
        places.map { p in
            let (r, _) = range(for: p)
            return "\(p.name): \(headerDate) \(r)"
        }.joined(separator: "\n")
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
                        .background(Theme.tierTint(tier).opacity(0.22), in: Capsule())
                        .overlay(Capsule().stroke(Theme.tierTint(tier).opacity(0.55), lineWidth: 1))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accentB)

                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 3)
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
    }
}
