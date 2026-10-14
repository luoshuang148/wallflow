import XCTest
@testable import WallpaperRuntime

@MainActor final class ManagementExitTests: XCTestCase {
    func testCompleteExitQuiescesBeforeStopAndTerminatesOnlyAfterSuccess() async {
        var events: [String] = []
        let exit = ManagementExitCoordinator(quiesce: { events.append("quiesce") }, stop: { events.append("stop") },
            recover: { events.append("recover") }, terminate: { events.append("terminate") })
        await exit.stopWallpaperAndExit()
        XCTAssertEqual(events, ["quiesce", "stop", "terminate"])
        XCTAssertNil(exit.errorMessage)
    }
    func testFailedCompleteExitKeepsManagerAvailableForRetry() async {
        var events: [String] = [], fails = true
        let exit = ManagementExitCoordinator(quiesce: { events.append("quiesce") }, stop: {
            events.append("stop")
            if fails { throw NSError(domain: "playerStillRunning", code: 1) }
        }, recover: { events.append("recover") }, terminate: { events.append("terminate") })
        await exit.stopWallpaperAndExit()
        XCTAssertEqual(events, ["quiesce", "stop", "recover"])
        XCTAssertNotNil(exit.errorMessage)
        XCTAssertFalse(exit.isExiting)
        fails = false
        await exit.stopWallpaperAndExit()
        XCTAssertEqual(events.suffix(3), ["quiesce", "stop", "terminate"])
    }
}
