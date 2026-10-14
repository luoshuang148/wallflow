import AppKit
import ServiceManagement

private struct PlayerLoginReply: Codable {
    var status: Int
    var bundleIdentifier: String
    var bundlePath: String
    var error: String?
}

/// Runs inside the player bundle so mainApp refers to the player, not management.
public enum PlayerLoginStartupCommand {
    @MainActor public static func performIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard let index = arguments.firstIndex(of: "--wallflow-login-startup") else { return false }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let service = SMAppService.mainApp
        var errorMessage: String?
        do {
            guard index + 1 < arguments.count else { throw commandError("缺少登录启动操作。") }
            switch arguments[index + 1] {
            case "status": break
            case "register":
                if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            case "unregister":
                if service.status == .enabled || service.status == .requiresApproval { try service.unregister() }
            default: throw commandError("未知登录启动操作。")
            }
        } catch { errorMessage = error.localizedDescription }
        let reply = PlayerLoginReply(status: service.status.rawValue, bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
                                     bundlePath: Bundle.main.bundleURL.path, error: errorMessage)
        if let data = try? JSONEncoder().encode(reply) { FileHandle.standardOutput.write(data) }
        return true
    }
}

private func commandError(_ message: String) -> NSError {
    NSError(domain: "WallFlowLogin", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

/// Queries/changes the player's own login registration without starting its AppKit host.
@MainActor final class PlayerLoginStartupService: LoginStartupService {
    private let playerURL: URL
    init(appURL: URL) { playerURL = appURL.appendingPathComponent("Contents/Library/LoginItems/WallFlowPlayer.app") }
    var status: SMAppService.Status {
        guard let value = try? execute("status") else { return .notFound }
        // A validated app with no BTM record can report notFound before first registration.
        return value == .notFound ? .notRegistered : value
    }
    func register() throws {
        let value = try execute("register")
        guard value == .enabled || value == .requiresApproval else { throw commandError("后台登录启动未注册成功，请重试。") }
    }
    func unregister() throws { _ = try execute("unregister") }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func execute(_ action: String) throws -> SMAppService.Status {
        let process = Process(), pipe = Pipe()
        process.executableURL = playerURL.appendingPathComponent("Contents/MacOS/WallFlowPlayer")
        process.arguments = ["--wallflow-login-startup", action]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        guard !process.isRunning else { process.terminate(); throw commandError("后台登录启动操作超时，请重试。") }
        guard process.terminationStatus == 0 else { throw commandError("后台登录启动操作未完成。") }
        let reply = try JSONDecoder().decode(PlayerLoginReply.self, from: pipe.fileHandleForReading.readDataToEndOfFile())
        guard reply.bundleIdentifier == "local.zongzihao.VideoWallpaper.Player", reply.bundlePath == playerURL.path else {
            throw commandError("后台登录启动程序身份不匹配，请使用完整的 WallFlow.app。")
        }
        if let error = reply.error { throw commandError(error) }
        switch reply.status {
        case SMAppService.Status.enabled.rawValue: return .enabled
        case SMAppService.Status.requiresApproval.rawValue: return .requiresApproval
        case SMAppService.Status.notRegistered.rawValue: return .notRegistered
        case SMAppService.Status.notFound.rawValue: return .notFound
        default: throw commandError("无法识别后台登录启动状态。")
        }
    }
}
