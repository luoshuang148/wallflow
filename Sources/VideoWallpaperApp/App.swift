import AppKit
import SwiftUI
import WallpaperCore
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

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: LibraryModel!
    private var workshop: WorkshopModel!
    private var player: BackgroundPlayerController!
    private var exit: ManagementExitCoordinator!
    private var window: NSWindow!
    private var startup = LoginStartupModel()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var connectedSession: UUID?
    private var lastPlayerError: String?
    private var terminationStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let url = BackgroundPlayerPaths.defaultStateURL
        model = LibraryModel(storeURL: url, mode: .management)
        workshop = WorkshopModel(library: model)
        player = BackgroundPlayerController(stateURL: url)
        exit = ManagementExitCoordinator(quiesce: { [weak self] in self?.quiesce() }, stop: { [weak self] expectedSession in
            guard let self else { throw CancellationError() }
            // A complete exit requested during launch must also stop the helper being launched.
            if expectedSession == nil { await self.startupTask?.value }
            else { self.startupTask?.cancel() }
            try await self.player.stopAndWait(expectedSession: expectedSession)
        }, recover: { [weak self] in self?.model.resumeManagementAfterFailedExit() }, terminate: { [weak self] in
            self?.quit()
        })
        setupMainMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 690),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "WallFlow"
        window.minSize = NSSize(width: 900, height: 660)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LibraryView(model: model, workshop: workshop, startup: startup, exit: exit))
        window.center()
        setupLifecycle()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.requestRefresh() } }
        RunLoop.main.add(timer!, forMode: .common)
        showLibrary()
        Task { await model.restore() }
        startupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.player.ensureRunning()
                self.connectedSession = self.player.status?.sessionID
                self.requestRefresh()
            } catch is CancellationError { }
            catch { self.model.errorMessage = error.localizedDescription }
        }
    }
    private func setupMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(), appMenu = NSMenu()
        let quit = NSMenuItem(title: "退出管理程序（壁纸继续播放）", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; appMenu.addItem(quit); appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""), edit = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = edit; menu.addItem(editItem)
        NSApplication.shared.mainMenu = menu
    }
    private func setupLifecycle() {
        // The management model uses these flags only for its silent preview.
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.model.setSuspended("sleep", active: true) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.model.setSuspended("sleep", active: false); $0.model.refreshDisplays() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.model.setSuspended("displaySleep", active: true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.model.setSuspended("displaySleep", active: false) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.model.setSuspended("inactiveSession", active: true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.model.setSuspended("inactiveSession", active: false) }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.model.setSuspended("lock", active: true) }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { $0.model.setSuspended("lock", active: false) }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.model.refreshDisplays() }
        observe(DistributedNotificationCenter.default(), Notification.Name(SharedStateStore.notification), object: model.storeURL.path) { $0.requestRefresh() }
        observePlayerExit(BackgroundPlayerPaths.stoppingNotification) { $0.quiesce() }
        let center = DistributedNotificationCenter.default()
        let stopped = center.addObserver(forName: BackgroundPlayerPaths.stoppedNotification, object: model.storeURL.path, queue: .main) { [weak self] notification in
            let session = (notification.userInfo?["session"] as? String).flatMap(UUID.init(uuidString:))
            Task { @MainActor in
                guard let self, let session else { return }
                await self.exit.playerStopped(session: session, connectedSession: self.connectedSession)
            }
        }
        observers.append((center, stopped))
    }
    private func observePlayerExit(_ name: Notification.Name, action: @escaping @MainActor (AppDelegate) -> Void) {
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(forName: name, object: model.storeURL.path, queue: .main) { [weak self] notification in
            let session = notification.userInfo?["session"] as? String
            Task { @MainActor in
                guard let self, let session, session == self.connectedSession?.uuidString else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: String? = nil, action: @escaping @MainActor (AppDelegate) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            Task { @MainActor in if let self, !self.terminationStarted { action(self) } }
        }))
    }
    private func requestRefresh() {
        guard !terminationStarted, refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            await self.model.reloadSharedState()
            do {
                try self.player.refreshStatus()
                if let status = self.player.status {
                    self.connectedSession = status.sessionID
                    self.model.setExternalPlaybackStatus(status.displays.mapValues(\.message))
                    if let error = status.error, error != self.lastPlayerError { self.model.errorMessage = error }
                    self.lastPlayerError = status.error
                } else {
                    self.model.setExternalPlaybackStatus([:])
                }
            } catch { self.model.errorMessage = error.localizedDescription }
        }
    }
    private func quiesce() { workshop?.shutdown(); model?.shutdown() }
    @objc private func showLibrary() {
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(nil) }
    }
    @objc private func quit() {
        if let window { ManagementWindowPolicy.allowQuitWithPresentedSheet(in: window) }
        NSApplication.shared.terminate(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showLibrary(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationStarted = true
        quiesce()
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); refreshTask?.cancel(); startupTask?.cancel()
        quiesce()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}
