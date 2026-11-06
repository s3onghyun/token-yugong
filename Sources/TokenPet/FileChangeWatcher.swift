import Foundation
import Darwin

/// A cheap nudge to refresh local usage data after a directory changes. The five-minute timer
/// remains as a recovery path for paths that do not exist yet and for nested tool log folders.
final class FileChangeWatcher {
    private let descriptor: CInt
    private let source: DispatchSourceFileSystemObject

    init?(directory: URL, queue: DispatchQueue = .global(qos: .utility), changed: @escaping () -> Void) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        self.descriptor = descriptor
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler(handler: changed)
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
    }

    deinit { source.cancel() }
}

enum UsageRefreshPolicy {
    /// File watches provide the prompt path; this is only a safety net for a newly-created or
    /// deeply nested log directory whose event could not be watched at launch.
    static let fallbackInterval: TimeInterval = 5 * 60
    static let notificationDebounce: TimeInterval = 1
    /// A busy CLI appends to a rollout log many times per response. A notification is still a
    /// prompt refresh path, but never turns each append into a costly complete history scan.
    static let minimumNotificationInterval: TimeInterval = 30
}
