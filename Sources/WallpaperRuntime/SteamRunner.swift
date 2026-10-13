import Foundation
import Darwin
import WallpaperCore

public struct SteamProcessResult: Sendable { public let exitCode: Int32; public let output: String }
public enum SteamRunner {
    public static func run(executable: URL, arguments: [String], environment: [String: String]? = nil,
                           timeout: TimeInterval = 1200, outputLimit: Int = 2_000_000) async throws -> SteamProcessResult {
        let control = ProcessControl()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached(priority: .utility) {
                try control.run(executable: executable, arguments: arguments, environment: environment, timeout: timeout, limit: max(1024, outputLimit))
            }.value
        } onCancel: { control.stop(timedOut: false) }
    }
}
private final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var expired = false
    private var ownsGroup = false
    private var finished = false
    private var stoppedAt: Date?
    func stop(timedOut: Bool) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        cancelled = true; expired = timedOut || expired
        if stoppedAt == nil { stoppedAt = Date() }
        if let process {
            if ownsGroup { Darwin.kill(-process.processIdentifier, SIGTERM) }
            else if process.isRunning { process.terminate() }
        }
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now()+2) { [weak self] in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard !self.finished, let process = self.process else { return }
            if self.ownsGroup { Darwin.kill(-process.processIdentifier, SIGKILL) }
            else if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
    }
    func run(executable: URL, arguments: [String], environment: [String: String]?, timeout: TimeInterval, limit: Int) throws -> SteamProcessResult {
        let p = Process(); let pipe = Pipe()
        p.executableURL = executable; p.arguments = arguments
        p.currentDirectoryURL = executable.deletingLastPathComponent()
        p.environment = environment ?? ProcessInfo.processInfo.environment
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = pipe; p.standardError = pipe
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do {
            try p.run(); process = p
            // Foundation launches a separate process group on this Mac. Check before signaling it.
            ownsGroup = Darwin.getpgid(p.processIdentifier) == p.processIdentifier
            lock.unlock()
        }
        catch { lock.unlock(); throw error }
        try? pipe.fileHandleForWriting.close()
        let timer = DispatchWorkItem { [weak self] in self?.stop(timedOut: true) }
        DispatchQueue.global().asyncAfter(deadline: .now()+max(0.05, timeout), execute: timer)
        var output = Data()
        let fd = pipe.fileHandleForReading.fileDescriptor
        let originalFlags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK)
        var buffer = [UInt8](repeating: 0, count: 16384)
        // Nonblocking draining bounds completion even when a helper inherits the output pipe.
        while true {
            lock.lock()
            let stopDeadline = stoppedAt?.addingTimeInterval(2.5)
            lock.unlock()
            if let stopDeadline, Date() >= stopDeadline { break }
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            if count > 0 {
                output.append(contentsOf: buffer.prefix(count))
                if output.count > limit { output.removeFirst(output.count-limit) }
                continue
            }
            if count == 0 || (errno != EAGAIN && errno != EINTR) { break }
            if !p.isRunning { break }
            usleep(20_000)
        }
        p.waitUntilExit(); timer.cancel()
        lock.lock()
        if ownsGroup { Darwin.kill(-p.processIdentifier, SIGKILL) }
        finished = true; process = nil
        let wasCancelled = cancelled; let wasExpired = expired
        lock.unlock()
        try? pipe.fileHandleForReading.close()
        if wasExpired { throw WallpaperError.message("Steam 操作超时，已停止进程。请检查网络后重试。") }
        if wasCancelled { throw CancellationError() }
        return SteamProcessResult(exitCode: p.terminationStatus, output: String(decoding: output, as: UTF8.self))
    }
}
