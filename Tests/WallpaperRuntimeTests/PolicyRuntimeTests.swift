import XCTest
import AppKit
@testable import WallpaperCore
@testable import WallpaperRuntime

final class PolicyRuntimeTests: XCTestCase {
    @MainActor func testPauseBeforeQueuedReconciliationStartsIsPreserved() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let project = try WallpaperProject.load(folder: URL(fileURLWithPath: path))
        var state = AppState()
        state.projects = [project]
        state.applyToAll(Assignment(projectID: project.id), displays: ["screen"])
        let engine = WallpaperEngine()
        defer { engine.stop() }
        engine.reconcile(state: state, displays: [Display(id: "screen", name: "Test", screen: screen)], shouldPlay: true)
        engine.setPlaying(false)
        let deadline = Date().addingTimeInterval(4)
        while engine.sessions["screen"] == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(40)) }
        let session = try XCTUnwrap(engine.sessions["screen"])
        XCTAssertEqual(session.player.rate, 0, "Queued display work must not undo a newer pause")
    }
    @MainActor func testPowerPoliciesResumeOnlyAfterEveryReasonClearsAndPreserveManualPause() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        let model = LibraryModel(storeURL: file)
        defer { model.engine.stop() }
        var settings = model.state.performance
        settings.pauseOnBattery = true
        model.setPerformance(settings)
        model.updatePowerState(onBattery: true, lowPowerMode: true)
        XCTAssertFalse(model.shouldPlay)
        model.updatePowerState(onBattery: false, lowPowerMode: true)
        XCTAssertFalse(model.shouldPlay)
        model.updatePowerState(onBattery: false, lowPowerMode: false)
        XCTAssertTrue(model.shouldPlay)
        model.togglePause()
        model.updatePowerState(onBattery: true, lowPowerMode: false)
        settings.pauseOnBattery = false
        model.setPerformance(settings)
        XCTAssertFalse(model.shouldPlay)
        model.togglePause()
        XCTAssertTrue(model.shouldPlay)
        model.setSuspended("lock", active: true)
        model.updatePowerState(onBattery: false, lowPowerMode: false)
        XCTAssertFalse(model.shouldPlay)
        model.setSuspended("lock", active: false)
        XCTAssertTrue(model.shouldPlay)
        XCTAssertEqual(try StateStore.load(from: file).performance, settings)
    }

    @MainActor private func processWindowEvents() async throws {
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            while let event = NSApplication.shared.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                NSApplication.shared.sendEvent(event)
            }
            NSApplication.shared.updateWindows()
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor func testOcclusionPausesOnlyCoveredDisplayAndRespectsGlobalPause() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let project = try WallpaperProject.load(folder: URL(fileURLWithPath: path))
        var state = AppState()
        state.projects = [project]
        state.applyToAll(Assignment(projectID: project.id), displays: ["left", "right"])
        let engine = WallpaperEngine()
        defer { engine.stop() }
        let displays = [Display(id: "left", name: "Left", screen: screen), Display(id: "right", name: "Right", screen: screen)]
        let change = try await engine.prepare(state: state, displays: displays, shouldPlay: true)
        try engine.commit(change, shouldPlay: true)
        let left = try XCTUnwrap(engine.sessions["left"])
        let right = try XCTUnwrap(engine.sessions["right"])
        let frame = screen.frame
        let half = NSRect(x: frame.minX + 20, y: frame.minY + 80, width: frame.width / 2 - 40, height: frame.height - 160)
        left.window.level = .floating
        right.window.level = .floating
        left.window.setFrame(half, display: true)
        right.window.setFrame(half.offsetBy(dx: frame.width / 2, dy: 0), display: true)
        left.window.orderFront(nil)
        right.window.orderFront(nil)
        engine.setOcclusionPolicy(true)
        try await processWindowEvents()
        XCTAssertGreaterThan(left.player.rate, 0)
        XCTAssertGreaterThan(right.player.rate, 0)
        let cover = NSWindow(contentRect: half, styleMask: .borderless, backing: .buffered, defer: false)
        cover.isReleasedWhenClosed = false
        cover.backgroundColor = .black
        cover.isOpaque = true
        cover.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        defer { cover.close() }
        cover.setFrame(NSRect(x: half.minX, y: half.minY, width: half.width / 2, height: half.height), display: true)
        cover.orderFront(nil)
        try await processWindowEvents()
        XCTAssertFalse(left.isOccluded)
        XCTAssertGreaterThan(left.player.rate, 0, "Partially visible desktops should keep playing")
        cover.setFrame(half, display: true)
        try await processWindowEvents()
        XCTAssertTrue(left.isOccluded)
        XCTAssertEqual(left.player.rate, 0)
        XCTAssertGreaterThan(right.player.rate, 0)
        engine.setOcclusionPolicy(false)
        XCTAssertGreaterThan(left.player.rate, 0)
        engine.setOcclusionPolicy(true)
        engine.setPlaying(false)
        cover.orderOut(nil)
        try await processWindowEvents()
        XCTAssertFalse(left.isOccluded)
        XCTAssertEqual(left.player.rate, 0)
        XCTAssertEqual(right.player.rate, 0)
        engine.setPlaying(true)
        XCTAssertGreaterThan(left.player.rate, 0)
        XCTAssertGreaterThan(right.player.rate, 0)
    }
}
