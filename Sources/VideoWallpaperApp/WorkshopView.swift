import SwiftUI
import AppKit
import WebKit
import WallpaperCore
import WallpaperRuntime

struct WorkshopView: View {
    @ObservedObject var model: WorkshopModel
    @ObservedObject var library: LibraryModel
    let onImportFolder: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsSubscriptions = false
    @State private var showsBrowser = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("创意工坊").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button(action:onImportFolder) { Label("导入壁纸文件夹",systemImage:"folder.badge.plus") }
                            .controlSize(.large).disabled(model.isBusy || library.isBusy)
                        Spacer()
                    }
                    GroupBox("下载账号") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Steam 登录账号名", text: $model.account).textFieldStyle(.roundedBorder)
                                    .onSubmit { model.savePreferences() }
                                if !model.accounts.isEmpty {
                                    Menu("已登录账号") {
                                        ForEach(model.accounts, id: \.self) { name in Button(name) { model.account = name; model.savePreferences() } }
                                    }.frame(width: 120)
                                }
                                Button("登录下载账号") { model.loginInTerminal() }
                                    .help("账号须拥有 Wallpaper Engine；在终端完成 Steam 登录与 Steam Guard 验证。")
                            }.disabled(model.isBusy || library.isBusy)
                            HStack {
                                Image(systemName: model.tool == nil ? "exclamationmark.triangle" : "checkmark.circle").foregroundStyle(model.tool == nil ? .orange : .secondary)
                                Text(model.tool == nil ? "尚未找到 SteamCMD" : "SteamCMD 已就绪").font(.caption)
                                Spacer()
                                Button("选择工具…", action: chooseTool).controlSize(.small).disabled(model.isBusy || library.isBusy)
                            }
                        }.padding(8)
                    }
                    GroupBox("通过链接下载") {
                        HStack {
                            TextField("粘贴 Steam 创意工坊链接或数字编号", text: $model.input).textFieldStyle(.roundedBorder)
                                .onSubmit { model.downloadInput() }
                            Button("下载并导入") { model.downloadInput() }.disabled(model.isBusy || library.isBusy || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.padding(8)
                    }
                    HStack {
                        Button { showsBrowser = true } label: { Label("浏览工坊…", systemImage: "globe") }
                        Button { showsSubscriptions = true } label: { Label("读取 Steam 订阅…", systemImage: "person.crop.circle.badge.checkmark") }
                        Button("导入本机已下载") { model.scanLocal() }
                        Menu("其他来源") {
                            Button("选择 Steam 视频目录…", action: chooseLocal)
                            Button("读取 Windows 已下载清单…", action: chooseManifest)
                        }.frame(width: 120)
                        Spacer()
                    }.disabled(model.isBusy || library.isBusy)
                    if !model.candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("视频壁纸 · \(model.candidates.count)").font(.headline)
                                Spacer()
                                Button("全选未导入") { model.selected = Set(model.candidates.filter { !model.alreadyImported($0.id) }.map(\.id)) }
                                Button("取消全选") { model.selected = [] }
                            }.disabled(model.isBusy || library.isBusy)
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(model.candidates) { item in
                                        HStack {
                                            Toggle(isOn: Binding(get: { model.selected.contains(item.id) }, set: { if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) } })) {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(item.title).lineLimit(2)
                                                    Text("\(item.id.rawValue) · \(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                                                }
                                            }.toggleStyle(.checkbox).disabled(model.isBusy || library.isBusy || model.alreadyImported(item.id))
                                            Spacer()
                                            if model.alreadyImported(item.id) { Text("已导入").font(.caption).foregroundStyle(.secondary) }
                                            Link("详情", destination: item.id.url).font(.caption)
                                        }
                                    }
                                }.padding(12)
                            }.frame(height: 200).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            HStack {
                                Text("已选 \(model.selected.count) 个 · 约 \(ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))").font(.callout).foregroundStyle(.secondary)
                                Spacer()
                                Button("下载所选视频") { model.downloadSelected() }.buttonStyle(.borderedProminent).disabled(model.isBusy || library.isBusy || model.selected.isEmpty)
                            }
                        }
                    }
                    if let error = model.errorMessage ?? library.errorMessage { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                    if !model.failures.isEmpty {
                        DisclosureGroup("\(model.failures.count) 项未完成，展开查看原因") {
                            VStack(alignment: .leading, spacing: 8) { ForEach(Array(model.failures.enumerated()), id: \.offset) { _, failure in Text(failure).font(.caption).textSelection(.enabled) } }.padding(.top, 8)
                        }
                    }
                }
            }
            Divider()
            HStack {
                if model.isBusy || library.isBusy { ProgressView().controlSize(.small) }
                Text(library.importStatus ?? (library.isBusy ? "正在导入…" : model.status)).font(.callout).lineLimit(3).textSelection(.enabled)
                Spacer()
                if model.isBusy { Button("取消任务") { model.cancel() } }
            }
            if model.isBusy && model.total > 0 { ProgressView(value: Double(model.completed), total: Double(model.total)) }
        }.padding(24).frame(width: 780, height: 660).onAppear { model.refreshAccounts() }
        .sheet(isPresented: $showsSubscriptions) {
            SubscriptionView { ids in model.loadSubscriptions(ids); showsSubscriptions = false }
        }
        .sheet(isPresented: $showsBrowser) { WorkshopBrowserView(model: model, library: library) }
    }
    private func chooseTool() {
        let panel = NSOpenPanel(); panel.title = "选择 SteamCMD 可执行文件 steamcmd"; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.chooseTool(url) }
    }
    private func chooseLocal() {
        let panel = NSOpenPanel(); panel.title = "选择 content/431960 目录（内含数字壁纸文件夹）"; panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { model.scanLocal(url) }
    }
    private func chooseManifest() {
        let panel = NSOpenPanel(); panel.title = "选择 Windows 的 appworkshop_431960.acf"; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { model.loadManifest(url) }
    }
}

private struct SubscriptionWebView: NSViewRepresentable {
    let browser: SubscriptionBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
private struct SubscriptionView: View {
    @StateObject private var browser = SubscriptionBrowser()
    @Environment(\.dismiss) private var dismiss
    let onRead: ([WorkshopID]) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Steam 账号订阅").font(.title2.bold())
                Spacer()
                Button(browser.isReading ? "取消读取" : "关闭") { browser.cancel(); dismiss() }
            }
            Text("Steam 网页与下载账号需分别登录。").font(.callout).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text(browser.address).font(.caption).lineLimit(1).textSelection(.enabled)
            }
            SubscriptionWebView(browser: browser).frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = browser.errorMessage { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                if browser.isReading { ProgressView().controlSize(.small) }
                Text(browser.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("回到我的订阅") { browser.goHome() }.disabled(browser.isReading)
                Button("读取全部订阅") { browser.readAll(completion: onRead) }.buttonStyle(.borderedProminent).disabled(browser.isReading)
            }
        }.padding(20).frame(width: 880, height: 700).onDisappear { browser.cancel() }
    }
}
