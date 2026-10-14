import XCTest
import AppKit
import WallpaperCore
@testable import WallpaperRuntime

@MainActor final class DesktopPlaybackHostTests: XCTestCase {
    func testPackagedPlayerStartupQueryExitsWithoutStartingPlayback() async throws {
        guard let appPath = ProcessInfo.processInfo.environment["WALLFLOW_PLAYER_APP"] else {
            throw XCTSkip("Set WALLFLOW_PLAYER_APP to test the packaged startup-control mode")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/MacOS/WallFlowPlayer")
        process.arguments = ["--wallflow-login-startup", "status", "--wallflow-state", root.appendingPathComponent("state.json").path]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(process.isRunning, "Startup-control mode must return without creating a playback host")
        guard !process.isRunning else { return }
        let reply = try XCTUnwrap((try? JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile())) as? [String: Any])
        XCTAssertEqual(reply["bundleIdentifier"] as? String, "local.zongzihao.VideoWallpaper.Player")
        XCTAssertEqual(reply["bundlePath"] as? String, appPath)
        XCTAssertNotNil(reply["status"] as? Int)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Runtime").path))
    }
    func testPackagedHelperActuallyExitsAfterCommandNotification() async throws {
        guard let appPath = ProcessInfo.processInfo.environment["WALLFLOW_PLAYER_APP"] else {
            throw XCTSkip("Set WALLFLOW_PLAYER_APP to a built helper bundle; uses an empty temporary library")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = BackgroundPlayerPaths(stateURL: root.appendingPathComponent("state.json"))
        try StateStore.save(AppState(), to: paths.stateURL)
        let original = try Data(contentsOf: paths.stateURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/MacOS/WallFlowPlayer")
        process.arguments = ["--wallflow-state", paths.stateURL.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let startupDeadline = Date().addingTimeInterval(10)
        var ready: PlayerStatus?
        while Date() < startupDeadline {
            if let status = try paths.readStatus(), status.phase == .ready { ready = status; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let status = try XCTUnwrap(ready)
        XCTAssertEqual(status.pid, process.processIdentifier)
        try paths.requestStop(session: status.sessionID)
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(process.isRunning, "AppKit terminateLater must finish in the packaged process")
        XCTAssertFalse(try paths.hasOwner())
        XCTAssertEqual(try paths.readStatus()?.phase, .stopped)
        XCTAssertEqual(try Data(contentsOf: paths.stateURL), original)
    }
    func testStopNotificationInvokesAppKitTerminationOutsideSwiftTask() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = BackgroundPlayerPaths(stateURL: root.appendingPathComponent("state.json"))
        try StateStore.save(AppState(), to: paths.stateURL)
        let lease = try XCTUnwrap(PlayerLease.acquire(paths)); defer { lease.release() }
        let host = DesktopPlaybackHost(paths: paths, parentAppURL: URL(fileURLWithPath: "/tmp/WallFlow.app"), build: "test", sessionID: lease.sessionID)
        defer { host.finish() }
        var called = false, insideSwiftTask = true
        host.onStopRequested = {
            called = true
            insideSwiftTask = withUnsafeCurrentTask { $0 != nil }
        }
        try await host.start()
        try paths.requestStop(session: host.sessionID)
        let deadline = Date().addingTimeInterval(2)
        while !called && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(called)
        XCTAssertFalse(insideSwiftTask, "AppKit terminateLater runs a nested loop and must not retain an active MainActor task")
    }
}
