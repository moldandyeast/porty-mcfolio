import Foundation
import CoreServices

final class FileWatcher {
    typealias Callback = ([String]) -> Void

    private var stream: FSEventStreamRef?
    private let callback: Callback
    private let path: String

    /// Indirection object whose lifetime is tied to the stream, not to `self`.
    /// Prevents use-after-free if an FSEvent callback is already queued when
    /// FileWatcher is deallocated.
    private final class StreamContext {
        let callback: Callback
        init(_ callback: @escaping Callback) { self.callback = callback }
    }
    private var streamContext: StreamContext?

    init(path: String, callback: @escaping Callback) {
        self.path = path
        self.callback = callback
    }

    func start() {
        guard stream == nil else { return }

        let ctx = StreamContext(callback)
        streamContext = ctx

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(ctx).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

        let eventCallback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let info = clientCallBackInfo else { return }
            let ctx = Unmanaged<StreamContext>.fromOpaque(info).takeUnretainedValue()

            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            let changedPaths = Array(paths.prefix(numEvents))
            ctx.callback(changedPaths)
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            eventCallback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        )

        guard let stream = stream else {
            // Stream creation failed — balance the retain
            Unmanaged.passUnretained(ctx).release()
            streamContext = nil
            return
        }

        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        // Balance the passRetained from start()
        if let ctx = streamContext {
            Unmanaged.passUnretained(ctx).release()
        }
        streamContext = nil
        self.stream = nil
    }

    deinit { stop() }
}
