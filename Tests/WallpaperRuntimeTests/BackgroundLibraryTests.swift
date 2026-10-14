import XCTest
import AppKit
@testable import WallpaperCore
@testable import WallpaperRuntime

@MainActor final class BackgroundLibraryTests: XCTestCase {
    private func fixture() throws -> (URL, WallpaperProject) {
        _ = NSApplication.shared
        guard NSScreen.main != nil else { throw XCTSkip("Requires display") }
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else { throw XCTSkip("Requires FFmpeg") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = ["-nostdin", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=320x180:d=3:r=10", "-c:v", "libx264", "-pix_fmt", "yuv420p", root.appendingPathComponent("video.mp4").path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        try Data(#"{"type":"video","file":"video.mp4"}"#.utf8).write(to: root.appendingPathComponent("project.json"))
        return (root, try WallpaperProject.load(folder: root))
    }
    func testManagementRestoreApplyAndShutdownNeverOwnDesktopSessions() async throws {
        let (root, project) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.json")
        var state = AppState(); state.projects = [project]; state.defaultAssignment = Assignment(projectID: project.id)
        state.isMuted = true; try StateStore.save(state, to: url)
        let manager = LibraryModel(storeURL: url, mode: .management)
        await manager.restore()
        XCTAssertNotNil(manager.mediaInfo[project.id])
        XCTAssertTrue(manager.engine.sessions.isEmpty)
        await manager.apply(projectID: project.id, target: nil, fit: .fit)
        XCTAssertEqual(try StateStore.load(from: url).defaultAssignment?.fit, .fit)
        manager.togglePause(); manager.setMuted(false); manager.refreshDisplays()
        XCTAssertTrue(manager.engine.sessions.isEmpty)
        XCTAssertTrue(manager.prepareForTermination().isEmpty)
    }
    func testManagementEditPreservesBackgroundChangesAndReloadsStatus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.json")
        let base = AppState(); try StateStore.save(base, to: url)
        let manager = LibraryModel(storeURL: url, mode: .management)
        var next = base; next.defaultAssignment = Assignment(projectID: "background")
        _ = try SharedStateStore.saveChanges(base: base, next: next, to: url)
        manager.setMuted(true)
        XCTAssertEqual(manager.state.defaultAssignment, next.defaultAssignment)
        XCTAssertTrue(manager.state.isMuted)
        manager.setExternalPlaybackStatus(["test": "播放中"])
        XCTAssertEqual(manager.playbackStatus(for: "test"), "播放中")
        XCTAssertTrue(manager.engine.sessions.isEmpty)
    }
    func testPlayerPolicyReloadReusesInstalledSession() async throws {
        let (root, project) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.json")
        var state = AppState(); state.projects = [project]; state.defaultAssignment = Assignment(projectID: project.id)
        state.performance.pauseWhenOccluded = false; state.isMuted = true
        try StateStore.save(state, to: url)
        let player = LibraryModel(storeURL: url, mode: .player)
        defer { player.engine.stop() }
        await player.restore()
        let session = try XCTUnwrap(player.engine.sessions.values.first)
        var next = state; next.manuallyPaused = true
        _ = try SharedStateStore.saveChanges(base: state, next: next, to: url)
        await player.reloadSharedState()
        XCTAssertTrue(player.engine.sessions.values.first === session)
        XCTAssertEqual(session.player.rate, 0)
        XCTAssertTrue(player.state.manuallyPaused)
    }
}
