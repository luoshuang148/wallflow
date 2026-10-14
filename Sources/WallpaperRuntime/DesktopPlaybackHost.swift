import AppKit
import AVFoundation
import WallpaperCore

/// Lives exclusively in WallFlowPlayer. The management process never owns this host.
@MainActor public final class DesktopPlaybackHost {
    public let model: LibraryModel
    public let paths: BackgroundPlayerPaths
    public let sessionID: UUID
    public private(set) var phase: PlayerPhase = .starting
    private let parentAppURL: URL
    private let build: String
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerMonitor: PowerMonitor?
    private var applicationMonitor: ApplicationMonitor?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var needsRefresh = false
    private var lastPlaylistTick = Date.distantPast
    private var stopScheduled = false
    public var onStopRequested: (() -> Void)?

    public init(paths: BackgroundPlayerPaths, parentAppURL: URL, build: String, sessionID: UUID) {
        self.sessionID = sessionID
        self.paths = paths; self.parentAppURL = parentAppURL; self.build = build
        model = LibraryModel(storeURL: paths.stateURL, mode: .player)
    }
    public func start() async throws {
        try publishStatus()
        powerMonitor = PowerMonitor { [weak self] battery, lowPower in self?.model.updatePowerState(onBattery: battery, lowPowerMode: lowPower) }
        powerMonitor?.start()
        applicationMonitor = ApplicationMonitor { [weak self] running, frontmost in self?.model.updateApplications(running: running, frontmost: frontmost) }
        applicationMonitor?.start()
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
        observe(DistributedNotificationCenter.default(), Notification.Name(SharedStateStore.notification), object: paths.stateURL.path) { $0.requestRefresh() }
        observe(DistributedNotificationCenter.default(), BackgroundPlayerPaths.commandNotification, object: paths.stateURL.path) { $0.checkStopRequest() }
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeat() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        await model.restore()
        guard phase == .starting else { return }
        phase = .ready
        try publishStatus()
        checkStopRequest()
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: String? = nil, action: @escaping @MainActor (DesktopPlaybackHost) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .starting || self.phase == .ready else { return }
                action(self)
            }
        }))
    }
    private func requestRefresh() {
        guard phase == .starting || phase == .ready else { return }
        needsRefresh = true
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            while self.needsRefresh && !Task.isCancelled {
                self.needsRefresh = false
                await self.model.reloadSharedState()
            }
            if self.phase == .ready && Date().timeIntervalSince(self.lastPlaylistTick) >= 15 {
                self.lastPlaylistTick = Date()
                await self.model.tickPlaylist()
            }
            try? self.publishStatus()
        }
    }
    private func heartbeat() {
        if phase == .starting || phase == .ready { checkStopRequest(); requestRefresh() }
        do { try publishStatus() } catch { model.errorMessage = error.localizedDescription }
    }
    private func checkStopRequest() {
        guard phase == .starting || phase == .ready else { return }
        do {
            if !stopScheduled, try paths.stopRequested(session: sessionID) {
                stopScheduled = true
                // AppKit's terminateLater nested loop must run outside a main-dispatch
                // callback, otherwise that occupied queue cannot resume the frame-export task.
                RunLoop.main.perform(inModes: [.default]) { [weak self] in self?.onStopRequested?() }
            }
        }
        catch { model.errorMessage = "无法读取退出请求：\(error.localizedDescription)" }
    }
    public func publishStatus() throws {
        var displays: [String: PlayerDisplayStatus] = [:]
        for display in model.displays {
            let session = model.engine.sessions[display.id]
            let seconds = session?.player.currentTime().seconds ?? 0
            displays[display.id] = PlayerDisplayStatus(message: model.playbackStatus(for: display.id),
                projectID: session?.projectID ?? "", seconds: seconds.isFinite ? seconds : 0,
                rate: session?.player.rate ?? 0, muted: session?.player.isMuted ?? true)
        }
        try paths.writeStatus(PlayerStatus(sessionID: sessionID, pid: getpid(), build: build,
            parentAppPath: parentAppURL.path, phase: phase, displays: displays, error: model.errorMessage))
    }
    public func prepareForTermination() -> [ExitWallpaper] {
        phase = .stopping
        powerMonitor?.stop(); applicationMonitor?.stop()
        refreshTask?.cancel(); needsRefresh = false
        let wallpapers = model.prepareForTermination()
        try? publishStatus()
        DistributedNotificationCenter.default().postNotificationName(BackgroundPlayerPaths.stoppingNotification,
            object: paths.stateURL.path, userInfo: ["session": sessionID.uuidString], deliverImmediately: true)
        return wallpapers
    }
    public func finish() {
        phase = .stopped
        timer?.invalidate(); timer = nil
        powerMonitor?.stop(); applicationMonitor?.stop(); refreshTask?.cancel()
        model.shutdown(); model.engine.stop()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        try? publishStatus()
    }
    public func openManagement() {
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        Task {
            do { _ = try await NSWorkspace.shared.openApplication(at: parentAppURL, configuration: config) }
            catch { model.errorMessage = "无法打开管理程序：\(error.localizedDescription)" }
        }
    }
}
