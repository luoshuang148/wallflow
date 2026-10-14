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
    func testHelperMenuEditCannotAbsorbExternalStopRuleWithoutApplyingIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.json"), base = AppState()
        try StateStore.save(base, to: url)
        let player = LibraryModel(storeURL: url, mode: .player)
        player.updateApplications(running: ["test.stop"], frontmost: "test.stop")
        var newer = base
        newer.applicationRules = [ApplicationRule(bundleID: "test.stop", name: "Test", action: .stop)]
        _ = try SharedStateStore.saveChanges(base: base, next: newer, to: url)
        player.togglePause(); player.togglePause()
        await player.reloadSharedState()
        XCTAssertTrue(player.applicationEffects.stopped)
    }
    func testMergedExternalAssignmentStillUpdatesInstalledFitOnReload() async throws {
        let (root, project) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.json")
        var base = AppState(); base.projects = [project]; base.defaultAssignment = Assignment(projectID: project.id)
        base.performance.pauseWhenOccluded = false; base.isMuted = true
        try StateStore.save(base, to: url)
        let player = LibraryModel(storeURL: url, mode: .player); defer { player.engine.stop() }
        await player.restore()
        var newer = base; newer.defaultAssignment?.fit = .fit
        _ = try SharedStateStore.saveChanges(base: base, next: newer, to: url)
        player.togglePause()
        await player.reloadSharedState()
        XCTAssertEqual(player.engine.sessions.values.first?.fit, .fit)
        XCTAssertEqual(player.engine.sessions.values.first?.player.rate, 0)
    }
    func testManagementAssignmentRefreshDoesNotCancelUnrelatedImport() async throws {
        let (root, project) = try fixture(), (importRoot, importedProject) = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: importRoot) }
        let url = root.appendingPathComponent("state.json")
        var base = AppState(); base.projects = [project]; base.defaultAssignment = Assignment(projectID: project.id)
        try StateStore.save(base, to: url)
        let manager = LibraryModel(storeURL: url, mode: .management)
        await manager.restore()
        let importing = Task { await manager.importFolder(importRoot) }
        while !manager.isBusy { await Task.yield() }
        var newer = base; newer.defaultAssignment?.fit = .fit
        _ = try SharedStateStore.saveChanges(base: base, next: newer, to: url)
        await manager.reloadSharedState()
        let result = await importing.value
        XCTAssertEqual(result, importedProject.id)
        XCTAssertEqual(manager.state.projects.count, 2)
        XCTAssertEqual(manager.state.defaultAssignment?.fit, .fit)
    }
    func testPlayerRestorationDoesNotOpenUnusedLibraryFolders() async throws {
        let (root, assigned) = try fixture(), (unusedRoot, unused) = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: unusedRoot) }
        let url = root.appendingPathComponent("state.json")
        var base = AppState(); base.projects = [assigned, unused]; base.defaultAssignment = Assignment(projectID: assigned.id)
        base.isMuted = true; base.performance.pauseWhenOccluded = false
        try StateStore.save(base, to: url)
        try FileManager.default.removeItem(at: unusedRoot.appendingPathComponent("project.json"))
        let player = LibraryModel(storeURL: url, mode: .player); defer { player.engine.stop() }
        await player.restore()
        XCTAssertNil(player.errorMessage, "Unused/offline/protected folders belong to management, not playback startup")
        XCTAssertNotNil(player.mediaInfo[assigned.id])
        XCTAssertNil(player.mediaInfo[unused.id])
        XCTAssertEqual(player.engine.sessions.values.first?.projectID, assigned.id)
    }
    func testPlayerPlaylistValidatesUnassignedVideoWhenItsTurnArrives() async throws {
        let (root, first) = try fixture(), (secondRoot, second) = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: secondRoot) }
        let url = root.appendingPathComponent("state.json")
        var base = AppState(); base.projects = [first, second]; base.defaultAssignment = Assignment(projectID: first.id)
        base.isMuted = true; base.performance.pauseWhenOccluded = false
        base.playlist.enabled = true; base.playlist.intervalMinutes = 1; base.playlist.projectIDs = [first.id, second.id]
        try StateStore.save(base, to: url)
        let player = LibraryModel(storeURL: url, mode: .player); defer { player.engine.stop() }
        await player.restore()
        XCTAssertNil(player.mediaInfo[second.id])
        let now = Date()
        await player.tickPlaylist(now: now)
        await player.tickPlaylist(now: now.addingTimeInterval(61))
        XCTAssertEqual(player.state.defaultAssignment?.projectID, second.id)
        XCTAssertNotNil(player.mediaInfo[second.id])
        XCTAssertEqual(player.engine.sessions.values.first?.projectID, second.id)
    }
}
