import Foundation
import Combine

/// Prevents a failed or pending background shutdown from closing management as if it succeeded.
@MainActor public final class ManagementExitCoordinator: ObservableObject {
    @Published public private(set) var isExiting = false
    @Published public private(set) var errorMessage: String?
    private let quiesce: () -> Void
    private let stop: () async throws -> Void
    private let recover: () -> Void
    private let terminate: () -> Void
    public init(quiesce: @escaping () -> Void, stop: @escaping () async throws -> Void,
                recover: @escaping () -> Void, terminate: @escaping () -> Void) {
        self.quiesce = quiesce; self.stop = stop; self.recover = recover; self.terminate = terminate
    }
    public func stopWallpaperAndExit() async {
        guard !isExiting else { return }
        isExiting = true; errorMessage = nil
        quiesce()
        do { try await stop(); terminate() }
        catch {
            errorMessage = error.localizedDescription
            recover()
            isExiting = false
        }
    }
}
