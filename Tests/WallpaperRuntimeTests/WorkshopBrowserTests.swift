import XCTest
import AppKit
import WebKit
@testable import WallpaperCore
@testable import WallpaperRuntime

@MainActor final class WorkshopBrowserTests: XCTestCase {
    private func item(_ id: String, video: Bool = true, appID: Int = 431960) throws -> WorkshopItem {
        WorkshopItem(id: try WorkshopID(id), title: "Item \(id)", bytes: 100,
                     result: 1, appID: appID, tags: [video ? "Video" : "Scene"])
    }
    private func detail(_ id: String) -> URL { URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(id)")! }
    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Condition did not become true", file: file, line: line)
    }
    func testOnlyStrictOfficialDetailsURLsSelectAnItem() throws {
        for url in [detail("12"), URL(string: "https://steamcommunity.com/workshop/filedetails/?id=12&l=schinese")!] {
            XCTAssertEqual(WorkshopBrowser.pageID(from: url), try WorkshopID("12"))
        }
        for value in [
            "https://steamcommunity.com/workshop/browse/?appid=431960&id=12",
            "https://steamcommunity.com/sharedfiles/filedetails/?id=12&id=34",
            "https://steamcommunity.com/sharedfiles/filedetails/?id=0",
            "https://steamcommunity.com/sharedfiles/filedetails/?id=18446744073709551616",
            "https://steamcommunity.com.evil.test/sharedfiles/filedetails/?id=12",
            "https://user@steamcommunity.com/sharedfiles/filedetails/?id=12",
            "https://steamcommunity.com:443/sharedfiles/filedetails/?id=12",
            "http://steamcommunity.com/sharedfiles/filedetails/?id=12",
            "steam://url/CommunityFilePage/12", "javascript:alert(1)"
        ] { XCTAssertNil(WorkshopBrowser.pageID(from: URL(string: value)), value) }
        XCTAssertNil(WorkshopBrowser.pageID(from: nil))
    }
    func testUsesPersistentSteamWebSessionAndVideoHome() {
        let browser = WorkshopBrowser(loadHome: false)
        defer { browser.close() }
        XCTAssertTrue(browser.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(browser.webView.configuration.websiteDataStore === WKWebsiteDataStore.default())
        let components = URLComponents(url: WorkshopBrowser.home, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.host, "steamcommunity.com")
        XCTAssertEqual(components.queryItems?.first { $0.name == "appid" }?.value, "431960")
        XCTAssertEqual(components.queryItems?.first { $0.name == "requiredtags[]" }?.value, "Video")
    }
    func testLateMetadataCannotReplaceNewerDetailSelection() async throws {
        var pending: [String: CheckedContinuation<WorkshopItem, Error>] = [:]
        let browser = WorkshopBrowser(loadHome: false) { id in
            try await withCheckedThrowingContinuation { pending[id.rawValue] = $0 }
        }
        defer { browser.close() }
        browser.inspectPage(at: detail("12"))
        try await eventually { pending["12"] != nil }
        browser.inspectPage(at: detail("34"))
        XCTAssertNil(browser.currentItem)
        XCTAssertTrue(browser.isChecking)
        try await eventually { pending["34"] != nil }
        pending.removeValue(forKey: "34")!.resume(returning: try item("34"))
        try await eventually { browser.currentItem?.id.rawValue == "34" }
        pending.removeValue(forKey: "12")!.resume(returning: try item("12", video: false))
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(browser.currentItem?.id.rawValue, "34")
        XCTAssertFalse(browser.isChecking)
        XCTAssertNil(browser.errorMessage)
    }
    func testNavigationAwayAndClosingInvalidateNoncooperativeLookup() async throws {
        var pending: CheckedContinuation<WorkshopItem, Error>?
        let browser = WorkshopBrowser(loadHome: false) { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        browser.inspectPage(at: detail("12"))
        try await eventually { pending != nil }
        browser.inspectPage(at: WorkshopBrowser.home)
        XCTAssertNil(browser.currentItem)
        XCTAssertFalse(browser.isChecking)
        browser.close()
        pending!.resume(returning: try item("12"))
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(browser.currentItem)
        XCTAssertFalse(browser.isChecking)
        XCTAssertNil(browser.errorMessage)
    }
    func testMetadataRejectsMismatchedIDAndReportsLookupFailure() async throws {
        let mismatch = try item("34")
        let browser = WorkshopBrowser(loadHome: false) { _ in mismatch }
        defer { browser.close() }
        browser.inspectPage(at: detail("12"))
        try await eventually { !browser.isChecking }
        XCTAssertNil(browser.currentItem)
        XCTAssertNotNil(browser.errorMessage)

        let failed = WorkshopBrowser(loadHome: false) { _ in throw WallpaperError.message("lookup unavailable") }
        defer { failed.close() }
        failed.inspectPage(at: detail("12"))
        try await eventually { !failed.isChecking }
        XCTAssertNil(failed.currentItem)
        XCTAssertTrue(failed.errorMessage?.contains("lookup unavailable") == true)
    }
    func testNonVideoAndWrongAppCannotBecomeDownloadable() async throws {
        for value in [try item("12", video: false), try item("12", appID: 440)] {
            let browser = WorkshopBrowser(loadHome: false) { _ in value }
            browser.inspectPage(at: detail("12"))
            try await eventually { !browser.isChecking }
            XCTAssertFalse(browser.currentItem?.isVideo ?? false)
            browser.close()
        }
    }
    func testExplicitDownloadCapturesIDPreservesManualInputAndBusyOperation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryModel(storeURL: root.appendingPathComponent("state.json"))
        defer { library.engine.stop() }
        var requested: [[WorkshopID]] = []
        let unsupported = try item("12", video: false)
        let model = WorkshopModel(library: library, preferencesURL: root.appendingPathComponent("workshop.json"), itemLoader: { ids in
            requested.append(ids); return [unsupported]
        })
        model.input = "keep this manual link"
        model.downloadItem(try WorkshopID("12"))
        model.downloadItem(try WorkshopID("34"))
        try await eventually { !model.isBusy }
        XCTAssertEqual(requested, [[try WorkshopID("12")]])
        XCTAssertEqual(model.input, "keep this manual link")
        XCTAssertTrue(model.errorMessage?.contains("视频") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("workshop.json").path))
    }
    func testCancelledDownloadCannotReachToolOrSavePreferencesAfterLookup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryModel(storeURL: root.appendingPathComponent("state.json"))
        defer { library.engine.stop() }
        var pending: CheckedContinuation<[WorkshopItem], Error>?
        let preferences = root.appendingPathComponent("workshop.json")
        let model = WorkshopModel(library: library, preferencesURL: preferences, itemLoader: { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        })
        model.downloadItem(try WorkshopID("12"))
        try await eventually { pending != nil }
        model.cancel()
        pending!.resume(returning: [try item("12")])
        try await eventually { !model.isBusy }
        XCTAssertTrue(model.status.contains("取消"))
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferences.path))
    }
    func testExplicitDownloadRechecksMetadataIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryModel(storeURL: root.appendingPathComponent("state.json"))
        defer { library.engine.stop() }
        let different = try item("34")
        let model = WorkshopModel(library: library, preferencesURL: root.appendingPathComponent("workshop.json"), itemLoader: { _ in [different] })
        model.downloadItem(try WorkshopID("12"))
        try await eventually { !model.isBusy }
        XCTAssertTrue(model.errorMessage?.contains("匹配") == true)
    }
    func testLiveOfficialBrowseAndVideoDetails() async throws {
        guard ProcessInfo.processInfo.environment["STEAM_BROWSER_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set STEAM_BROWSER_LIVE_TEST=1 for public Steam page integration")
        }
        _ = NSApplication.shared
        let browser = WorkshopBrowser()
        defer { browser.close() }
        var selected: WorkshopID?
        for _ in 0..<300 {
            try await Task.sleep(for: .milliseconds(200))
            if !browser.webView.isLoading, browser.webView.url?.host == "steamcommunity.com" {
                let links = try? await browser.webView.evaluateJavaScript("Array.from(document.querySelectorAll('a[href]')).map(a => a.href)")
                selected = (links as? [String])?.compactMap { WorkshopBrowser.pageID(from: URL(string: $0)) }.first
                if selected != nil { break }
            }
        }
        if selected == nil {
            let diagnostics = try? await browser.webView.evaluateJavaScript("JSON.stringify({url:location.href,title:document.title,ready:document.readyState,roots:document.querySelectorAll('.workshopBrowseItems').length,links:document.querySelectorAll('a[href]').length})")
            print("Live browser diagnostics: url=\(browser.webView.url?.absoluteString ?? "nil"), loading=\(browser.webView.isLoading), error=\(browser.errorMessage ?? "nil"), DOM=\(diagnostics ?? "nil")")
        }
        let id = try XCTUnwrap(selected, "Official Video browse page must contain selectable details links. \(browser.errorMessage ?? "")")
        browser.webView.load(URLRequest(url: id.url, timeoutInterval: 45))
        for _ in 0..<300 {
            try await Task.sleep(for: .milliseconds(200))
            if browser.currentItem != nil { break }
            if !browser.isLoading, !browser.isChecking, browser.errorMessage != nil { break }
        }
        let value = try XCTUnwrap(browser.currentItem, browser.errorMessage ?? "Missing live detail metadata")
        XCTAssertEqual(value.id, id)
        XCTAssertTrue(value.isVideo)
    }
}
