import XCTest
import AppKit
@testable import WallpaperCore
@testable import WallpaperRuntime

@MainActor final class FeatureIntegrationTests: XCTestCase {
    func testLegacyStateEncodesNewDefaults() throws {
        let state = try JSONDecoder().decode(AppState.self, from: Data(#"{"projects":[],"assignments":{},"manuallyPaused":false}"#.utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String:Any])
        XCTAssertNotNil(json["organization"])
        XCTAssertNotNil(json["playlist"])
        XCTAssertNotNil(json["applicationRules"])
    }

    func testRemovalCleansCollectionsAndDisablesIncompletePlaylist() throws {
        var state = AppState()
        state.organization.toggleFavorite("A")
        let group = try state.organization.addGroup("动画")
        state.organization.memberships["A"] = group
        state.playlist.enabled = true; state.playlist.projectIDs = ["A", "B"]
        state.remove(projectID: "A")
        XCTAssertFalse(state.organization.favorites.contains("A"))
        XCTAssertNil(state.organization.memberships["A"])
        XCTAssertEqual(state.playlist.projectIDs, ["B"])
        XCTAssertFalse(state.playlist.enabled)
    }
    func makeModel() throws -> (LibraryModel, URL) {
        _ = NSApplication.shared
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = LibraryModel(storeURL: temp.appendingPathComponent("state.json"))
        var performance = model.state.performance; performance.pauseWhenOccluded = false
        model.setPerformance(performance)
        return (model, temp)
    }
    func folder() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        return URL(fileURLWithPath: path)
    }
    func testSettingsEditedDuringApplySurviveAndPersist() async throws {
        let (model, temp) = try makeModel()
        defer { model.engine.stop(); try? FileManager.default.removeItem(at:temp) }
        let imported = await model.importFolder(try folder())
        let id = try XCTUnwrap(imported)
        let task = Task { await model.apply(projectID:id,target:nil,fit:.fill) }
        while !model.isBusy { await Task.yield() }
        var organization = LibraryOrganization(); organization.toggleFavorite(id)
        model.setOrganization(organization)
        var playlist = PlaylistSettings(); playlist.intervalMinutes = 7
        model.setPlaylist(playlist)
        let rules = [ApplicationRule(bundleID:"test.nonexistent",name:"Test",action:.mute)]
        model.setApplicationRules(rules)
        await task.value
        XCTAssertEqual(model.state.organization, organization)
        XCTAssertEqual(model.state.playlist, playlist)
        XCTAssertEqual(model.state.applicationRules, rules)
        XCTAssertEqual(try StateStore.load(from:model.storeURL), model.state)
        XCTAssertEqual(model.state.defaultAssignment?.projectID,id)
    }
    func testApplicationOverridesRestoreManualPreferencesAndStopReleasesResources() async throws {
        let (model, temp) = try makeModel()
        defer { model.engine.stop(); try? FileManager.default.removeItem(at:temp) }
        let imported = await model.importFolder(try folder())
        let id = try XCTUnwrap(imported)
        await model.apply(projectID:id,target:nil,fit:.fill)
        let saved = model.state.assignments
        model.setApplicationRules([ApplicationRule(bundleID:"test.app",name:"Test",action:.mute)])
        model.updateApplications(running:["test.app"],frontmost:"test.app")
        XCTAssertFalse(model.state.isMuted)
        XCTAssertTrue(model.engine.sessions.values.allSatisfy { $0.player.isMuted })
        model.updateApplications(running:[],frontmost:nil)
        XCTAssertEqual(model.engine.sessions.values.filter { !$0.player.isMuted }.count,1)
        model.setApplicationRules([ApplicationRule(bundleID:"test.app",name:"Test",action:.pause)])
        model.updateApplications(running:["test.app"],frontmost:"test.app")
        XCTAssertFalse(model.state.manuallyPaused)
        XCTAssertFalse(model.shouldPlay)
        XCTAssertTrue(model.engine.sessions.values.allSatisfy { $0.player.rate == 0 })
        model.togglePause()
        model.updateApplications(running:[],frontmost:nil)
        XCTAssertTrue(model.state.manuallyPaused)
        XCTAssertFalse(model.shouldPlay)
        model.togglePause()
        model.setApplicationRules([ApplicationRule(bundleID:"test.app",name:"Test",action:.stop)])
        model.updateApplications(running:["test.app"],frontmost:"test.app")
        XCTAssertTrue(model.engine.sessions.isEmpty)
        model.setMuted(true); model.setMuted(false)
        model.updatePowerState(onBattery:false,lowPowerMode:false)
        XCTAssertTrue(model.engine.sessions.isEmpty)
        model.updateApplications(running:[],frontmost:nil)
        for _ in 0..<150 where model.engine.sessions.isEmpty { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertEqual(model.engine.sessions.count,model.displays.count)
        XCTAssertEqual(model.state.assignments,saved)
        XCTAssertFalse(model.state.manuallyPaused)
    }
    func testStopRuleAllowsSavingNewAssignmentWithoutCreatingPlayers() async throws {
        let (model, temp) = try makeModel()
        defer { model.engine.stop(); try? FileManager.default.removeItem(at:temp) }
        let imported = await model.importFolder(try folder())
        let id = try XCTUnwrap(imported)
        model.setApplicationRules([ApplicationRule(bundleID:"test.app",name:"Test",action:.stop)])
        model.updateApplications(running:["test.app"],frontmost:"test.app")
        await model.apply(projectID:id,target:nil,fit:.fit)
        XCTAssertEqual(model.state.defaultAssignment?.projectID,id)
        XCTAssertTrue(model.engine.sessions.isEmpty)
    }

    func testPlaylistTicksSkipManualPauseAndDisconnectedTarget() async throws {
        let (model, temp) = try makeModel()
        defer { model.engine.stop(); try? FileManager.default.removeItem(at:temp) }
        let original = try WallpaperProject.load(folder:folder())
        let other = temp.appendingPathComponent("other")
        try FileManager.default.createDirectory(at:other,withIntermediateDirectories:true)
        try FileManager.default.linkItem(at:URL(fileURLWithPath:original.videoPath),to:other.appendingPathComponent("video.mp4"))
        try Data(#"{"type":"video","title":"Other","file":"video.mp4"}"#.utf8).write(to:other.appendingPathComponent("project.json"))
        let firstImported = await model.importFolder(try folder())
        let first = try XCTUnwrap(firstImported)
        let imported = await model.importFolder(other)
        let second = try XCTUnwrap(imported)
        var settings = PlaylistSettings(); settings.enabled = true; settings.intervalMinutes = 1; settings.projectIDs = [first,second]
        model.setPlaylist(settings)
        let base = Date(timeIntervalSince1970:1_800_000_000)
        await model.tickPlaylist(now:base)
        XCTAssertNil(model.state.defaultAssignment)
        await model.tickPlaylist(now:base.addingTimeInterval(61))
        XCTAssertEqual(model.state.defaultAssignment?.projectID,first)
        await model.tickPlaylist(now:base.addingTimeInterval(122))
        XCTAssertEqual(model.state.defaultAssignment?.projectID,second)
        model.togglePause()
        await model.tickPlaylist(now:base.addingTimeInterval(183))
        XCTAssertEqual(model.state.defaultAssignment?.projectID,second)
        model.togglePause()
        await model.tickPlaylist(now:base.addingTimeInterval(184))
        XCTAssertEqual(model.state.defaultAssignment?.projectID,first)
        await model.tickPlaylist(now:base.addingTimeInterval(185))
        XCTAssertEqual(model.state.defaultAssignment?.projectID,first)
        var disconnected = model.state
        disconnected.playlist.targetDisplayID = "disconnected"
        try StateStore.save(disconnected,to:temp.appendingPathComponent("offline.json"))
        let offline = LibraryModel(storeURL:temp.appendingPathComponent("offline.json"))
        defer { offline.engine.stop() }
        await offline.restore()
        await offline.tickPlaylist(now:base)
        await offline.tickPlaylist(now:base.addingTimeInterval(61))
        XCTAssertEqual(offline.state.assignments,disconnected.assignments)
    }

    func testAutomaticChangeDefersWhenPauseArrivesDuringPreparation() async throws {
        let (model,temp) = try makeModel()
        defer { model.engine.stop(); try? FileManager.default.removeItem(at:temp) }
        let firstImported = await model.importFolder(try folder())
        let first = try XCTUnwrap(firstImported)
        let original = try WallpaperProject.load(folder:folder())
        let other = temp.appendingPathComponent("other")
        try FileManager.default.createDirectory(at:other,withIntermediateDirectories:true)
        try FileManager.default.linkItem(at:URL(fileURLWithPath:original.videoPath),to:other.appendingPathComponent("video.mp4"))
        try Data(#"{"type":"video","file":"video.mp4"}"#.utf8).write(to:other.appendingPathComponent("project.json"))
        let secondImported = await model.importFolder(other)
        let second = try XCTUnwrap(secondImported)
        var playlist = PlaylistSettings(); playlist.enabled = true; playlist.intervalMinutes = 1; playlist.projectIDs = [first,second]
        model.setPlaylist(playlist)
        let base = Date(timeIntervalSince1970:1_800_000_000)
        await model.tickPlaylist(now:base)
        let task = Task { await model.tickPlaylist(now:base.addingTimeInterval(61)) }
        while !model.isBusy { await Task.yield() }
        model.togglePause()
        await task.value
        XCTAssertNil(model.state.defaultAssignment,"A new automatic wallpaper must not commit after a pause")
        model.togglePause()
        await model.tickPlaylist(now:base.addingTimeInterval(62))
        XCTAssertEqual(model.state.defaultAssignment?.projectID,first,"Deferred deadline must remain due")
    }
}
