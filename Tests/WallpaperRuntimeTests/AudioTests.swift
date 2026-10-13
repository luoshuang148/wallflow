import XCTest
import AppKit
@testable import WallpaperCore
@testable import WallpaperRuntime

@MainActor final class AudioTests: XCTestCase {
    func project() throws -> WallpaperProject {
        guard let folder = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        return try WallpaperProject.load(folder:URL(fileURLWithPath:folder))
    }
    func testUninstalledPlayerStartsMuted() throws {
        _ = NSApplication.shared
        let session = WallpaperSession(project:try project(),fit:.fit,screen:try XCTUnwrap(NSScreen.screens.first),onOcclusionChange:{_ in},onError:{_,_ in})
        defer { session.stop() }
        XCTAssertTrue(session.player.isMuted,"Preparing players must remain silent until committed")
    }
    func testGlobalMuteAndOnlyOnePlayingDisplayHasSound() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var state = AppState(); state.isMuted = false
        let project = try project(); state.projects = [project]
        state.applyToAll(Assignment(projectID:project.id),displays:["A","B"])
        let displays = [Display(id:"A",name:"A",screen:screen),Display(id:"B",name:"B",screen:screen)]
        let engine = WallpaperEngine(); defer { engine.stop() }
        let prepared = try await engine.prepare(state:state,displays:displays,shouldPlay:true)
        try engine.commit(prepared,shouldPlay:true)
        XCTAssertFalse(try XCTUnwrap(engine.sessions["A"]).player.isMuted)
        XCTAssertTrue(try XCTUnwrap(engine.sessions["B"]).player.isMuted)
        engine.setMuted(true)
        XCTAssertTrue(engine.sessions.values.allSatisfy { $0.player.isMuted })
        engine.setMuted(false)
        XCTAssertEqual(engine.sessions.values.filter { !$0.player.isMuted }.count,1)
        engine.setPlaying(false)
        XCTAssertTrue(engine.sessions.values.allSatisfy { $0.player.isMuted })
        engine.setPlaying(true)
        XCTAssertEqual(engine.sessions.values.filter { !$0.player.isMuted }.count,1)
        engine.reconcile(state:state,displays:[displays[1]],shouldPlay:true)
        for _ in 0..<50 where engine.sessions["B"]?.player.isMuted != false { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertNil(engine.sessions["A"])
        XCTAssertFalse(try XCTUnwrap(engine.sessions["B"]).player.isMuted)
    }
    func testMuteDuringApplyPersistsAndRestores() async throws {
        _ = NSApplication.shared
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:temp) }
        let store = temp.appendingPathComponent("state.json")
        let model = LibraryModel(storeURL:store); defer { model.engine.stop() }
        var performance = model.state.performance
        performance.pauseWhenOccluded = false
        model.setPerformance(performance)
        XCTAssertFalse(model.state.isMuted)
        let imported = await model.importFolder(URL(fileURLWithPath:try project().folderPath))
        let id = try XCTUnwrap(imported)
        let apply = Task { await model.apply(projectID:id,target:nil,fit:.fit) }
        while !model.isBusy { await Task.yield() }
        model.setMuted(true)
        await apply.value
        XCTAssertEqual(model.engine.sessions.count,model.displays.count)
        XCTAssertTrue(model.state.isMuted)
        XCTAssertTrue(model.engine.sessions.values.allSatisfy { $0.player.isMuted })
        XCTAssertTrue(try StateStore.load(from:store).isMuted)
        model.engine.stop()
        let restored = LibraryModel(storeURL:store); defer { restored.engine.stop() }
        await restored.restore()
        XCTAssertTrue(restored.state.isMuted)
        XCTAssertTrue(restored.engine.sessions.values.allSatisfy { $0.player.isMuted })
        restored.setMuted(false)
        XCTAssertFalse(try StateStore.load(from:store).isMuted)
        XCTAssertEqual(restored.engine.sessions.values.filter { !$0.player.isMuted }.count,1)
    }
    func testSoundMovesToSurvivingDisplayAfterPlaybackFailure() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let project = try project()
        var state = AppState(); state.projects = [project]
        state.applyToAll(Assignment(projectID:project.id),displays:["A","B"])
        let engine = WallpaperEngine(); defer { engine.stop() }
        let change = try await engine.prepare(state:state,displays:[Display(id:"A",name:"A",screen:screen),Display(id:"B",name:"B",screen:screen)],shouldPlay:true)
        try engine.commit(change,shouldPlay:true)
        let failed = try XCTUnwrap(engine.sessions["A"])
        XCTAssertFalse(failed.player.isMuted)
        failed.handleFailure("Simulated decoder failure")
        XCTAssertNil(engine.sessions["A"])
        let survivor = try XCTUnwrap(engine.sessions["B"])
        XCTAssertFalse(survivor.player.isMuted)
        XCTAssertEqual(survivor.player.rate,1)
    }
}
