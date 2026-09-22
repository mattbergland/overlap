import SwiftUI
import ServiceManagement

struct ContentView: View {
    var standalone: Bool = false

    @Environment(PlaceStore.self) private var store
    @Environment(CalendarService.self) private var calendar
    @AppStorage("use24Hour") private var use24 = false

    @State private var selectedDate = Date()
    @State private var hoverHour: Int? = nil
    @State private var selection: ClosedRange<Int>? = nil
    @State private var query = ""
    @State private var showToast = false
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
    private let calendarTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    private var busyHours: Set<Int> {
        calendar.enabled ? calendar.busyHomeHours(for: selectedDate, homeTZ: home) : []
    }

    private var busyBlocks: [BusyBlock] {
        calendar.enabled ? calendar.busy : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                header

                Divider().overlay(Color.white.opacity(0.08))
                    .padding(.vertical, 10)

                VStack(alignment: .leading, spacing: 0) {
                    // 16pt lane above the track: holds the now-time pill
                    Color.clear.frame(height: 16)
                        .overlay(alignment: .topLeading) { nowPill }

                    BestWindowsBar(store: store,
                                   date: selectedDate,
                                   home: home,
                                   busyHours: busyHours,
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
                                     busy: busyBlocks,
                                     hoverHour: $hoverHour,
                                     selection: $selection)
                            .transition(.asymmetric(insertion: .push(from: .top).combined(with: .opacity),
                                                    removal: .opacity))
                        }
                    }
                    .overlay(alignment: .topLeading) { selectionPill }
                    .animation(.snappy, value: store.places)
                }
                .overlay(alignment: .topLeading) { nowLine }

                if let selection {
                    SummaryBar(date: selectedDate,
                               home: home,
                               places: store.places,
                               selection: selection,
                               use24: use24,
                               onClear: { self.selection = nil },
                               onToast: { flashToast() })
                    .padding(.top, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(16)
        .onReceive(timer) { now = $0 }
        .onReceive(calendarTimer) { _ in refreshCalendar() }
        .onChange(of: selectedDate) { refreshCalendar() }
        .onAppear { refreshCalendar() }
        .fontDesign(.rounded)
        .frame(width: Self.popoverWidth)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Theme.base.opacity(standalone ? 0.98 : 0.92)
            }
        )
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .overlay {
            // inner stroke + top sheen
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
            VStack(spacing: 0) {
                LinearGradient(colors: [.white.opacity(0.06), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 80)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if showToast {
                Label("Added to Calendar", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.goodGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: showToast)
        .animation(.snappy, value: selection != nil)
        .animation(.snappy, value: hoverHour)
        .onExitCommand {
            if !query.isEmpty { query = "" } else { selection = nil }
        }
    }

    /// X offset of the strip inside the rows container (row pad + left col + gap).
    private var stripX: CGFloat { 10 + Self.leftColumn + Self.columnGap }
    private var colPitch: CGFloat { Self.stripWidth / 24 }

    private var nowFraction: Double? {
        guard isToday else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = home
        let f = now.timeIntervalSince(cal.startOfDay(for: selectedDate)) / 3600
        return (f >= 0 && f <= 24) ? f : nil
    }

    private var nowTimeLabel: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = home
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        if use24 { return String(format: "%d:%02d", h, m) }
        return String(format: "%d:%02d", (h % 12 == 0) ? 12 : h % 12, m)
    }

    private func homeRangeLabel(_ sel: ClosedRange<Int>) -> String {
        let f: (Int) -> String = { h in
            let hh = h % 24
            if use24 { return "\(hh):00" }
            return "\((hh % 12 == 0) ? 12 : hh % 12):00"
        }
        let end = sel.upperBound + 1
        let suffix = use24 ? "" : " \(end % 24 < 12 ? "AM" : "PM")"
        return "\(f(sel.lowerBound)) – \(f(end))\(suffix)"
    }

    private var nowX: CGFloat? {
        nowFraction.map { stripX + CGFloat($0) * colPitch }
    }

    /// Time pill in the 16pt lane, centered on the now-line's x.
    @ViewBuilder
    private var nowPill: some View {
        if let x = nowX {
            Color.clear
                .frame(width: 0, height: 16)
                .overlay {
                    Text(nowTimeLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.base)
                        .padding(.horizontal, 5)
                        .frame(height: 14)
                        .background(Theme.accentB, in: Capsule())
                        .fixedSize()
                }
                .offset(x: x)
                .allowsHitTesting(false)
        }
    }

    /// 1.5pt now-line from the pill's bottom (lane end) to the last row's
    /// bottom — drawn over lane + track + rows so it sits above the band.
    @ViewBuilder
    private var nowLine: some View {
        if let x = nowX {
            Capsule()
                .fill(Theme.accentVertical)
                .frame(width: 1.5)
                .shadow(color: Theme.accentB.opacity(0.45), radius: 3)
                .padding(.top, 16)
                .offset(x: x - 0.75)
                .allowsHitTesting(false)
        }
    }

    /// Home-range pill centered on the selection band, half-overlapping
    /// its top edge.
    @ViewBuilder
    private var selectionPill: some View {
        if let sel = selection {
            Text(homeRangeLabel(sel))
                .font(.system(size: 8.5, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(Theme.accentB.opacity(0.6), lineWidth: 0.5))
                .fixedSize()
                .frame(width: CGFloat(sel.count) * colPitch)
                .offset(x: stripX + CGFloat(sel.lowerBound) * colPitch, y: -8)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Layout constants

    static let leftColumn: CGFloat = 230
    static let columnGap: CGFloat = 14
    static let cellHeight: CGFloat = 30
    static let popoverWidth: CGFloat = 820
    /// Width of the 24-cell strip: popover minus root padding (16×2),
    /// row horizontal padding (10×2), left column and the gap.
    static let stripWidth: CGFloat = popoverWidth - 32 - 20 - leftColumn - columnGap

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
            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6, height: 6)
                Text("OVERLAP")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(Theme.accent)
            }

            Spacer(minLength: 4)

            // Date navigator
            HStack(spacing: 2) {
                Button { shiftDay(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text(dateLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 92)

                Button { shiftDay(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
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
                // ⌘T — jump back to today (hidden, always active)
                Button("") { withAnimation(.snappy) { selectedDate = Date() } }
                    .keyboardShortcut("t", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
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
            Toggle("Show my calendar", isOn: Binding(
                get: { calendar.enabled },
                set: { on in
                    calendar.enabled = on
                    if on {
                        Task { await calendar.requestAccess() }
                    } else {
                        calendar.refresh()
                    }
                }))

            if calendar.authorization == .denied || calendar.authorization == .restricted {
                Button("Calendar access denied — open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Divider()

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

    private func refreshCalendar() {
        calendar.refresh(for: selectedDate, homeTZ: home)
    }

    private func flashToast() {
        withAnimation(.snappy) { showToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { showToast = false }
        }
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
