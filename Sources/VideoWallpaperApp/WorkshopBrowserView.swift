import SwiftUI
import WebKit
import WallpaperRuntime

private struct WorkshopWebSurface: NSViewRepresentable {
    let browser: WorkshopBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct WorkshopBrowserView: View {
    @ObservedObject var model: WorkshopModel
    @ObservedObject var library: LibraryModel
    @StateObject private var browser = WorkshopBrowser()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("浏览创意工坊").font(.title2.bold())
                Spacer()
                Button("关闭") { browser.close(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 10) {
                Button(action: browser.goBack) { Image(systemName: "chevron.left") }
                    .help("后退").accessibilityLabel("后退").disabled(!browser.canGoBack)
                Button(action: browser.goForward) { Image(systemName: "chevron.right") }
                    .help("前进").accessibilityLabel("前进").disabled(!browser.canGoForward)
                Button(action: browser.reload) { Image(systemName: "arrow.clockwise") }
                    .help("重新加载").accessibilityLabel("重新加载")
                Button("工坊首页", action: browser.goHome)
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text(browser.address).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                Spacer(minLength: 0)
                if browser.isLoading { ProgressView().controlSize(.small) }
            }
            WorkshopWebSurface(browser: browser).frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = browser.errorMessage ?? model.errorMessage ?? library.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled).lineLimit(3)
            }
            if !model.failures.isEmpty {
                DisclosureGroup("\(model.failures.count) 项未完成，展开查看原因") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(model.failures.enumerated()), id: \.offset) { _, failure in
                                Text(failure).font(.caption).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }.frame(maxHeight: 100)
                }
            }
            HStack {
                if browser.isChecking { ProgressView().controlSize(.small); Text("正在检查作品…").font(.callout) }
                else if let item = browser.currentItem {
                    Text(item.title).font(.callout).lineLimit(1)
                    if !item.isVideo { Text("仅支持视频壁纸").font(.caption).foregroundStyle(.secondary) }
                } else { Text("选择作品后可下载视频壁纸").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button("下载此作品") {
                    if let item = browser.currentItem, item.isVideo { model.downloadItem(item.id) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(browser.isLoading || browser.isChecking || browser.currentItem?.isVideo != true || model.isBusy || library.isBusy)
            }
            HStack {
                if model.isBusy || library.isBusy { ProgressView().controlSize(.small) }
                Text(library.importStatus ?? model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                Spacer()
                if model.isBusy { Button("取消任务") { model.cancel() } }
            }
            if model.isBusy, model.total > 0 { ProgressView(value: Double(model.completed), total: Double(model.total)) }
        }
        .padding(20).frame(width: 1000, height: 720)
        .onDisappear { browser.close() }
    }
}
