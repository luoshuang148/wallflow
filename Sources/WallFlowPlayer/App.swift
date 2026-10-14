import AppKit
import Combine
import WallpaperRuntime

@main struct WallFlowPlayerApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = PlayerDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor private final class PlayerDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var lease: PlayerLease?
    private var host: DesktopPlaybackHost?
    private var statusItem: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var cancellable: AnyCancellable?
    private var terminationStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        var stateURL = BackgroundPlayerPaths.defaultStateURL
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--wallflow-state"), index + 1 < args.count { stateURL = URL(fileURLWithPath: args[index + 1]) }
        let paths = BackgroundPlayerPaths(stateURL: stateURL)
        do {
            guard let acquired = try PlayerLease.acquire(paths) else { NSApplication.shared.terminate(nil); return }
            lease = acquired
            var parent = Bundle.main.bundleURL
            for _ in 0..<4 { parent.deleteLastPathComponent() }
            let host = DesktopPlaybackHost(paths: paths, parentAppURL: parent,
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development", sessionID: acquired.sessionID)
            self.host = host
            host.onStopRequested = { NSApplication.shared.terminate(nil) }
            setupStatusItem(host)
            Task {
                do { try await host.start() }
                catch {
                    let alert = NSAlert(); alert.messageText = "后台播放器无法启动"; alert.informativeText = error.localizedDescription
                    alert.runModal()
                    NSApplication.shared.terminate(nil)
                }
            }
        } catch {
            let alert = NSAlert(); alert.messageText = "后台播放器无法启动"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApplication.shared.terminate(nil)
        }
    }
    private func setupStatusItem(_ host: DesktopPlaybackHost) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        let menu = NSMenu(); menu.delegate = self
        let open = NSMenuItem(title: "管理壁纸…", action: #selector(openManagement), keyEquivalent: ""); open.target = self
        menu.addItem(open); menu.addItem(.separator())
        let pause = NSMenuItem(title: "全部暂停", action: #selector(togglePause), keyEquivalent: ""); pause.target = self
        pauseItem = pause; menu.addItem(pause); menu.addItem(.separator())
        let quit = NSMenuItem(title: "停止壁纸并完全退出", action: #selector(quit), keyEquivalent: ""); quit.target = self
        menu.addItem(quit); item.menu = menu
        cancellable = host.model.$state.map(\.manuallyPaused).removeDuplicates().sink { [weak self] paused in
            let image = NSImage(systemSymbolName: paused ? "pause.rectangle" : "play.rectangle", accessibilityDescription: "WallFlow")
            image?.isTemplate = true
            self?.statusItem?.button?.image = image
            self?.statusItem?.button?.toolTip = paused ? "WallFlow · 已暂停" : "WallFlow · 后台播放"
        }
    }
    func menuWillOpen(_ menu: NSMenu) {
        pauseItem?.title = host?.model.state.manuallyPaused == true ? "恢复播放" : "全部暂停"
        pauseItem?.isEnabled = host?.phase == .ready && host?.model.state.projects.isEmpty == false
    }
    @objc private func openManagement() { host?.openManagement() }
    @objc private func togglePause() { host?.model.togglePause() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let host else { return .terminateNow }
        guard !terminationStarted else { return .terminateLater }
        terminationStarted = true
        let wallpapers = host.prepareForTermination()
        let keeper = StaticWallpaperKeeper(directory: host.paths.stateURL.deletingLastPathComponent().appendingPathComponent("ExitWallpapers", isDirectory: true))
        Task { @MainActor in
            while !wallpapers.isEmpty {
                let errors = await keeper.preserve(wallpapers)
                if errors.isEmpty { break }
                let alert = NSAlert()
                alert.messageText = "无法保留部分屏幕的壁纸"
                alert.informativeText = errors.joined(separator: "\n")
                alert.addButton(withTitle: "重试"); alert.addButton(withTitle: "仍然退出")
                sender.activate(ignoringOtherApps: true)
                if alert.runModal() != .alertFirstButtonReturn { break }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        host?.finish()
        lease?.release(); lease = nil
        if let host {
            DistributedNotificationCenter.default().postNotificationName(BackgroundPlayerPaths.stoppedNotification,
                object: host.paths.stateURL.path, userInfo: ["session": host.sessionID.uuidString], deliverImmediately: true)
        }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}
