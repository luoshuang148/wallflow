import Foundation
import WebKit
import Combine
import WallpaperCore

public struct SubscriptionPage {
    public let ids: [WorkshopID]
    public let total: Int
    public let end: Int
    public let next: URL?
    public static func decode(_ raw: Any) throws -> SubscriptionPage {
        guard let d = raw as? [String: Any] else { throw WallpaperError.message(L("workshop.subscriptions.couldNotReadTheSubscriptionsPage")) }
        if let error = d["error"] as? String { throw WallpaperError.message(L(error)) }
        guard let values = d["ids"] as? [String], let total = d["total"] as? Int, let end = d["end"] as? Int,
              total >= 0, total <= 10000, end <= total else { throw WallpaperError.message(L("workshop.subscriptions.theSubscriptionsPageStructureIsUnrecognized")) }
        let ids = try values.map(WorkshopID.init)
        let next = (d["next"] as? String).flatMap(URL.init(string:))
        guard Set(ids).count == ids.count, (end == total || next != nil),
              next == nil || SubscriptionBrowser.isSubscriptionURL(next!) else { throw WallpaperError.message(L("workshop.subscriptions.subscriptionPaginationIsIncompleteTheListWasKept")) }
        return SubscriptionPage(ids: ids, total: total, end: end, next: next)
    }
    public static let script = #"""
    (() => {
      const error = message => ({error: message});
      const url = new URL(document.baseURI);
      if (url.hostname !== 'steamcommunity.com' || !/\/(my|id\/[^/]+|profiles\/\d+)\/myworkshopfiles\/?$/.test(url.pathname) || url.searchParams.get('appid') !== '431960' || url.searchParams.get('browsefilter') !== 'mysubscriptions')
        return error('workshop.subscriptions.pageSignInRequired');
      const empty = document.querySelector('#no_items .inventory_msg_content');
      if (empty && /No matching files were found/i.test(empty.textContent)) return {ids: [], total: 0, end: 0, next: null};
      const root = document.querySelector('.workshopBrowseItems');
      // Steam uses full-width subscription rows, separately from published-item grids.
      const subscriptions = [...document.querySelectorAll('.workshopItemSubscription')];
      const rows = subscriptions.length ? subscriptions : [...(root?.querySelectorAll('.workshopItem') || [])];
      const info = document.querySelector('.workshopBrowsePagingInfo');
      if (!rows.length || !info) return error('workshop.subscriptions.pageNotReady');
      const range = info.textContent.match(/Showing\s+([\d,]+)\s*[-–]\s*([\d,]+)\s+of\s+([\d,]+)\s+entries/i);
      if (!range) return error('workshop.subscriptions.pageCountUnrecognized');
      const start = Number(range[1].replaceAll(',', '')), end = Number(range[2].replaceAll(',', '')), total = Number(range[3].replaceAll(',', ''));
      const ids = [...new Set(rows.flatMap(row => [...row.querySelectorAll('a[href]')]).flatMap(a => {
        const u = new URL(a.href, document.baseURI);
        const id = u.searchParams.get('id');
        return u.hostname === 'steamcommunity.com' && /^\/(sharedfiles|workshop)\/filedetails\/?$/.test(u.pathname) && /^[0-9]+$/.test(id || '') ? [id] : [];
      }))];
      if (ids.length !== end-start+1 || start < 1 || end > total) return error('workshop.subscriptions.pageIncomplete');
      const current = Number(url.searchParams.get('p') || '1');
      const links = [...document.querySelectorAll('.workshopBrowsePagingControls a[href]')].map(a => new URL(a.href, document.baseURI));
      const next = links.find(u => u.hostname === url.hostname && u.pathname === url.pathname && u.searchParams.get('appid') === '431960' && u.searchParams.get('browsefilter') === 'mysubscriptions' && Number(u.searchParams.get('p')) === current+1);
      if (end < total && !next) return error('workshop.subscriptions.pageNextMissing');
      return {ids, total, end, next: end < total ? next.href : null};
    })()
    """#
}

@MainActor public final class SubscriptionBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    public static let home = URL(string: "https://steamcommunity.com/my/myworkshopfiles/?appid=431960&browsefilter=mysubscriptions&numperpage=30&l=english&p=1")!
    public let webView: WKWebView
    @Published public private(set) var address = home.absoluteString
    @Published public private(set) var isReading = false
    @Published public private(set) var status = L("workshop.subscriptions.signInOnTheOfficialSteamWebsiteThen")
    @Published public var errorMessage: String?
    private var navigationError: String?
    private var task: Task<Void, Never>?
    public override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.load(URLRequest(url: Self.home))
    }
    nonisolated public static func isOfficial(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil &&
        ["steamcommunity.com", "store.steampowered.com", "login.steampowered.com", "help.steampowered.com"].contains(url.host?.lowercased() ?? "")
    }
    nonisolated public static func isSubscriptionURL(_ url: URL) -> Bool {
        guard isOfficial(url), url.host == "steamcommunity.com", url.path.range(of: "^/(my|id/[^/]+|profiles/[0-9]+)/myworkshopfiles/?$", options: .regularExpression) != nil,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return c.queryItems?.first(where: { $0.name == "appid" })?.value == "431960" && c.queryItems?.first(where: { $0.name == "browsefilter" })?.value == "mysubscriptions"
    }
    public func goHome() { guard !isReading else { return }; navigationError = nil; webView.load(URLRequest(url: Self.home)) }
    public func cancel() { task?.cancel(); webView.stopLoading() }
    public func readAll(completion: @escaping ([WorkshopID]) -> Void) {
        guard !isReading else { return }
        isReading = true; errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isReading = false; self.task = nil }
            do {
                var next: URL? = Self.home
                var visited = Set<String>(); var all: [WorkshopID] = []; var expectedTotal: Int?
                for pageNumber in 1...100 {
                    try Task.checkCancellation()
                    guard let target = next, visited.insert(target.absoluteString).inserted else { throw WallpaperError.message(L("workshop.subscriptions.subscriptionPaginationLoopsTheListWasKept")) }
                    self.status = String(format: L("workshop.subscriptions.readingPageItemsCollected"), String(describing: pageNumber), String(describing: all.count))
                    try await self.navigate(target)
                    let raw = try await self.webView.evaluateJavaScript(SubscriptionPage.script)
                    let page = try SubscriptionPage.decode(raw)
                    if let expectedTotal, expectedTotal != page.total { throw WallpaperError.message(L("workshop.subscriptions.theSubscriptionCountChangedWhileReadingReadThe")) }
                    expectedTotal = page.total
                    all += page.ids
                    guard Set(all).count == all.count, all.count == page.end else { throw WallpaperError.message(L("workshop.subscriptions.subscriptionPagesContainDuplicatesOrMissingItemsRead")) }
                    next = page.next
                    if next == nil {
                        guard all.count == page.total else { throw WallpaperError.message(L("workshop.subscriptions.theSubscriptionListIsIncompleteReadItAgain")) }
                        try Task.checkCancellation()
                        self.status = String(format: L("workshop.subscriptions.readAllSubscriptions"), String(describing: all.count))
                        completion(all); return
                    }
                }
                throw WallpaperError.message(L("workshop.subscriptions.subscriptionsExceed100PagesReadingDidNotFinish"))
            } catch is CancellationError { self.status = L("workshop.subscriptions.readingCancelled") }
            catch { self.errorMessage = error.localizedDescription; self.status = L("workshop.subscriptions.readingDidNotFinishThePreviousListWas") }
        }
    }
    private func navigate(_ url: URL) async throws {
        navigationError = nil
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 40))
        let deadline = Date().addingTimeInterval(45)
        repeat {
            try await Task.sleep(for: .milliseconds(200))
            try Task.checkCancellation()
            if let navigationError { throw WallpaperError.message(navigationError) }
            if !webView.isLoading {
                guard let actual = webView.url, Self.isSubscriptionURL(actual) else { throw WallpaperError.message(L("workshop.subscriptions.signInOnTheOfficialSteamWebsiteFirst")) }
                try await Task.sleep(for: .milliseconds(500)); return
            }
        } while Date() < deadline
        webView.stopLoading(); throw WallpaperError.message(L("workshop.subscriptions.theSteamSubscriptionsPageTimedOutCheckYour"))
    }
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, Self.isOfficial(url) else { decisionHandler(.cancel); return }
        if isReading && navigationAction.navigationType == .linkActivated { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { address = webView.url?.absoluteString ?? "" }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { record(error) }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { record(error) }
    private func record(_ error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { navigationError = String(format: L("workshop.subscriptions.steamPageFailedToLoad"), String(describing: error.localizedDescription)); errorMessage = navigationError }
    }
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, Self.isOfficial(url) { webView.load(navigationAction.request) }
        return nil
    }
}
