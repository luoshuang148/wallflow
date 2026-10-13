import XCTest
import AppKit
import AVFoundation
@testable import WallpaperCore
@testable import WallpaperRuntime

final class RuntimeTests: XCTestCase {
    @MainActor func testRealDesktopPlaybackLoopsPausesAndReleasesDisconnectedDisplay() async throws {
        guard let folder = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else {
            throw XCTSkip("Set WALLPAPER_FOLDER to exercise desktop playback")
        }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let project = try WallpaperProject.load(folder: URL(fileURLWithPath: folder))
        _ = try await MediaValidator.validate(url: URL(fileURLWithPath: project.videoPath))
        let engine = WallpaperEngine()
        defer { engine.stop() }
        var state = AppState()
        state.isMuted = true
        state.projects = [project]
        state.applyToAll(Assignment(projectID: project.id), displays: ["sample-display"])
        let display = Display(id: "sample-display", name: "Test", screen: screen)
        engine.reconcile(state: state, displays: [display], shouldPlay: true)
        try await Task.sleep(for: .seconds(1))
        let session = try XCTUnwrap(engine.sessions["sample-display"], "Assigned display must have a wallpaper session")
        XCTAssertTrue(session.window.isVisible)
        XCTAssertTrue(session.window.ignoresMouseEvents)
        XCTAssertFalse(session.window.canBecomeKey)
        XCTAssertFalse(session.window.canBecomeMain)
        XCTAssertEqual(session.window.level.rawValue, Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        XCTAssertEqual(session.window.frame, screen.frame)
        XCTAssertTrue(session.window.collectionBehavior.contains(.canJoinAllSpaces))
        try await Task.sleep(for: .seconds(3))
        XCTAssertGreaterThan(session.player.currentTime().seconds, 0.5)
        XCTAssertTrue(session.player.isMuted)
        engine.setPlaying(false)
        let pausedAt = session.player.currentTime().seconds
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(session.player.currentTime().seconds, pausedAt, accuracy: 0.15)
        engine.setPlaying(true)
        try await Task.sleep(for: .seconds(18))
        XCTAssertGreaterThanOrEqual(session.looper?.loopCount ?? 0, 1)
        engine.reconcile(state: state, displays: [], shouldPlay: true)
        XCTAssertTrue(engine.sessions.isEmpty)
        XCTAssertFalse(session.window.isVisible)
        XCTAssertEqual(session.player.rate, 0)
        XCTAssertEqual(state.assignment(for: "sample-display")?.projectID, project.id)
    }
}
