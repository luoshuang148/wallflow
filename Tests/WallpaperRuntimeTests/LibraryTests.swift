import XCTest
import AppKit
@testable import WallpaperCore
@testable import WallpaperRuntime

final class LibraryTests: XCTestCase {
    @MainActor func testImportApplyAndRestartPreserveScreenChoiceAndManualPause() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: path)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        let model = LibraryModel(storeURL: file)
        defer { model.engine.stop() }
        let imported = await model.importFolder(folder)
        let id = try XCTUnwrap(imported)
        XCTAssertEqual(model.state.projects.count, 1)
        await model.apply(projectID: id, target: nil, fit: .fit)
        XCTAssertEqual(model.state.assignment(for: "new-screen")?.fit, .fit)
        let display = try XCTUnwrap(model.displays.first)
        await model.apply(projectID: id, target: display.id, fit: .fill)
        XCTAssertEqual(model.state.assignment(for: display.id)?.fit, .fill)
        model.togglePause()
        model.setSuspended("lock", active: true)
        model.setSuspended("sleep", active: true)
        model.setSuspended("sleep", active: false)
        model.setSuspended("lock", active: false)
        XCTAssertFalse(model.shouldPlay)
        model.engine.stop()
        let restored = LibraryModel(storeURL: file)
        defer { restored.engine.stop() }
        await restored.restore()
        XCTAssertEqual(restored.state, model.state)
        XCTAssertFalse(restored.shouldPlay)
        XCTAssertEqual(restored.engine.sessions[display.id]?.player.rate, 0)
    }
    @MainActor func testBadImportAndMissingApplyKeepPreviousSelection() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = LibraryModel(storeURL: dir.appendingPathComponent("state.json"))
        defer { model.engine.stop() }
        let imported = await model.importFolder(URL(fileURLWithPath: path))
        let id = try XCTUnwrap(imported)
        await model.apply(projectID: id, target: nil, fit: .fill)
        let before = model.state
        let invalid = dir.appendingPathComponent("bad")
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        try Data("{\"type\":\"video\",\"file\":\"fake.mp4\"}".utf8).write(to: invalid.appendingPathComponent("project.json"))
        try Data("not video".utf8).write(to: invalid.appendingPathComponent("fake.mp4"))
        let failed = await model.importFolder(invalid)
        XCTAssertNil(failed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.state, before)
        await model.apply(projectID: "missing", target: nil, fit: .fit)
        XCTAssertEqual(model.state, before)
        XCTAssertEqual(try StateStore.load(from: model.storeURL), before)
    }
}
