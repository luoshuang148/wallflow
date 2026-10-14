import XCTest
@testable import WallpaperCore

final class SharedStateStoreTests: XCTestCase {
    func testPlaylistDependencyIsCheckedInsideLockBeforeChangingAssignment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.json")
        let base = AppState()
        var newer = base; newer.manuallyPaused = true
        try StateStore.save(newer, to: url)
        var rotation = base; rotation.defaultAssignment = Assignment(projectID: "rotation")
        XCTAssertThrowsError(try SharedStateStore.saveChanges(base: base, next: rotation, to: url, validate: { current in
            if current.manuallyPaused { throw CancellationError() }
        }))
        XCTAssertEqual(try StateStore.load(from: url), newer)
    }
    private func store() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
    }
    func testAssignmentFitAndProjectAreOneConcurrentChoice() throws {
        for useDefault in [true, false] {
            let url = store(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            var base = AppState()
            func assign(_ state: inout AppState, _ value: Assignment) {
                if useDefault { state.defaultAssignment = value } else { state.assignments["display"] = value }
            }
            assign(&base, Assignment(projectID: "A", fit: .fill))
            try StateStore.save(base, to: url)
            var manual = base; assign(&manual, Assignment(projectID: "A", fit: .fit))
            _ = try SharedStateStore.saveChanges(base: base, next: manual, to: url)
            var staleRotation = base; assign(&staleRotation, Assignment(projectID: "B", fit: .fill))
            XCTAssertThrowsError(try SharedStateStore.saveChanges(base: base, next: staleRotation, to: url))
            XCTAssertEqual(try StateStore.load(from: url), manual)
        }
    }
    func testIndependentSettingsAndAssignmentsSurviveStaleWriter() throws {
        let url = store(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let base = AppState(); try StateStore.save(base, to: url)
        var background = base; background.defaultAssignment = Assignment(projectID: "new-wallpaper")
        _ = try SharedStateStore.saveChanges(base: base, next: background, to: url)
        var manager = base; manager.isMuted = true
        let saved = try SharedStateStore.saveChanges(base: base, next: manager, to: url)
        XCTAssertTrue(saved.isMuted)
        XCTAssertEqual(saved.defaultAssignment, background.defaultAssignment)
        XCTAssertEqual(try StateStore.load(from: url), saved)
    }
    func testNestedSettingsMergeAndOptionalDeletion() throws {
        let url = store(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var base = AppState(); base.defaultAssignment = Assignment(projectID: "old")
        try StateStore.save(base, to: url)
        var a = base; a.performance.pauseOnBattery = true
        _ = try SharedStateStore.saveChanges(base: base, next: a, to: url)
        var b = base; b.performance.pauseInLowPowerMode = false; b.defaultAssignment = nil
        let saved = try SharedStateStore.saveChanges(base: base, next: b, to: url)
        XCTAssertTrue(saved.performance.pauseOnBattery)
        XCTAssertFalse(saved.performance.pauseInLowPowerMode)
        XCTAssertNil(saved.defaultAssignment)
    }
    func testConflictingAssignmentDoesNotOverwriteNewerChoice() throws {
        let url = store(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var base = AppState(); base.defaultAssignment = Assignment(projectID: "old")
        try StateStore.save(base, to: url)
        var a = base; a.defaultAssignment = Assignment(projectID: "manual")
        _ = try SharedStateStore.saveChanges(base: base, next: a, to: url)
        let before = try Data(contentsOf: url)
        var b = base; b.defaultAssignment = Assignment(projectID: "playlist")
        XCTAssertThrowsError(try SharedStateStore.saveChanges(base: base, next: b, to: url))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
    func testUnchangedAndIdempotentWritesPreserveBytes() throws {
        let url = store(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let base = AppState(); try StateStore.save(base, to: url)
        let before = try Data(contentsOf: url)
        _ = try SharedStateStore.saveChanges(base: base, next: base, to: url)
        XCTAssertEqual(try Data(contentsOf: url), before)
        var next = base; next.isMuted = true
        _ = try SharedStateStore.saveChanges(base: base, next: next, to: url)
        _ = try SharedStateStore.saveChanges(base: base, next: next, to: url)
        XCTAssertTrue(try StateStore.load(from: url).isMuted)
    }
    func testCorruptStateIsNeverReplaced() throws {
        let url = store(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let damaged = Data("not json".utf8); try damaged.write(to: url)
        var next = AppState(); next.isMuted = true
        XCTAssertThrowsError(try SharedStateStore.saveChanges(base: AppState(), next: next, to: url))
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }
}
