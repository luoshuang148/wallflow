import XCTest
import AppKit
import WebKit
@testable import WallpaperCore
@testable import WallpaperRuntime

final class SubscriptionTests: XCTestCase {
    @MainActor func snapshot(_ html: String) async throws -> SubscriptionPage {
        _ = NSApplication.shared
        let web = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        web.loadHTMLString(html, baseURL: URL(string: "https://steamcommunity.com/id/test/myworkshopfiles/?appid=431960&browsefilter=mysubscriptions&p=1&l=english"))
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(40))
            if !web.isLoading, (try? await web.evaluateJavaScript("document.readyState")) as? String == "complete" { break }
        }
        let raw = try await web.evaluateJavaScript(SubscriptionPage.script)
        return try SubscriptionPage.decode(raw)
    }
    @MainActor func testDOMExtractsOnlyResultsAndPagination() async throws {
        let page = try await snapshot("""
        <a href="/sharedfiles/filedetails/?id=999">unrelated</a>
        <div class="workshopBrowsePagingInfo">Showing 1-2 of 3 entries</div>
        <div class="workshopBrowseItems"><div class="workshopItem"><a class="ugc" href="/sharedfiles/filedetails/?id=12"></a></div><div class="workshopItem"><a class="ugc" href="/sharedfiles/filedetails/?id=34"></a></div></div>
        <div class="workshopBrowsePagingControls"><a class="pagelink" href="?appid=431960&browsefilter=mysubscriptions&p=2&l=english">2</a></div>
        """)
        XCTAssertEqual(page.ids.map(\.rawValue), ["12", "34"])
        XCTAssertEqual(page.total, 3)
        XCTAssertEqual(page.end, 2)
        XCTAssertTrue(page.next?.query?.contains("p=2") == true)
    }
    @MainActor func testEmptyIsExplicitAndUnknownOrMissingPaginationFails() async throws {
        let empty = try await snapshot("<div id='no_items'><div class='inventory_msg_content'>No matching files were found.</div></div>")
        XCTAssertEqual(empty.total, 0)
        do { _ = try await snapshot("<h1>Sign in</h1>"); XCTFail("Login is not empty") } catch { }
        do { _ = try await snapshot("<div class='workshopBrowsePagingInfo'>Showing 1-1 of 2 entries</div><div class='workshopBrowseItems'><div class='workshopItem'><a class='ugc' href='/sharedfiles/filedetails/?id=12'></a></div></div>"); XCTFail("Missing next is not complete") } catch { }
    }
    func testNavigationScope() {
        XCTAssertTrue(SubscriptionBrowser.isOfficial(URL(string: "https://steamcommunity.com/login/home/")!))
        XCTAssertTrue(SubscriptionBrowser.isOfficial(URL(string: "https://login.steampowered.com/jwt/refresh")!))
        XCTAssertFalse(SubscriptionBrowser.isOfficial(URL(string: "https://steamcommunity.com.evil.test/")!))
        XCTAssertFalse(SubscriptionBrowser.isOfficial(URL(string: "http://steamcommunity.com/")!))
    }
    @MainActor func testActualPublicHTMLUsesSameLegacyStructure() async throws {
        guard let root = ProcessInfo.processInfo.environment["STEAM_HTML_FIXTURES"] else { throw XCTSkip("Set fixtures directory") }
        let two = try await snapshot(String(contentsOfFile: root + "/legacy-workshop.html", encoding: .utf8))
        XCTAssertEqual(two.ids.count, 2)
        XCTAssertEqual(two.total, 2)
        let empty = try await snapshot(String(contentsOfFile: root + "/empty-workshop.html", encoding: .utf8))
        XCTAssertEqual(empty.ids.count, 0)
        XCTAssertEqual(empty.total, 0)
        // Public authored pages use myfiles; rewrite only this filter for the subscription parser fixture.
        let html = try String(contentsOfFile: root + "/paged-workshop.html", encoding: .utf8).replacingOccurrences(of: "browsefilter=myfiles", with: "browsefilter=mysubscriptions")
        let page = try await snapshot(html)
        XCTAssertGreaterThan(page.total, page.ids.count)
        XCTAssertEqual(page.ids.count, 30)
        XCTAssertNotNil(page.next)
    }

    @MainActor func testSubscriptionRowsWithoutPublishedItemsGrid() async throws {
        let page = try await snapshot("""
        <a href="/sharedfiles/filedetails/?id=999">unrelated sidebar link</a>
        <div class="workshopBrowsePagingWithBG">
          <div class="workshopBrowsePagingInfo">Showing 1-2 of 3 entries</div>
          <div class="workshopBrowsePagingControls"><a href="?appid=431960&browsefilter=mysubscriptions&p=2&l=english">&gt;</a></div>
        </div>
        <div class="workshopItemSubscription" id="Subscription12"><div class="itemContents">
          <div class="workshopItemPreviewHolderFloatLeft"><a href="/sharedfiles/filedetails/?id=12"><img></a></div>
          <div class="workshopItemSubscriptionDetails"><a href="/sharedfiles/filedetails/?id=12">First</a></div>
          <button onclick="throw Error('must not change subscriptions')">Subscribed</button>
        </div></div>
        <div class="workshopItemSubscription" id="Subscription34"><div class="itemContents">
          <div class="workshopItemSubscriptionDetails"><a href="/sharedfiles/filedetails/?id=34">Second</a></div>
        </div></div>
        """)
        XCTAssertEqual(page.ids.map(\.rawValue), ["12", "34"])
        XCTAssertEqual(page.total, 3)
        XCTAssertEqual(page.end, 2)
        XCTAssertNotNil(page.next)
    }
    @MainActor func testLastSubscriptionRowPageAndIncompleteRows() async throws {
        let last = try await snapshot("""
        <div class="workshopBrowsePagingInfo">Showing 3-3 of 3 entries</div>
        <div class="workshopItemSubscription" id="Subscription56"><a href="/sharedfiles/filedetails/?id=56">Last</a></div>
        """)
        XCTAssertEqual(last.ids.map(\.rawValue), ["56"])
        XCTAssertEqual(last.end, 3)
        XCTAssertNil(last.next)
        do {
            _ = try await snapshot("<div class='workshopBrowsePagingInfo'>Showing 1-2 of 2 entries</div><div class='workshopItemSubscription'><a href='/sharedfiles/filedetails/?id=12'>Only one</a></div>")
            XCTFail("Incomplete rows must fail")
        } catch { }
    }

}
