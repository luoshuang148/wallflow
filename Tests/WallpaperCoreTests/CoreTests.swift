import XCTest
@testable import WallpaperCore

final class CoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func folder(_ name: String = "wallpaper", metadata: [String: Any] = [:]) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var json: [String: Any] = ["type": "video", "file": "视频.mp4", "title": "测试壁纸", "preview": "preview.jpg"]
        json.merge(metadata) { _, new in new }
        try JSONSerialization.data(withJSONObject: json).write(to: url.appendingPathComponent("project.json"))
        try Data([0]).write(to: url.appendingPathComponent("视频.mp4"))
        return url
    }
    func testSoundDefaultsOnAndMuteChoiceSurvivesOldStateRoundTrip() throws {
        let legacy = Data(#"{"projects":[],"assignments":{},"manuallyPaused":false}"#.utf8)
        var state = try JSONDecoder().decode(AppState.self,from:legacy)
        XCTAssertFalse(state.isMuted)
        state.isMuted = true
        let restored = try JSONDecoder().decode(AppState.self,from:JSONEncoder().encode(state))
        XCTAssertTrue(restored.isMuted)
        XCTAssertEqual(restored.projects,state.projects)
    }
    func testImportsUnicodeVideoAndOptionalPreview() throws {
        let url = try folder()
        let project = try WallpaperProject.load(folder: url)
        XCTAssertEqual(project.title, "测试壁纸")
        XCTAssertEqual(project.videoPath, url.appendingPathComponent("视频.mp4").path)
        XCTAssertNil(project.previewPath)
    }
    func testSearchMatchesNameAndWorkshopNumber() throws {
        let roxy = try WallpaperProject.load(folder:folder("3524676173",metadata:["title":"洛琪希 Roxy"]))
        let cafe = try WallpaperProject.load(folder:folder("5678",metadata:["title":"Café Night"]))
        let projects = [roxy,cafe]
        for query in ["洛琪", "ROXY", "352467", "roxy 6173"] {
            XCTAssertEqual(WallpaperSearch.filter(projects,query:query),[roxy],query)
        }
        XCTAssertEqual(WallpaperSearch.filter(projects,query:"cafe"),[cafe])
        XCTAssertTrue(WallpaperSearch.filter(projects,query:"Roxy Night").isEmpty)
    }
    func testSearchWhitespaceNoResultsAndConvertedSourceIdentity() throws {
        let first = try WallpaperProject.load(folder:folder("converted",metadata:["title":"First"]))
            .identifyingSourceFolder("/original/901037918")
        let second = try WallpaperProject.load(folder:folder("second",metadata:["title":"Second"]))
        XCTAssertEqual(WallpaperSearch.filter([second,first],query:" \n\t "),[second,first])
        XCTAssertEqual(WallpaperSearch.filter([second,first],query:"901037918"),[first])
        XCTAssertTrue(WallpaperSearch.filter([second,first],query:"nothing-matches").isEmpty)
    }
    func testMissingTitleUsesFolderName() throws {
        let project = try WallpaperProject.load(folder: folder(metadata: ["title": "  "]))
        XCTAssertEqual(project.title, "wallpaper")
    }
    func testImportsCapitalizedVideoType() throws {
        let project = try WallpaperProject.load(folder: folder(metadata: ["type": "Video"]))
        XCTAssertEqual(project.title, "测试壁纸")
        XCTAssertTrue(project.videoPath.hasSuffix("视频.mp4"))
    }
    func testRejectsSceneAndMissingVideo() throws {
        XCTAssertThrowsError(try WallpaperProject.load(folder: folder("scene", metadata: ["type": "scene"])))
        XCTAssertThrowsError(try WallpaperProject.load(folder: folder("missing", metadata: ["file": "gone.mp4"])))
    }
    func testRejectsTraversalEvenWhenOutsideFileExists() throws {
        try Data([1]).write(to: root.appendingPathComponent("outside.mp4"))
        XCTAssertThrowsError(try WallpaperProject.load(folder: folder(metadata: ["file": "../outside.mp4"])))
    }
    func testRejectsSymlinkEscapingFolder() throws {
        let outside = root.appendingPathComponent("outside.mp4")
        try Data([1]).write(to: outside)
        let url = try folder(metadata: ["file": "link.mp4"])
        try FileManager.default.createSymbolicLink(at: url.appendingPathComponent("link.mp4"), withDestinationURL: outside)
        XCTAssertThrowsError(try WallpaperProject.load(folder: url))
    }
    func testPreviewEscapeIsIgnored() throws {
        try Data([1]).write(to: root.appendingPathComponent("outside.jpg"))
        let project = try WallpaperProject.load(folder: folder(metadata: ["preview": "../outside.jpg"]))
        XCTAssertNil(project.previewPath)
    }
    func testDefaultAssignmentAndDisconnectedOverrideSurviveRoundTrip() throws {
        var state = AppState()
        let p = try WallpaperProject.load(folder: folder())
        state.projects = [p]
        state.assignments["disconnected"] = Assignment(projectID: p.id, fit: .fit)
        state.applyToAll(Assignment(projectID: p.id), displays: ["internal"])
        state.manuallyPaused = true
        let file = root.appendingPathComponent("nested/state.json")
        try StateStore.save(state, to: file)
        let saved = try StateStore.load(from: file)
        XCTAssertEqual(saved, state)
        XCTAssertEqual(saved.assignment(for: "brand-new")?.projectID, p.id)
        XCTAssertEqual(saved.assignment(for: "disconnected")?.fit, .fit)
        XCTAssertEqual(saved.assignment(for: "internal")?.fit, .fill)
    }
    func testManualPauseSurvivesResumeAndMultipleSuspensions() {
        var intent = PlaybackIntent()
        XCTAssertTrue(intent.shouldPlay)
        intent.suspensions = ["lock", "sleep"]
        XCTAssertFalse(intent.shouldPlay)
        intent.suspensions.remove("sleep")
        XCTAssertFalse(intent.shouldPlay)
        intent.manuallyPaused = true
        intent.suspensions.removeAll()
        XCTAssertFalse(intent.shouldPlay)
        intent.manuallyPaused = false
        XCTAssertTrue(intent.shouldPlay)
    }
    func testRemovalClearsDefaultAndDisconnectedAssignments() throws {
        let p = try WallpaperProject.load(folder: folder())
        var state = AppState()
        state.projects = [p]
        state.applyToAll(Assignment(projectID: p.id), displays: ["offline"])
        state.remove(projectID: p.id)
        XCTAssertTrue(state.projects.isEmpty)
        XCTAssertNil(state.defaultAssignment)
        XCTAssertTrue(state.assignments.isEmpty)
    }
    func testMissingStateIsEmptyAndCorruptStateReportsError() throws {
        let file = root.appendingPathComponent("state.json")
        XCTAssertEqual(try StateStore.load(from: file), AppState())
        try Data("invalid".utf8).write(to: file)
        XCTAssertThrowsError(try StateStore.load(from: file))
    }
}
