import Foundation
import WebKit
import Combine
import WallpaperCore

@MainActor public final class WorkshopBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    public typealias ItemLoader = (WorkshopID) async throws -> WorkshopItem
    public static let home = URL(string: "https://steamcommunity.com/workshop/browse/?appid=431960&browsesort=trend&section=readytouseitems&requiredtags%5B%5D=Video&l=\(L("workshop.browser.steamLanguage"))")!
    public let webView: WKWebView
    @Published public private(set) var address = home.absoluteString
    @Published public private(set) var isLoading = false
    @Published public private(set) var canGoBack = false
    @Published public private(set) var canGoForward = false
    @Published public private(set) var currentItem: WorkshopItem?
    @Published public private(set) var isChecking = false
    @Published public private(set) var errorMessage: String?
    private let itemLoader: ItemLoader
    private var lookup: Task<Void, Never>?
    private var generation = UUID()
    private var pageURL: URL?
    private var isClosed = false
    private var urlObservation: NSKeyValueObservation?

    public init(loadHome: Bool = true, itemLoader: @escaping ItemLoader = { id in
        try await WorkshopModel.fetchItems([id])[0]
    }) {
        self.itemLoader = itemLoader
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }
                self.updateNavigation()
                // Also invalidate detail selection for a same-document URL change.
                if self.pageURL != self.webView.url {
                    if self.webView.isLoading {
                        self.clearSelection(); self.pageURL = self.webView.url
                    } else { self.inspectPage(at: self.webView.url) }
                }
            }
        }
        if loadHome { goHome() }
    }
    nonisolated public static func pageID(from url: URL?) -> WorkshopID? {
        guard let url, SubscriptionBrowser.isOfficial(url) else { return nil }
        return try? WorkshopID(url.absoluteString)
    }
    public func goHome() { load(Self.home) }
    public func goBack() {
        guard !isClosed, webView.canGoBack else { return }
        clearSelection(); webView.goBack()
    }
    public func goForward() {
        guard !isClosed, webView.canGoForward else { return }
        clearSelection(); webView.goForward()
    }
    public func reload() {
        guard !isClosed else { return }
        clearSelection(); webView.reload()
    }
    public func close() {
        isClosed = true
        clearSelection()
        isLoading = false
        urlObservation?.invalidate(); urlObservation = nil
        webView.stopLoading()
        webView.navigationDelegate = nil; webView.uiDelegate = nil
    }
    private func load(_ url: URL) {
        guard !isClosed else { return }
        clearSelection()
        webView.load(URLRequest(url: url, timeoutInterval: 45))
    }
    private func clearSelection() {
        generation = UUID()
        lookup?.cancel(); lookup = nil
        currentItem = nil; isChecking = false; errorMessage = nil
    }
    private func updateNavigation() {
        address = webView.url?.absoluteString ?? Self.home.absoluteString
        canGoBack = webView.canGoBack; canGoForward = webView.canGoForward
    }
    func inspectPage(at url: URL?) {
        guard !isClosed else { return }
        clearSelection(); pageURL = url
        if let url { address = url.absoluteString }
        guard let id = Self.pageID(from: url) else { return }
        let request = generation
        isChecking = true
        lookup = Task { [weak self] in
            guard let self else { return }
            do {
                let item = try await self.itemLoader(id)
                try Task.checkCancellation()
                guard request == self.generation, !self.isClosed else { return }
                guard item.id == id else { throw WallpaperError.message(L("workshop.browser.steamReturnedItemInformationThatDoesNotMatch")) }
                self.currentItem = item
            } catch is CancellationError { }
            catch {
                guard request == self.generation, !self.isClosed else { return }
                self.errorMessage = String(format: L("workshop.browser.couldNotReadItemInformation"), String(describing: error.localizedDescription))
            }
            if request == self.generation, !self.isClosed {
                self.isChecking = false; self.lookup = nil
            }
        }
    }
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !isClosed, let url = navigationAction.request.url, SubscriptionBrowser.isOfficial(url) else {
            if navigationAction.targetFrame?.isMainFrame ?? true {
                clearSelection(); errorMessage = L("workshop.browser.onlyOfficialSteamPagesCanBeBrowsed")
            }
            decisionHandler(.cancel); return
        }
        if navigationAction.targetFrame?.isMainFrame ?? true { clearSelection() }
        decisionHandler(.allow)
    }
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        clearSelection(); isLoading = true; updateNavigation()
    }
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { updateNavigation() }
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false; updateNavigation(); inspectPage(at: webView.url)
    }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { record(error) }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { record(error) }
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        clearSelection(); isLoading = false; errorMessage = L("workshop.browser.theSteamPageStoppedReloadIt")
    }
    private func record(_ error: Error) {
        guard !isClosed, (error as NSError).code != NSURLErrorCancelled else { return }
        clearSelection(); isLoading = false; updateNavigation()
        errorMessage = String(format: L("workshop.subscriptions.steamPageFailedToLoad"), String(describing: error.localizedDescription))
    }
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if !isClosed, let url = navigationAction.request.url, SubscriptionBrowser.isOfficial(url) { load(url) }
        return nil
    }
}
