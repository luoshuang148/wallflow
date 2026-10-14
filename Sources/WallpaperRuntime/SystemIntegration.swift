import AppKit
import Combine
import ServiceManagement

/// The ServiceManagement boundary is injectable so tests never alter login items.
@MainActor protocol LoginStartupService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
    func migrateLegacyRegistration() throws -> LoginStartupMigration
}
enum LoginStartupMigration { case unchanged, enabled, disabled }
extension LoginStartupService { func migrateLegacyRegistration() throws -> LoginStartupMigration { .unchanged } }

@MainActor final class MigratingLoginStartupService: LoginStartupService {
    private let player: LoginStartupService
    private let legacy: LoginStartupService
    init(player: LoginStartupService, legacy: LoginStartupService) { self.player = player; self.legacy = legacy }
    var status: SMAppService.Status {
        let current = player.status
        if current == .enabled || current == .requiresApproval { return current }
        if legacy.status == .enabled || legacy.status == .requiresApproval { return legacy.status }
        return current
    }
    func register() throws { try player.register() }
    func unregister() throws {
        var errors: [String] = []
        for item in [legacy, player] where item.status == .enabled || item.status == .requiresApproval {
            do { try item.unregister() } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { throw NSError(domain: "WallFlowLogin", code: 1, userInfo: [NSLocalizedDescriptionKey: errors.joined(separator: "\n")]) }
    }
    func openSettings() { player.openSettings() }
    func migrateLegacyRegistration() throws -> LoginStartupMigration {
        if legacy.status == .requiresApproval && player.status != .enabled && player.status != .requiresApproval {
            // This status can mean revoked consent. Remove the inactive legacy item
            // while preserving off, rather than enabling a fresh identity automatically.
            try legacy.unregister()
            return .disabled
        }
        guard legacy.status == .enabled || legacy.status == .requiresApproval else { return .unchanged }
        if player.status != .enabled && player.status != .requiresApproval { try player.register() }
        guard player.status == .enabled || player.status == .requiresApproval else {
            throw NSError(domain: "WallFlowLogin", code: 1, userInfo: [NSLocalizedDescriptionKey: "后台播放器登录启动尚未注册。"])
        }
        try legacy.unregister()
        return .enabled
    }
}

@MainActor private final class NativeLoginStartupService: LoginStartupService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// The default is applied once; current enabled/approval state always comes from macOS.
@MainActor public final class LoginStartupModel: ObservableObject {
    @Published public private(set) var enabled = false
    @Published public private(set) var needsApproval = false
    @Published public var errorMessage: String?
    private let service: LoginStartupService
    private let preferences: UserDefaults
    private let configuredKey = "backgroundLoginStartupConfigured"
    private let optedOutKey = "backgroundLoginStartupOptedOut"
    private let pendingDisableKey = "backgroundLoginStartupPendingDisable"

    public convenience init() {
        self.init(service: MigratingLoginStartupService(player: PlayerLoginStartupService(appURL: Bundle.main.bundleURL), legacy: NativeLoginStartupService()))
    }

    init(service: LoginStartupService, preferences: UserDefaults = .standard) {
        self.service = service
        self.preferences = preferences
        refresh()
    }

    public func refresh() {
        errorMessage = nil
        updateStatus()
    }
    public func configureDefaultIfNeeded() {
        errorMessage = nil
        do {
            if preferences.bool(forKey: optedOutKey) {
                if preferences.bool(forKey: pendingDisableKey) {
                    if service.status == .enabled || service.status == .requiresApproval { try service.unregister() }
                    preferences.set(false, forKey: pendingDisableKey)
                }
                updateStatus()
                return
            }
            if try service.migrateLegacyRegistration() == .disabled {
                preferences.set(true, forKey: configuredKey)
                preferences.set(true, forKey: optedOutKey)
            }
        }
        catch { errorMessage = "无法迁移后台登录启动：\(error.localizedDescription)"; updateStatus(); return }
        updateStatus()
        guard !preferences.bool(forKey: configuredKey) else { return }
        changeEnabled(true)
        if errorMessage == nil && (enabled || needsApproval) { preferences.set(true, forKey: configuredKey) }
    }

    public func setEnabled(_ enabled: Bool) {
        preferences.set(true, forKey: configuredKey)
        preferences.set(!enabled, forKey: optedOutKey)
        preferences.set(false, forKey: pendingDisableKey)
        changeEnabled(enabled)
        if !enabled && errorMessage != nil { preferences.set(true, forKey: pendingDisableKey) }
    }

    private func changeEnabled(_ enabled: Bool) {
        errorMessage = nil
        let status = service.status
        do {
            if enabled {
                // Pending approval is already registered; the user must approve it in Settings.
                if status != .enabled && status != .requiresApproval { try service.register() }
            } else if status == .enabled || status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            errorMessage = "无法更改登录启动：\(error.localizedDescription)"
        }
        updateStatus()
    }

    public func openSettings() { service.openSettings() }

    private func updateStatus() {
        let status = service.status
        enabled = status == .enabled
        needsApproval = status == .requiresApproval
        if status == .notFound && errorMessage == nil {
            errorMessage = "系统未找到此应用的登录启动项。请将应用放入“应用程序”文件夹后重试。"
        }
    }
}

/// Emits application bundle identifiers when the workspace's application state changes.
@MainActor public final class ApplicationMonitor {
    private let notificationCenter: NotificationCenter
    private let runningBundleIDs: () -> Set<String>
    private let frontmostBundleID: () -> String?
    private let onChange: (Set<String>, String?) -> Void
    private var observers: [NSObjectProtocol] = []
    private var lastRunning: Set<String>?
    private var lastFrontmost: String?
    private var isRunning = false

    public convenience init(onChange: @escaping (Set<String>, String?) -> Void) {
        let workspace = NSWorkspace.shared
        self.init(
            notificationCenter: workspace.notificationCenter,
            runningBundleIDs: { Set(workspace.runningApplications.compactMap(\.bundleIdentifier)) },
            frontmostBundleID: { workspace.frontmostApplication?.bundleIdentifier },
            onChange: onChange
        )
    }

    init(notificationCenter: NotificationCenter,
         runningBundleIDs: @escaping () -> Set<String>,
         frontmostBundleID: @escaping () -> String?,
         onChange: @escaping (Set<String>, String?) -> Void) {
        self.notificationCenter = notificationCenter
        self.runningBundleIDs = runningBundleIDs
        self.frontmostBundleID = frontmostBundleID
        self.onChange = onChange
    }

    public func start() {
        stop()
        isRunning = true
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    self.refresh()
                }
            })
        }
        refresh()
    }

    public func refresh() {
        let running = runningBundleIDs()
        let frontmost = frontmostBundleID()
        guard running != lastRunning || frontmost != lastFrontmost else { return }
        lastRunning = running
        lastFrontmost = frontmost
        onChange(running, frontmost)
    }

    public func stop() {
        isRunning = false
        for observer in observers { notificationCenter.removeObserver(observer) }
        observers.removeAll()
        lastRunning = nil
        lastFrontmost = nil
    }

    deinit {
        for observer in observers { notificationCenter.removeObserver(observer) }
    }
}
