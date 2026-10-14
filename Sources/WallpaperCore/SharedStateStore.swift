import Foundation
import Darwin

/// Both app processes serialize changes and merge only the fields they edited.
public enum SharedStateStore {
    public static let notification = "local.zongzihao.WallFlow.stateChanged"

    public static func saveChanges(base: AppState, next: AppState, to url: URL, validate: (AppState) throws -> Void = { _ in }) throws -> AppState {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = url.appendingPathExtension("lock")
        let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw WallpaperError.message("无法锁定壁纸设置。") }
        defer { flock(fd, LOCK_UN); Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw WallpaperError.message("无法锁定壁纸设置。") }
        let current = try StateStore.load(from: url)
        try validate(current)
        let encoder = JSONEncoder()
        func object(_ state: AppState) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(state)) }
        let merged = try merge(base: object(base), next: object(next), current: object(current), path: "设置")!
        let result = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: merged))
        if result != current || !FileManager.default.fileExists(atPath: url.path) {
            try StateStore.save(result, to: url)
            DistributedNotificationCenter.default().postNotificationName(Notification.Name(notification), object: url.path, userInfo: nil, deliverImmediately: true)
        }
        return result
    }

    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil || b == nil { return a == nil && b == nil }
        return (a as? NSObject)?.isEqual(b) == true
    }
    private static func merge(base: Any?, next: Any?, current: Any?, path: String) throws -> Any? {
        if equal(base, next) || equal(next, current) { return current }
        if equal(base, current) { return next }
        // A project and its fit mode are one user choice, never a mix of competing choices.
        let atomicAssignment = path == "设置.defaultAssignment" || path.hasPrefix("设置.assignments.")
        if !atomicAssignment, let b = base as? [String: Any], let n = next as? [String: Any], let c = current as? [String: Any] {
            var result = c
            for key in Set(b.keys).union(n.keys).union(c.keys) {
                result[key] = try merge(base: b[key], next: n[key], current: c[key], path: path + "." + key)
            }
            return result
        }
        throw WallpaperError.message("\(path) 已在后台更新，请等待同步后重试。")
    }
}
