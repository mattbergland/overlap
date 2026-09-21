import SwiftUI
import ServiceManagement

struct ContentView: View {
    var standalone: Bool = false

    @Environment(PlaceStore.self) private var store
    @AppStorage("use24Hour") private var use24 = false

    @State private var selectedDate = Date()
    @State private var hoverHour: Int? = nil
    @State private var selection: ClosedRange<Int>? = nil
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    private var home: TimeZone { store.homeTimeZone }

    private var isToday: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = home
        return cal.isDateInToday(selectedDate)
    }

    @State private var now = Date()
    private let timer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                header

                Divider().overlay(Color.white.opacity(0.08))
                    .padding(.vertical, 10)

                BestWindowsBar(store: store,
                               date: selectedDate,
                               home: home,
                               selection: $selection)
                    .padding(.bottom, 8)

                // Rows
                VStack(spacing: 6) {
                    ForEach(store.places) { place in
                        PlaceRow(place: place,
                                 date: selectedDate,
                                 now: now,
                                 home: home,
                                 use24: use24,
                                 isToday: isToday,
                                 hoverHour: $hoverHour,
                                 selection: $selection)
                        .transition(.asymmetric(insertion: .push(from: .top).combined(with: .opacity),
                                                removal: .opacity))
                    }
                }
                .animation(.snappy, value: store.places)

                if let selection {
                    SummaryBar(date: selectedDate,
                               home: home,
                               places: store.places,
                               selection: selection,
                               use24: use24,
                               onClear: { self.selection = nil })
                    .padding(.top, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(16)
        .onReceive(timer) { now = $0 }
        .fontDesign(.rounded)
        .frame(width: Self.popoverWidth)
        .background(.ultraThinMaterial)
        .background(Theme.base.opacity(standalone ? 0.98 : 0.86))
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .animation(.snappy, value: selection != nil)
        .animation(.snappy, value: hoverHour)
        .onExitCommand {
            if !query.isEmpty { query = "" } else { selection = nil }
        }
    }

    // MARK: - Layout constants

    static let leftColumn: CGFloat = 190
    static let columnGap: CGFloat = 14
    static let cellHeight: CGFloat = 30
    static let cellSpacing: CGFloat = 2
    static let popoverWidth: CGFloat = 800
    /// Width of the 24-cell strip: popover minus root padding (16×2),
    /// row horizontal padding (10×2), left column and the gap.
    static let stripWidth: CGFloat = popoverWidth - 32 - 20 - leftColumn - columnGap
    static var cellWidth: CGFloat { (stripWidth - 23 * cellSpacing) / 24 }

    // MARK: - Header

    private var dateLabel: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = home
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = home
        f.dateFormat = "EEE, MMM d"
        return f.string(from: selectedDate)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("OVERLAP")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundStyle(Theme.accent)

            Spacer(minLength: 4)

            // Date navigator
            HStack(spacing: 2) {
                Button { shiftDay(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text(dateLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 92)

                Button { shiftDay(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if !isToday {
                    Button("Today") {
                        withAnimation(.snappy) { selectedDate = Date() }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accentB)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.card, in: Capsule())

            // Search
            CitySearchField(query: $query, focused: $searchFocused) { city in
                store.add(name: city.name, timeZoneID: city.identifier)
                query = ""
            }
            .frame(width: 150)

            // Pop-out window
            if !standalone {
                Button {
                    openWindow(id: "main")
                    dismiss()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open in a window")
            }

            optionsMenu
        }
    }

    private var optionsMenu: some View {
        Menu {
            Toggle("Launch at Login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch { }
                }))

            Toggle("Use 24-hour time", isOn: $use24)

            Divider()

            Button("Quit Overlap") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func shiftDay(_ delta: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = home
        if let d = cal.date(byAdding: .day, value: delta, to: selectedDate) {
            withAnimation(.snappy) { selectedDate = d }
        }
    }
}

// MARK: - City search field with dropdown

struct CitySearchField: View {
    @Binding var query: String
    @FocusState.Binding var focused: Bool
    var onPick: (City) -> Void

    private var results: [City] { CityCatalog.shared.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Add a city…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit {
                        if let first = results.first { onPick(first) }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.card, in: Capsule())
        }
        .overlay(alignment: .topLeading) {
            if focused && !results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { city in
                        Button {
                            onPick(city)
                        } label: {
                            HStack {
                                Text(city.name)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text(city.region)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 220)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1)))
                .offset(y: 32)
                .zIndex(10)
            }
        }
        .zIndex(10)
    }
}
