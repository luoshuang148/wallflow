import XCTest
@testable import WallpaperCore

final class PerformanceTests: XCTestCase {
    func testOldSettingsKeepWallpaperAndReceiveSafeDefaults() throws {
        let json = Data(#"{"projects":[],"assignments":{"screen":{"projectID":"saved","fit":"fit"}},"manuallyPaused":true}"#.utf8)
        let state = try JSONDecoder().decode(AppState.self, from: json)
        XCTAssertEqual(state.assignment(for: "screen")?.projectID, "saved")
        XCTAssertTrue(state.manuallyPaused)
        XCTAssertTrue(state.performance.pauseWhenOccluded)
        XCTAssertFalse(state.performance.pauseOnBattery)
        XCTAssertTrue(state.performance.pauseInLowPowerMode)
    }
    func testPoliciesComposeAndDisabledChoicesDoNotPause() {
        var settings = PerformanceSettings()
        XCTAssertEqual(settings.pauseReasons(onBattery: true, lowPowerMode: false, occluded: false), [])
        settings.pauseOnBattery = true
        XCTAssertEqual(settings.pauseReasons(onBattery: true, lowPowerMode: true, occluded: true), [.battery, .lowPowerMode, .occluded])
        settings.pauseWhenOccluded = false
        settings.pauseInLowPowerMode = false
        XCTAssertEqual(settings.pauseReasons(onBattery: true, lowPowerMode: true, occluded: true), [.battery])
        XCTAssertTrue(settings.pauseReasons(onBattery: false, lowPowerMode: false, occluded: false).isEmpty)
    }
    func testPerformanceChoicesSurviveStateRoundTrip() throws {
        let json = Data(#"{"projects":[],"assignments":{},"manuallyPaused":true,"performance":{"pauseWhenOccluded":false,"pauseOnBattery":true,"pauseInLowPowerMode":false}}"#.utf8)
        let state = try JSONDecoder().decode(AppState.self, from: json)
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        let performance = try XCTUnwrap(saved?["performance"] as? [String: Bool])
        XCTAssertEqual(performance["pauseWhenOccluded"], false)
        XCTAssertEqual(performance["pauseOnBattery"], true)
        XCTAssertEqual(performance["pauseInLowPowerMode"], false)
        XCTAssertTrue(state.manuallyPaused)
    }
}
