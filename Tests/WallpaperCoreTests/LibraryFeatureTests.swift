import XCTest
@testable import WallpaperCore

final class LibraryFeatureTests: XCTestCase {
    func testDefaultsAndCodableRoundTrip() throws {
        let organization = LibraryOrganization()
        XCTAssertTrue(organization.favorites.isEmpty)
        XCTAssertTrue(organization.groups.isEmpty)
        XCTAssertTrue(organization.memberships.isEmpty)
        XCTAssertEqual(organization.sort, .added)
        XCTAssertEqual(try JSONDecoder().decode(LibraryOrganization.self, from: JSONEncoder().encode(organization)), organization)
        XCTAssertEqual(try JSONDecoder().decode(LibraryOrganization.self, from: Data("{}".utf8)), organization)
        let playlist = PlaylistSettings()
        XCTAssertFalse(playlist.enabled)
        XCTAssertEqual(playlist.intervalMinutes, 30)
        XCTAssertEqual(playlist.dayStartMinute, 480)
        XCTAssertEqual(playlist.nightStartMinute, 1200)
        XCTAssertEqual(try JSONDecoder().decode(PlaylistSettings.self, from: Data("{}".utf8)), playlist)
        XCTAssertEqual(try JSONDecoder().decode(PlaylistSettings.self, from: JSONEncoder().encode(playlist)), playlist)
        let rule = ApplicationRule(bundleID: "com.example.editor", name: "Editor")
        XCTAssertEqual(rule.condition, .frontmost)
        XCTAssertEqual(rule.action, .pause)
        XCTAssertTrue(rule.enabled)
        XCTAssertEqual(try JSONDecoder().decode(ApplicationRule.self, from: JSONEncoder().encode(rule)), rule)
    }
    func testGroupNamesTrimAndRejectEmptyOrDuplicate() throws {
        var value = LibraryOrganization()
        let id = try value.addGroup("  Café \n")
        XCTAssertEqual(value.groups.first?.name, "Café")
        XCTAssertThrowsError(try value.addGroup(" \n"))
        XCTAssertThrowsError(try value.addGroup("CAFÉ"))
        let other = try value.addGroup("Other")
        XCTAssertThrowsError(try value.renameGroup(other, name: " café "))
        XCTAssertThrowsError(try value.renameGroup(id, name: "\t"))
        try value.renameGroup(id, name: " New ")
        XCTAssertEqual(value.groups.first?.name, "New")
        XCTAssertThrowsError(try value.renameGroup("missing", name: "Name"))
    }
    func testRemovalCleansOnlyRelatedMetadata() throws {
        var value = LibraryOrganization()
        let first = try value.addGroup("First")
        let second = try value.addGroup("Second")
        value.memberships = ["a": first, "b": second]
        value.toggleFavorite("a")
        value.toggleFavorite("b")
        value.toggleFavorite("b")
        XCTAssertEqual(value.favorites, ["a"])
        value.deleteGroup(first)
        XCTAssertNil(value.memberships["a"])
        XCTAssertEqual(value.memberships["b"], second)
        XCTAssertTrue(value.favorites.contains("a"))
        value.removeProject("a")
        XCTAssertTrue(value.favorites.isEmpty)
        value.removeProject("b")
        XCTAssertTrue(value.memberships.isEmpty)
        XCTAssertEqual(value.groups.map(\.id), [second])
    }
    func testFiltersComposeAndSortIsStable() throws {
        let a = WallpaperProject(folderPath: "/1", title: "Alpha", videoPath: "/1/v", previewPath: nil)
        let b = WallpaperProject(folderPath: "/2", title: "Beta", videoPath: "/2/v", previewPath: nil)
        let c = WallpaperProject(folderPath: "/3", title: "Alpha", videoPath: "/3/v", previewPath: nil)
        let projects = [b, c, a]
        var value = LibraryOrganization()
        value.favorites = [a.id, b.id]
        value.memberships = [a.id: "g", c.id: "g"]
        XCTAssertEqual(value.filterAndSort(projects, query: "alpha", favoritesOnly: true, groupID: "g"), [a])
        XCTAssertEqual(value.filterAndSort(projects, query: "", favoritesOnly: false, groupID: nil), projects)
        value.sort = .title
        XCTAssertEqual(value.filterAndSort(projects, query: "", favoritesOnly: false, groupID: nil), [c, a, b])
        value.sort = .favoritesFirst
        XCTAssertEqual(value.filterAndSort(projects, query: "", favoritesOnly: false, groupID: nil), [b, a, c])
        value.sort = .newest
        XCTAssertEqual(value.filterAndSort(projects, query: "", favoritesOnly: false, groupID: nil), [a, c, b])
    }
    func testIntervalValidationRejectsMissingDuplicateAndOutOfRange() throws {
        var value = PlaylistSettings()
        try value.validate(availableIDs: [])
        value.enabled = true
        XCTAssertThrowsError(try value.validate(availableIDs: ["a", "b"]))
        value.projectIDs = ["a", "a"]
        XCTAssertThrowsError(try value.validate(availableIDs: ["a", "b"]))
        value.projectIDs = ["a", "missing"]
        XCTAssertThrowsError(try value.validate(availableIDs: ["a", "b"]))
        value.projectIDs = ["a", "b"]
        for interval in [0, 1441] {
            value.intervalMinutes = interval
            XCTAssertThrowsError(try value.validate(availableIDs: ["a", "b"]))
        }
        for interval in [1, 1440] {
            value.intervalMinutes = interval
            try value.validate(availableIDs: ["a", "b"])
        }
    }
    func testDayNightValidationAndBoundariesIncludingOvernight() throws {
        var value = PlaylistSettings()
        value.enabled = true
        value.mode = .dayNight
        value.dayProjectID = "a"
        value.nightProjectID = "b"
        try value.validate(availableIDs: ["a", "b"])
        value.nightProjectID = "missing"
        XCTAssertThrowsError(try value.validate(availableIDs: ["a", "b"]))
        value.nightProjectID = "b"
        value.nightStartMinute = value.dayStartMinute
        XCTAssertThrowsError(try value.validate(availableIDs: ["a", "b"]))
        value.nightStartMinute = 1440
        XCTAssertThrowsError(try value.validate(availableIDs: ["a", "b"]))
        value.nightStartMinute = 1200
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        func date(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: hour, minute: minute))!
        }
        XCTAssertFalse(value.isDay(at: date(7, 59), calendar: calendar))
        XCTAssertTrue(value.isDay(at: date(8), calendar: calendar))
        XCTAssertFalse(value.isDay(at: date(20), calendar: calendar))
        value.dayStartMinute = 1200
        value.nightStartMinute = 480
        XCTAssertTrue(value.isDay(at: date(23), calendar: calendar))
        XCTAssertTrue(value.isDay(at: date(7, 59), calendar: calendar))
        XCTAssertFalse(value.isDay(at: date(8), calendar: calendar))
        XCTAssertTrue(value.isDay(at: date(20), calendar: calendar))
    }
    func testApplicationEffectsCombineConditionsAndStrongestAction() {
        let rules = [
            ApplicationRule(bundleID: "editor", name: "Editor", condition: .running, action: .mute),
            ApplicationRule(bundleID: "game", name: "Game", condition: .frontmost, action: .stop),
            ApplicationRule(bundleID: "disabled", name: "Disabled", condition: .running, action: .stop, enabled: false),
            ApplicationRule(bundleID: "browser", name: "Browser", condition: .frontmost, action: .pause)
        ]
        XCTAssertEqual(ApplicationEffects.evaluate(rules, running: ["disabled"], frontmost: nil), ApplicationEffects())
        XCTAssertEqual(ApplicationEffects.evaluate(rules, running: ["editor", "game"], frontmost: "other"), ApplicationEffects(muted: true))
        XCTAssertEqual(ApplicationEffects.evaluate(rules, running: ["editor", "game"], frontmost: "game"), ApplicationEffects(muted: true, paused: true, stopped: true))
        XCTAssertEqual(ApplicationEffects.evaluate(rules, running: ["browser"], frontmost: "browser"), ApplicationEffects(paused: true))
        XCTAssertEqual(ApplicationEffects.evaluate([rules[1]], running: ["game"], frontmost: "game"), ApplicationEffects(paused: true, stopped: true))
    }
}
