import SwiftUI

@main
struct OverlapApp: App {
    @State private var store = PlaceStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Window("Overlap", id: "main") {
            ContentView(standalone: true)
                .environment(store)
                .frame(minWidth: 800, minHeight: 320)
        }
        .windowResizability(.contentSize)
    }
}

/// Menu bar label: globe + home city's current time, updated by a Timer.
/// (TimelineView inside a MenuBarExtra label spins at 100% CPU on macOS 26.)
private struct MenuBarLabel: View {
    @Environment(PlaceStore.self) private var store
    @State private var now = Date()

    private let timer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        let home = store.homeTimeZone
        let comps = TimeMath.localComponents(of: now, in: home)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        HStack(spacing: 4) {
            Image(systemName: "globe")
            Text(String(format: "%d:%02d", h, m))
                .monospacedDigit()
        }
        .onReceive(timer) { now = $0 }
    }
}
