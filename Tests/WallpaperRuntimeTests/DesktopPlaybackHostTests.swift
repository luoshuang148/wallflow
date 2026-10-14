import XCTest
import AppKit
import WallpaperCore
@testable import WallpaperRuntime

@MainActor final class DesktopPlaybackHostTests: XCTestCase {
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
