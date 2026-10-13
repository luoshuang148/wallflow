import XCTest
import AppKit
@testable import WallpaperCore
@testable import WallpaperRuntime

final class RecoveryTests: XCTestCase {
    @MainActor func testFailedReplacementRetainsWorkingSessionAndCanBeRetried() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let good = try WallpaperProject.load(folder: URL(fileURLWithPath: path))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{\"type\":\"video\",\"file\":\"video.mp4\"}".utf8).write(to: root.appendingPathComponent("project.json"))
        let file = root.appendingPathComponent("video.mp4")
        try Data("broken MP4".utf8).write(to: file)
        let broken = try WallpaperProject.load(folder: root)
        var state = AppState()
        state.projects = [good, broken]
        state.assignments["test"] = Assignment(projectID: good.id)
        let display = Display(id: "test", name: "test", screen: screen)
        let engine = WallpaperEngine()
        defer { engine.stop() }
        engine.reconcile(state: state, displays: [display], shouldPlay: true)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(engine.sessions["test"]?.projectID, good.id)
        state.assignments["test"] = Assignment(projectID: broken.id)
        engine.reconcile(state: state, displays: [display], shouldPlay: true)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(engine.sessions["test"]?.projectID, good.id, "Failed pending player must not replace current session")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: good.videoPath), to: file)
        engine.reconcile(state: state, displays: [display], shouldPlay: true)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(engine.sessions["test"]?.projectID, broken.id, "Retry must create a fresh player after file is fixed")
    }
    @MainActor func testReconnectionRejectsVideoReplacedWithOutsideSymlink() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let good = try WallpaperProject.load(folder: URL(fileURLWithPath: path))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{\"type\":\"video\",\"file\":\"video.mp4\"}".utf8).write(to: root.appendingPathComponent("project.json"))
        let file = root.appendingPathComponent("video.mp4")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: good.videoPath), to: file)
        let project = try WallpaperProject.load(folder: root)
        var state = AppState()
        state.projects = [project]
        state.applyToAll(Assignment(projectID: project.id), displays: ["test"])
        let display = Display(id: "test", name: "test", screen: screen)
        let engine = WallpaperEngine()
        defer { engine.stop() }
        engine.reconcile(state: state, displays: [display], shouldPlay: true)
        try await Task.sleep(for: .seconds(1))
        XCTAssertNotNil(engine.sessions["test"])
        engine.reconcile(state: state, displays: [], shouldPlay: true)
        XCTAssertTrue(engine.sessions.isEmpty)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: URL(fileURLWithPath: good.videoPath))
        engine.reconcile(state: state, displays: [display], shouldPlay: true)
        try await Task.sleep(for: .seconds(1))
        XCTAssertNil(engine.sessions["test"], "Reconnect must recheck containment before opening the video")
    }
}
