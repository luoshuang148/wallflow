import XCTest
@testable import WallpaperCore

final class WorkshopTests: XCTestCase {
    func testStrictIDsAndSteamLinks() throws {
        for value in ["3524676173", " https://steamcommunity.com/sharedfiles/filedetails/?id=3524676173&searchtext=roxy ", "https://steamcommunity.com/workshop/filedetails/?id=3524676173"] {
            XCTAssertEqual(try WorkshopID(value).rawValue, "3524676173")
        }
        for value in ["0", "-1", "１２３", "123 +quit", "https://steamcommunity.com.evil.test/sharedfiles/filedetails/?id=1", "https://evil@steamcommunity.com/sharedfiles/filedetails/?id=1", "http://steamcommunity.com/sharedfiles/filedetails/?id=1", "https://steamcommunity.com/sharedfiles/filedetails/?id=1&id=2", "18446744073709551616"] {
            XCTAssertThrowsError(try WorkshopID(value), value)
        }
    }
    func testManifestUsesOnlyInstalledItemsAndRejectsMalformedKV() throws {
        let text = "\"AppWorkshop\" { \"appid\" \"431960\" \"WorkshopItemsInstalled\" { \"12\" { \"manifest\" \"999\" } \"34\" { } } \"WorkshopItemDetails\" { \"56\" { } } }"
        XCTAssertEqual(try SteamKeyValues.installedIDs(text).map(\.rawValue), ["12", "34"])
        XCTAssertThrowsError(try SteamKeyValues.installedIDs(text.replacingOccurrences(of: "431960", with: "440")))
        XCTAssertThrowsError(try SteamKeyValues.parse("\"x\" { \"y\""))
        XCTAssertEqual(try SteamKeyValues.parse("// comment\n\"Accounts\" { \"foo\" { \"SteamID\" \"123\" } }").object("Accounts")?.keys, ["foo"])
    }
    func testMetadataFiltersVideoAndChecksResultAndApp() throws {
        let data = Data("{\"response\":{\"publishedfiledetails\":[{\"publishedfileid\":\"12\",\"result\":1,\"consumer_app_id\":431960,\"title\":\"Video\",\"file_size\":\"900\",\"tags\":[{\"tag\":\"Video\"}]},{\"publishedfileid\":\"34\",\"result\":1,\"consumer_app_id\":431960,\"tags\":[{\"tag\":\"Scene\"}]},{\"publishedfileid\":\"56\",\"result\":9} ]}}".utf8)
        let items = try WorkshopItem.decodeResponse(data)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0].isVideo)
        XCTAssertEqual(items[0].bytes, 900)
        XCTAssertFalse(items[1].isVideo)
        XCTAssertFalse(items[2].isVideo)
    }
    func testSuccessRequiresCurrentIDExitZeroAndExplicitMarker() throws {
        let id = try WorkshopID("12")
        let good = "Success. Downloaded item 12 to \"/tmp/content/431960/12\" (900 bytes)"
        XCTAssertEqual(try SteamDownloadResult.folder(output: good, exitCode: 0, id: id).path, "/tmp/content/431960/12")
        XCTAssertThrowsError(try SteamDownloadResult.folder(output: good, exitCode: 1, id: id))
        XCTAssertThrowsError(try SteamDownloadResult.folder(output: good, exitCode: 0, id: WorkshopID("34")))
        XCTAssertThrowsError(try SteamDownloadResult.folder(output: "ERROR! Download item 12 failed (Failure).", exitCode: 0, id: id))
    }
}
