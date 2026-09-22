import XCTest

final class OverlapTests: XCTestCase {

    private func tz(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

    private func date(_ s: String, in tz: TimeZone) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = tz
        f.calendar = Calendar(identifier: .gregorian)
        return f.date(from: s)!
    }

    // MARK: - Local hour conversion

    func testLocalHourAndDayOffset() {
        let la = tz("America/Los_Angeles")
        let ny = tz("America/New_York")
        let tokyo = tz("Asia/Tokyo")
        let day = date("2026-09-21", in: la)

        let nineAM_LA = TimeMath.instant(homeHour: 9, on: day, home: la)
        XCTAssertEqual(TimeMath.localHour(of: nineAM_LA, in: la), 9)
        XCTAssertEqual(TimeMath.localHour(of: nineAM_LA, in: ny), 12)
        XCTAssertEqual(TimeMath.localHour(of: nineAM_LA, in: tokyo), 1)

        // Tokyo is already on Sep 22.
        XCTAssertEqual(TimeMath.dayOffset(of: nineAM_LA, target: tokyo, home: la), 1)
        XCTAssertEqual(TimeMath.dayOffset(of: nineAM_LA, target: ny, home: la), 0)
    }

    // MARK: - Good windows

    func testGoodWindows_LaNyLondon() {
        let la = tz("America/Los_Angeles")
        let places = [
            Place(name: "LA", timeZoneID: "America/Los_Angeles", isHome: true),
            Place(name: "NY", timeZoneID: "America/New_York"),
            Place(name: "London", timeZoneID: "Europe/London"),
        ]
        let day = date("2026-09-21", in: la)

        // LA h -> NY h+3 -> London h+8 (PDT→BST = +8 on that date).
        // work = all in [9,18): h>=9 and h+8<18 -> h=9 only.
        let windows = TimeMath.goodWindows(places: places, on: day, home: la)
        XCTAssertEqual(windows.work, [9...9])
        // okay tier (== .okay exactly): h=7,8 (LA fringe) and h=10,11,12
        // (London 18,19,20 → fringe).
        XCTAssertEqual(windows.okay, [7...8, 10...12])
    }

    func testBestEffortWindows() {
        let la = tz("America/Los_Angeles")
        let places = [
            Place(name: "LA", timeZoneID: "America/Los_Angeles", isHome: true),
            Place(name: "NY", timeZoneID: "America/New_York"),
            Place(name: "London", timeZoneID: "Europe/London"),
            Place(name: "Tokyo", timeZoneID: "Asia/Tokyo"),
        ]
        let day = date("2026-09-21", in: la)

        // Score = 2 per place in work tier, 1 per place in okay tier.
        // LA h=9: LA 9(w) NY 12(w) London 17(w) Tokyo 25→1(night) → 6.
        // Tokyo is at night for every reasonable LA business hour, so 6
        // is the max and h=9 is the only column reaching it.
        let effort = TimeMath.bestEffortWindows(places: places, on: day, home: la)
        XCTAssertEqual(effort, [9...9])
    }

    func testGoodWindows_BusyExcludesColumn() {
        let la = tz("America/Los_Angeles")
        let places = [
            Place(name: "LA", timeZoneID: "America/Los_Angeles", isHome: true),
            Place(name: "NY", timeZoneID: "America/New_York"),
            Place(name: "London", timeZoneID: "Europe/London"),
        ]
        let day = date("2026-09-21", in: la)

        // Busy at home hour 9: the only work column disappears and the
        // okay tier still excludes it.
        let windows = TimeMath.goodWindows(places: places, on: day, home: la,
                                           busyHomeHours: [9])
        XCTAssertEqual(windows.work, [])
        XCTAssertEqual(windows.okay, [7...8, 10...12])
    }

    // MARK: - InviteFormatter

    func testInviteFormatter() {
        let la = tz("America/Los_Angeles")
        let places = [
            Place(name: "LA", timeZoneID: "America/Los_Angeles", isHome: true),
            Place(name: "NY", timeZoneID: "America/New_York"),
        ]
        let day = date("2026-09-21", in: la)
        let sel = 9...10

        XCTAssertEqual(
            InviteFormatter.plain(date: day, places: places, selection: sel, home: la, use24: false),
            "LA: Mon Sep 21 9:00 – 11:00 AM\nNY: Mon Sep 21 12:00 – 2:00 PM")
        XCTAssertEqual(
            InviteFormatter.slack(date: day, places: places, selection: sel, home: la, use24: false),
            "*Mon Sep 21*\n• 9:00 – 11:00 AM  LA\n• 12:00 – 2:00 PM  NY")
        XCTAssertEqual(
            InviteFormatter.markdown(date: day, places: places, selection: sel, home: la, use24: false),
            "**Mon Sep 21**\n\n| City | Local time |\n|---|---|\n| LA | 9:00 – 11:00 AM |\n| NY | 12:00 – 2:00 PM |")
    }

    // MARK: - CommandParser

    func testCommandParser() {
        let la = tz("America/Los_Angeles")
        let catalog = CityCatalog()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = la
        let ref = cal.date(from: DateComponents(year: 2026, month: 9, day: 21,
                                                hour: 9, minute: 0))!

        // "3pm Tokyo tomorrow" → jump 15:00 in Tokyo, +1 day.
        guard case .jump(let h, let m, let city, let off, _, _) =
                CommandParser.parse("3pm tokyo tomorrow", catalog: catalog,
                                    referenceDate: ref, homeTZ: la)?.intent else {
            return XCTFail("expected jump")
        }
        XCTAssertEqual(h, 15)
        XCTAssertEqual(m, 0)
        XCTAssertEqual(city?.identifier, "Asia/Tokyo")
        XCTAssertEqual(off, 1)

        // "london, sydney" → addPlaces 2.
        guard case .addPlaces(let ps) =
                CommandParser.parse("london, sydney", catalog: catalog,
                                    referenceDate: ref, homeTZ: la)?.intent else {
            return XCTFail("expected addPlaces")
        }
        XCTAssertEqual(ps.map(\.identifier), ["Europe/London", "Australia/Sydney"])

        // "next tue 10am london" → Tue Sep 29 (+8, the Tue after the coming one).
        guard case .jump(let h2, _, let city2, let off2, let wd, _) =
                CommandParser.parse("next tue 10am london", catalog: catalog,
                                    referenceDate: ref, homeTZ: la)?.intent else {
            return XCTFail("expected jump")
        }
        XCTAssertEqual(h2, 10)
        XCTAssertEqual(city2?.identifier, "Europe/London")
        XCTAssertEqual(wd, 3)              // Tuesday
        XCTAssertEqual(off2, 8)

        // "noon" → jump 12:00 home (no city).
        guard case .jump(let h3, let m3, let city3, _, _, _) =
                CommandParser.parse("noon", catalog: catalog,
                                    referenceDate: ref, homeTZ: la)?.intent else {
            return XCTFail("expected jump")
        }
        XCTAssertEqual(h3, 12)
        XCTAssertEqual(m3, 0)
        XCTAssertNil(city3)

        // "call with berlin and paris" → addPlaces 2.
        guard case .addPlaces(let ps2) =
                CommandParser.parse("call with berlin and paris", catalog: catalog,
                                    referenceDate: ref, homeTZ: la)?.intent else {
            return XCTFail("expected addPlaces")
        }
        XCTAssertEqual(ps2.map(\.identifier), ["Europe/Berlin", "Europe/Paris"])

        XCTAssertNil(CommandParser.parse("asdf qwer", catalog: catalog,
                                         referenceDate: ref, homeTZ: la))
    }

    // MARK: - DST edge

    func testDSTTransition_LondonMar29() {
        // 2026-03-29: UK clocks jump 01:00→02:00 BST. LA is already on PDT.
        let la = tz("America/Los_Angeles")
        let london = tz("Europe/London")
        let day = date("2026-03-29", in: la)

        var hours: [Int] = []
        for h in 0..<24 {
            let inst = TimeMath.instant(homeHour: h, on: day, home: la)
            hours.append(TimeMath.localHour(of: inst, in: london))
        }
        XCTAssertEqual(hours.count, 24)
        // London local hour should progress +1 each column (mod 24);
        // BST transition happened before LA's midnight, so no gaps/dups.
        for i in 1..<24 {
            XCTAssertEqual((hours[i] - hours[i - 1] + 24) % 24, 1,
                           "hour jump at column \(i)")
        }

        // And a date where LA itself transitions: 2026-03-08 PDT start.
        // Local hour 2 doesn't exist — the sequence skips it (0,1,3,4,…)
        // and the last column lands on next-day 0 because the day is 23h.
        let laSpring = date("2026-03-08", in: la)
        var laHours: [Int] = []
        for h in 0..<24 {
            let inst = TimeMath.instant(homeHour: h, on: laSpring, home: la)
            laHours.append(TimeMath.localHour(of: inst, in: la))
        }
        XCTAssertEqual(laHours.count, 24)
        for h in laHours { XCTAssertTrue((0..<24).contains(h)) }
        for i in 1..<24 {
            let diff = (laHours[i] - laHours[i - 1] + 24) % 24
            XCTAssertTrue(diff == 1 || diff == 2,
                          "unexpected jump \(diff) at column \(i)")
        }
        XCTAssertTrue(laHours.contains(3) && !laHours.contains(2))
    }

    // MARK: - CityCatalog search

    func testCatalogSearch() {
        let catalog = CityCatalog()

        let nyc = catalog.search("nyc")
        XCTAssertEqual(nyc.first?.identifier, "America/New_York")

        let lon = catalog.search("lon")
        XCTAssertEqual(lon.first?.name, "London")

        let sf = catalog.search("sf")
        XCTAssertEqual(sf.first?.identifier, "America/Los_Angeles")
    }
}
