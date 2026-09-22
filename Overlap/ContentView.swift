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
    @State private var pulseHour: Int? = nil
    @FocusState private var searchFocused: Bool

    private var hotkey: HotKeyManager { .shared }

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
                    .overlay(alignment: .topLeading) {
                        if let p = pulseHour {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Theme.accentB, lineWidth: 1.5)
                                .shadow(color: Theme.accentB.opacity(0.8), radius: 5)
                                .frame(width: colPitch - 1)
                                .offset(x: stripX + CGFloat(p) * colPitch + 0.5)
                                .allowsHitTesting(false)
                        }
                    }
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
            if !query.isEmpty { query = "" }
            else if selection != nil { selection = nil }
            else { dismiss() }
        }
        .sheet(isPresented: Binding(
            get: { hotkey.showRecorder },
            set: { hotkey.showRecorder = $0 })) {
            VStack(spacing: 12) {
                Text("Press a shortcut (⌥/⇧/⌃/⌘ + key)")
                    .font(.system(size: 12, weight: .medium))
                Text("Esc to cancel")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                HotKeyRecorder(
                    onCapture: { code, mods in
                        hotkey.set(keyCode: code, modifiers: mods)
                        hotkey.showRecorder = false
                    },
                    onCancel: { hotkey.showRecorder = false })
                .frame(width: 220, height: 30)
            }
            .padding(20)
        }
        .onAppear {
            HotKeyManager.shared.handler = { toggleMainWindow() }
        }
        .background(
            // ⌘K — focus the command bar (hidden, always active)
            Button("") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)
        )
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

            // Command bar
            CommandBar(query: $query,
                       focused: $searchFocused,
                       home: home,
                       referenceDate: selectedDate,
                       preview: jumpPreview,
                       onRun: runQuery)
            .frame(width: 190)

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
            Button("Global shortcut: \(hotkey.label)") {
                if standalone {
                    hotkey.showRecorder = true
                } else {
                    openWindow(id: "main")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        hotkey.showRecorder = true
                    }
                }
            }
            if hotkey.enabled {
                Button("Clear shortcut") { hotkey.disable() }
            }

            Divider()

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

    /// Toggle the standalone window for the global hotkey.
    private func toggleMainWindow() {
        if let w = NSApp.windows.first(where: { $0.title == "Overlap" }), w.isVisible {
            w.orderOut(nil)
            return
        }
        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
            if let w = NSApp.windows.first(where: { $0.title == "Overlap" }) {
                w.center()
                let mouse = NSEvent.mouseLocation
                var f = w.frame
                f.origin.x = mouse.x - f.width / 2
                f.origin.y = mouse.y - f.height / 2
                w.setFrameOrigin(f.origin)
                w.makeKeyAndOrderFront(nil)
            }
            searchFocused = true
        }
    }

    // MARK: - Command bar

    private var parsedCommand: ParsedCommand? {
        CommandParser.parse(query, catalog: .shared,
                            referenceDate: selectedDate, homeTZ: home)
    }

    /// "Jump to 3:00 PM Tokyo · Tue Sep 22" preview for the dropdown.
    private var jumpPreview: String? {
        guard let cmd = parsedCommand,
              case .jump(_, _, let city, _, _, _) = cmd.intent,
              let (instant, homeDay, _) = resolve(cmd) else { return nil }
        let tz = city.flatMap { TimeZone(identifier: $0.identifier) } ?? home
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = use24 ? "H:mm" : "h:mm a"
        let df = DateFormatter()
        df.timeZone = home
        df.dateFormat = "EEE MMM d"
        let where_ = city?.name ?? "home"
        return "Jump to \(f.string(from: instant)) \(where_) · \(df.string(from: homeDay))"
    }

    /// Resolve a jump command to (instant, home-day, home column hour).
    private func resolve(_ cmd: ParsedCommand) -> (Date, Date, Int)? {
        guard case .jump(let h, let m, let city, let off, _, let md) = cmd.intent
        else { return nil }
        let tz = city.flatMap { TimeZone(identifier: $0.identifier) } ?? home
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        var day = cal.startOfDay(for: selectedDate)
        if let off {
            day = cal.date(byAdding: .day, value: off, to: day) ?? day
        } else if let md {
            var c = cal.dateComponents([.year], from: selectedDate)
            c.month = md.month; c.day = md.day
            day = cal.date(from: c) ?? day
            if day < cal.startOfDay(for: selectedDate) {
                day = cal.date(byAdding: .year, value: 1, to: day) ?? day
            }
        }
        var t = cal.dateComponents([.year, .month, .day], from: day)
        t.hour = h; t.minute = m
        guard let instant = cal.date(from: t) else { return nil }

        var hcal = Calendar(identifier: .gregorian)
        hcal.timeZone = home
        let homeDay = hcal.startOfDay(for: instant)
        let col = max(0, min(23, Int(instant.timeIntervalSince(homeDay) / 3600)))
        return (instant, homeDay, col)
    }

    /// Execute the command-bar input (⏎).
    private func runQuery() {
        if let cmd = parsedCommand {
            execute(cmd)
        } else if let city = CityCatalog.shared.search(query).first {
            store.add(name: city.name, timeZoneID: city.identifier)
        }
        query = ""
    }

    private func execute(_ cmd: ParsedCommand) {
        switch cmd.intent {
        case .addPlaces(let cities):
            for c in cities where !store.places.contains(where: {
                $0.timeZoneID == c.identifier }) {
                store.add(name: c.name, timeZoneID: c.identifier)
            }
        case .jump(_, _, let city, _, _, _):
            guard let (_, homeDay, col) = resolve(cmd) else { return }
            if let city, !store.places.contains(where: { $0.timeZoneID == city.identifier }) {
                store.add(name: city.name, timeZoneID: city.identifier)
            }
            withAnimation(.snappy) {
                selectedDate = homeDay
                selection = col...col
            }
            pulseHour = col
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                pulseHour = nil
            }
        }
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

// MARK: - Command bar with suggestions dropdown

struct CommandBar: View {
    @Binding var query: String
    @FocusState.Binding var focused: Bool
    var home: TimeZone
    var referenceDate: Date
    var preview: String?
    var onRun: () -> Void

    private var results: [City] { CityCatalog.shared.search(query, limit: 5) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Add a city, or try “3pm Tokyo tomorrow”", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { onRun() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.card, in: Capsule())
        }
        .overlay(alignment: .topLeading) {
            if focused && (preview != nil || !results.isEmpty) {
                VStack(alignment: .leading, spacing: 0) {
                    if let preview {
                        Button { onRun() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.accentB)
                                Text(preview)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                    ForEach(results.prefix(preview == nil ? 5 : 4)) { city in
                        Button { onRun() } label: {
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
                .frame(width: 240)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1)))
                .offset(y: 32)
                .zIndex(10)
            }
        }
        .zIndex(10)
    }
}
