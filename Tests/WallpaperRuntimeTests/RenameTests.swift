import XCTest
@testable import WallpaperCore
@testable import WallpaperRuntime

@MainActor final class RenameTests: XCTestCase {
    func fixture() throws -> (LibraryModel, WallpaperProject, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = WallpaperProject(folderPath:"/wallpapers/3524676173",title:"Original Roxy",videoPath:"/wallpapers/3524676173/video.mp4",previewPath:nil)
        var state = AppState(); state.projects = [project]
        state.applyToAll(Assignment(projectID:project.id),displays:["screen"])
        state.organization.favorites = [project.id]
        state.playlist.projectIDs = [project.id]
        let store = root.appendingPathComponent("state.json")
        try StateStore.save(state,to:store)
        return (LibraryModel(storeURL:store),project,root)
    }
    func testRenamePersistsTrimmedNameAndPreservesIdentityAndAssignments() throws {
        let (model,project,root) = try fixture()
        defer { model.engine.stop(); try? FileManager.default.removeItem(at:root) }
        let old = model.state
        XCTAssertTrue(model.rename(projectID:project.id,name:"  我的洛琪希 \n"))
        XCTAssertEqual(model.displayName(for:project),"我的洛琪希")
        XCTAssertEqual(model.state.projects,old.projects)
        XCTAssertEqual(model.state.assignments,old.assignments)
        XCTAssertEqual(model.state.organization.favorites,old.organization.favorites)
        XCTAssertEqual(model.state.playlist,old.playlist)
        let restored = LibraryModel(storeURL:model.storeURL)
        defer { restored.engine.stop() }
        XCTAssertEqual(restored.displayName(for:project),"我的洛琪希")
        XCTAssertFalse(model.rename(projectID:project.id,name:" \n\t"))
        XCTAssertEqual(model.displayName(for:project),"我的洛琪希")
        XCTAssertFalse(model.rename(projectID:"missing",name:"Other"))
        XCTAssertTrue(model.rename(projectID:project.id,name:nil))
        XCTAssertEqual(model.displayName(for:project),"Original Roxy")
        XCTAssertEqual(try StateStore.load(from:model.storeURL).organization.customNames,[:])
    }
    func testRenamedTitlesDriveSearchAndSortingAndRemovalCleansAlias() throws {
        let (model,project,root) = try fixture()
        defer { model.engine.stop(); try? FileManager.default.removeItem(at:root) }
        XCTAssertTrue(model.rename(projectID:project.id,name:"Zulu"))
        let other = WallpaperProject(folderPath:"/wallpapers/9",title:"Beta",videoPath:"/wallpapers/9/v.mp4",previewPath:nil)
        var org = model.state.organization; org.sort = .title
        XCTAssertEqual(org.filterAndSort([project,other],query:"zulu",favoritesOnly:false,groupID:nil).map(\.id),[project.id])
        XCTAssertEqual(org.filterAndSort([project,other],query:"ROXY",favoritesOnly:false,groupID:nil).map(\.id),[project.id])
        XCTAssertEqual(org.filterAndSort([project,other],query:"352467",favoritesOnly:false,groupID:nil).map(\.id),[project.id])
        XCTAssertEqual(org.filterAndSort([project,other],query:"",favoritesOnly:false,groupID:nil).map(\.id),[other.id,project.id])
        model.remove(projectID:project.id)
        XCTAssertNil(model.state.organization.customNames[project.id])
    }
    func testLegacyStateHasNoCustomNames() throws {
        let decoded = try JSONDecoder().decode(LibraryOrganization.self,from:Data(#"{"favorites":[],"groups":[],"memberships":{},"sort":"added"}"#.utf8))
        XCTAssertEqual(decoded.customNames,[:])
    }

    func testReimportRetainsAliasAndLeavesSourceManifestUnchanged() async throws {
        guard let folder = ProcessInfo.processInfo.environment["WALLPAPER_FOLDER"] else { throw XCTSkip("Set WALLPAPER_FOLDER") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = LibraryModel(storeURL:root.appendingPathComponent("state.json"))
        defer { model.engine.stop(); try? FileManager.default.removeItem(at:root) }
        let source = URL(fileURLWithPath:folder)
        let manifest = try Data(contentsOf:source.appendingPathComponent("project.json"))
        let imported = await model.importFolder(source)
        let id = try XCTUnwrap(imported)
        XCTAssertTrue(model.rename(projectID:id,name:"Custom title"))
        let again = await model.importFolder(source)
        XCTAssertEqual(again,id)
        XCTAssertEqual(model.state.projects.count,1)
        XCTAssertEqual(model.displayName(for:try XCTUnwrap(model.state.projects.first)),"Custom title")
        XCTAssertEqual(try Data(contentsOf:source.appendingPathComponent("project.json")),manifest)
    }
}
