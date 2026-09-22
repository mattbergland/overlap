import SwiftUI
import WidgetKit
import AppKit

@main
struct PreviewMain {
    static func loadPlaces() -> [Place] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Overlap/places.json")
        if let data = try? Data(contentsOf: url),
           let places = try? JSONDecoder().decode([Place].self, from: data),
           !places.isEmpty {
            return places
        }
        return [
            Place(name: "Los Angeles", timeZoneID: "America/Los_Angeles", isHome: true),
            Place(name: "New York", timeZoneID: "America/New_York"),
            Place(name: "London", timeZoneID: "Europe/London"),
            Place(name: "Tokyo", timeZoneID: "Asia/Tokyo"),
        ]
    }

    @MainActor
    static func main() {
        let places = loadPlaces()
        let entry = WidgetEntry(date: Date(), places: places)

        func bg<V: View>(_ v: V) -> some View {
            v.background(Theme.base).clipShape(RoundedRectangle(cornerRadius: 18))
        }

        let small = bg(ClocksWidgetView(entry: entry, familyOverride: .systemSmall))
        let clocksMed = bg(ClocksWidgetView(entry: entry, familyOverride: .systemMedium))
        let stripMed = bg(StripWidgetView(entry: entry, familyOverride: .systemMedium))
        let stripLarge = bg(StripWidgetView(entry: entry, familyOverride: .systemLarge))

        let canvas = VStack(spacing: 24) {
            HStack(alignment: .top, spacing: 24) {
                small.frame(width: 155, height: 155)
                clocksMed.frame(width: 330, height: 155)
            }
            stripMed.frame(width: 330, height: 155)
            stripLarge.frame(width: 330, height: 330)
        }
        .padding(32)
        .environment(\.colorScheme, .dark)
        .background(Color(hex: 0x05070B))

        let renderer = ImageRenderer(content: canvas.preferredColorScheme(.dark))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("render failed")
        }
        let out = FileManager.default.currentDirectoryPath + "/docs/screenshots/widgets.png"
        try? FileManager.default.createDirectory(
            atPath: FileManager.default.currentDirectoryPath + "/docs/screenshots",
            withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
