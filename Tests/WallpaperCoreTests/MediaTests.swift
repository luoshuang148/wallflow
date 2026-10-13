import XCTest
@testable import WallpaperCore

final class MediaTests: XCTestCase {
    func testNativeDecoderAcceptsRealWallpaper() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLPAPER_SAMPLE"] else {
            throw XCTSkip("Set WALLPAPER_SAMPLE to a local video for native decode verification")
        }
        let info = try await MediaValidator.validate(url: URL(fileURLWithPath: path))
        XCTAssertEqual(info.width, 3840)
        XCTAssertEqual(info.height, 2160)
        XCTAssertEqual(info.duration, 16.666667, accuracy: 0.1)
    }
    func testFakeVideoIsRejected() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("not a video".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            _ = try await MediaValidator.validate(url: file)
            XCTFail("Invalid MP4 accepted")
        } catch { /* Expected: invalid media must not replace a playing wallpaper. */ }
    }
}
