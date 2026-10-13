import AppKit
import SwiftUI
import Combine
import WallpaperRuntime

@main struct VideoWallpaperApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: LibraryModel!
    private var workshop: WorkshopModel!
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var cancellable: AnyCancellable?
    private var powerMonitor: PowerMonitor?
    private var startup = LoginStartupModel()
    private var applicationMonitor: ApplicationMonitor?
    private var playlistTimer: Timer?
    private var terminationStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoWallpaper", isDirectory: true)
        model = LibraryModel(storeURL: directory.appendingPathComponent("state.json"))
        workshop = WorkshopModel(library: model)
        powerMonitor = PowerMonitor { [weak self] onBattery, lowPowerMode in
            self?.model.updatePowerState(onBattery: onBattery, lowPowerMode: lowPowerMode)
        }
        powerMonitor?.start()
        setupMainMenu()
        setupStatusItem()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 690),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "WallFlow"
        window.minSize = NSSize(width: 900, height: 660)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LibraryView(model: model, workshop: workshop, startup:startup))
        window.center()
        setupLifecycle()
        applicationMonitor = ApplicationMonitor { [weak self] running, frontmost in
            self?.model.updateApplications(running:running,frontmost:frontmost)
        }
        applicationMonitor?.start()
        playlistTimer = Timer.scheduledTimer(withTimeInterval:15,repeats:true) { [weak self] _ in
            Task { @MainActor in await self?.model.tickPlaylist() }
        }
        playlistTimer?.tolerance = 2
        showLibrary()
        Task { await model.restore() }
    }
    private func setupMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quit = NSMenuItem(title: "退出 WallFlow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApplication.shared.mainMenu = menu
    }
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        let open = NSMenuItem(title: "管理壁纸…", action: #selector(showLibrary), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        pauseItem = NSMenuItem(title: "全部暂停", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 WallFlow", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        cancellable = model.$state.map(\.manuallyPaused).removeDuplicates().sink { [weak self] paused in
            let image = NSImage(systemSymbolName: paused ? "pause.rectangle" : "play.rectangle", accessibilityDescription: "WallFlow")
            image?.isTemplate = true
            self?.statusItem.button?.image = image
            self?.statusItem.button?.toolTip = paused ? "WallFlow · 已暂停" : "WallFlow"
        }
    }
    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.title = model.state.manuallyPaused ? "恢复播放" : "全部暂停"
        pauseItem.isEnabled = !model.state.projects.isEmpty
    }
    private func setupLifecycle() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.model.setSuspended("sleep", active: true) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.powerMonitor?.refresh(); $0.model.setSuspended("sleep", active: false); $0.model.refreshDisplays() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.model.setSuspended("displaySleep", active: true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.model.setSuspended("displaySleep", active: false) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.model.setSuspended("inactiveSession", active: true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.model.setSuspended("inactiveSession", active: false) }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.model.setSuspended("lock", active: true) }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { $0.model.setSuspended("lock", active: false) }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.model.refreshDisplays() }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor (AppDelegate) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if let self { action(self) } }
        }
        observers.append((center, token))
    }
    @objc private func showLibrary() {
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(nil) }
    }
    @objc private func togglePause() { model.togglePause() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showLibrary(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil else { return .terminateNow }
        guard !terminationStarted else { return .terminateLater }
        terminationStarted = true
        playlistTimer?.invalidate()
        applicationMonitor?.stop()
        powerMonitor?.stop()
        workshop?.shutdown()
        window?.orderOut(nil)
        let wallpapers = model.prepareForTermination()
        let keeper = StaticWallpaperKeeper(directory:model.storeURL.deletingLastPathComponent().appendingPathComponent("ExitWallpapers",isDirectory:true))
        Task { @MainActor in
            while !wallpapers.isEmpty {
                let errors = await keeper.preserve(wallpapers)
                if errors.isEmpty { break }
                let alert = NSAlert()
                alert.messageText = "无法保留部分屏幕的壁纸"
                alert.informativeText = errors.joined(separator:"\n")
                alert.addButton(withTitle:"重试")
                alert.addButton(withTitle:"仍然退出")
                sender.activate(ignoringOtherApps:true)
                if alert.runModal() != .alertFirstButtonReturn { break }
            }
            sender.reply(toApplicationShouldTerminate:true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        playlistTimer?.invalidate()
        applicationMonitor?.stop()
        workshop?.shutdown()
        model?.shutdown()
        model?.engine.stop()
        powerMonitor?.stop()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}
