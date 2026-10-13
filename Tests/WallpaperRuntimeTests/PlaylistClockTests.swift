import XCTest
import WallpaperCore
@testable import WallpaperRuntime

final class PlaylistClockTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 13) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func interval() -> PlaylistSettings {
        var settings = PlaylistSettings()
        settings.enabled = true
        settings.projectIDs = ["a", "b", "c"]
        settings.intervalMinutes = 1
        return settings
    }
    private func dayNight() -> PlaylistSettings {
        var settings = interval()
        settings.mode = .dayNight
        settings.dayProjectID = "a"
        settings.nightProjectID = "b"
        return settings
    }
    func testIntervalWaitsThenFollowsCurrentWithoutCatchup() {
        var clock = PlaylistClock()
        let settings = interval(), start = date(8)
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start, canAdvance: true))
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start.addingTimeInterval(59), canAdvance: true))
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start.addingTimeInterval(3600), canAdvance: true), "b")
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "b", now: start.addingTimeInterval(3601), canAdvance: true))
    }
    func testFailedAttemptDoesNotRepeatSameSequentialItem() {
        var clock = PlaylistClock()
        let settings = interval(), start = date(8)
        _ = clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start, canAdvance: true)
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start.addingTimeInterval(60), canAdvance: true), "b")
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start.addingTimeInterval(120), canAdvance: true), "c")
    }
    func testSequentialSkipsUnavailableIDsAndDuplicates() {
        var clock = PlaylistClock()
        var settings = interval()
        settings.projectIDs = ["a", "gone", "b", "b", "c"]
        let start = date(8)
        _ = clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start, canAdvance: true)
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start.addingTimeInterval(60), canAdvance: true), "b")
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "b", now: start.addingTimeInterval(120), canAdvance: true), "c")
    }
    func testRandomExcludesCurrentAndInjectsChoice() {
        var clock = PlaylistClock()
        var settings = interval()
        settings.order = .random
        let start = date(8)
        _ = clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "b", now: start, canAdvance: true)
        var candidateCount = 0
        let result = clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "b", now: start.addingTimeInterval(60), canAdvance: true) { count in
            candidateCount = count
            return count - 1
        }
        XCTAssertEqual(candidateCount, 2)
        XCTAssertEqual(result, "c")
    }
    func testSequentialFollowsRemovedLastAttemptInConfiguredOrder() {
        var clock = PlaylistClock()
        let settings = interval(), start = date(8)
        _ = clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start, canAdvance: true)
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start.addingTimeInterval(60), canAdvance: true), "b")
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "c"], currentID: "a", now: start.addingTimeInterval(120), canAdvance: true), "c")
    }
    func testBusyTickLeavesOverdueIntervalPending() {
        var clock = PlaylistClock()
        let settings = interval(), start = date(8)
        _ = clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: start, canAdvance: true)
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: start.addingTimeInterval(60), canAdvance: false))
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: start.addingTimeInterval(61), canAdvance: true), "b")
    }
    func testSettingsChangeAndResetRestartInterval() {
        var clock = PlaylistClock()
        var settings = interval()
        let start = date(8)
        _ = clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: start, canAdvance: true)
        settings.intervalMinutes = 2
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: start.addingTimeInterval(60), canAdvance: true))
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: start.addingTimeInterval(179), canAdvance: true))
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: start.addingTimeInterval(180), canAdvance: true), "b")
        clock.reset()
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "b", now: start.addingTimeInterval(400), canAdvance: true))
    }
    func testManualIntervalChoiceRestartsDeadlineAndSequence() {
        var clock = PlaylistClock()
        let settings = interval(), start = date(8)
        _ = clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "a", now: start, canAdvance: true)
        clock.noteManualChoice("b", settings: settings, now: start.addingTimeInterval(50))
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "b", now: start.addingTimeInterval(60), canAdvance: true))
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "b", now: start.addingTimeInterval(110), canAdvance: true), "c")
    }
    func testDayNightFirstEligibleTickAndBoundaryApplyOnce() {
        var clock = PlaylistClock()
        let settings = dayNight()
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "b", now: date(9), calendar: calendar, canAdvance: false))
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "b", now: date(9), calendar: calendar, canAdvance: true), "a")
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "b", now: date(10), calendar: calendar, canAdvance: true))
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: date(20), calendar: calendar, canAdvance: true), "b")
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "b", now: date(21), calendar: calendar, canAdvance: true))
    }
    func testManualDayNightChoiceHoldsUntilNextBoundary() {
        var clock = PlaylistClock()
        let settings = dayNight()
        clock.noteManualChoice("c", settings: settings, now: date(9), calendar: calendar)
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "c", now: date(19, 59), calendar: calendar, canAdvance: true))
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b", "c"], currentID: "c", now: date(20), calendar: calendar, canAdvance: true), "b")
    }
    func testDayNightPauseAcrossMultipleDaysDoesNotLosePhase() {
        var clock = PlaylistClock()
        let settings = dayNight()
        _ = clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "b", now: date(9, day: 13), calendar: calendar, canAdvance: true)
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: date(21, day: 14), calendar: calendar, canAdvance: false))
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "c", now: date(9, day: 15), calendar: calendar, canAdvance: true), "a")
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: date(9, 1, day: 15), calendar: calendar, canAdvance: true))
    }
    func testOvernightDayWindowUsesLocalCalendar() {
        var clock = PlaylistClock()
        var settings = dayNight()
        settings.dayStartMinute = 22 * 60
        settings.nightStartMinute = 6 * 60
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: nil, now: date(2), calendar: calendar, canAdvance: true), "a")
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: date(5, 59), calendar: calendar, canAdvance: true))
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: date(6), calendar: calendar, canAdvance: true), "b")
    }
    func testUnavailableDayProjectRemainsPendingAndDisabledNeverAdvances() {
        var clock = PlaylistClock()
        var settings = dayNight()
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["b"], currentID: "b", now: date(9), calendar: calendar, canAdvance: true))
        XCTAssertEqual(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "b", now: date(10), calendar: calendar, canAdvance: true), "a")
        settings.enabled = false
        XCTAssertNil(clock.next(settings: settings, availableIDs: ["a", "b"], currentID: "a", now: date(21), calendar: calendar, canAdvance: true))
    }
}
