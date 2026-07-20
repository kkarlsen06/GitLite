import CoreServices
import Foundation

final class RepositoryWatcher: @unchecked Sendable {
    private let paths: [String]
    private let sinceWhen: FSEventStreamEventId
    private let callbackQueue = DispatchQueue(
        label: "com.hjalmarkarlsen.Kvist.repository-watcher",
        // Filesystem changes feed visible repository state. A utility queue can
        // be deprioritized for hundreds of milliseconds while the app or test
        // suite is busy, violating the bounded event-storm refresh latency.
        qos: .userInitiated
    )
    private let onChange: @Sendable ([String], [String]?) -> Void
    private let stateLock = NSLock()
    private var stream: FSEventStreamRef?
    private var pendingCallback: DispatchWorkItem?
    private var pendingPaths: Set<String> = []
    private var pendingPathsOverflowed = false
    private var pendingFileTreePaths: Set<String> = []
    private var pendingCallbackGeneration = 0
    private let maximumPendingPathCount = 256
    private let eventLatency: CFTimeInterval = 0.01
    private let burstQuietPeriod = DispatchTimeInterval.milliseconds(50)

    init(
        paths: [String],
        sinceWhen: FSEventStreamEventId = FSEventStreamEventId(
            kFSEventStreamEventIdSinceNow
        ),
        onChange: @escaping @Sendable ([String], [String]?) -> Void
    ) {
        self.paths = paths
        self.sinceWhen = sinceWhen
        self.onChange = onChange
    }

    static func currentEventID() -> FSEventStreamEventId {
        FSEventsGetCurrentEventId()
    }

    func start() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard stream == nil, !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagUseCFTypes
        )

        guard let newStream = FSEventStreamCreate(
            nil,
            { _, contextInfo, eventCount, eventPaths, eventFlags, _ in
                guard let contextInfo else { return }
                let watcher = Unmanaged<RepositoryWatcher>
                    .fromOpaque(contextInfo)
                    .takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
                let flags = Array(UnsafeBufferPointer(
                    start: eventFlags,
                    count: eventCount
                ))
                watcher.repositoryDidChange(paths: paths, flags: flags)
            },
            &context,
            paths as CFArray,
            sinceWhen,
            eventLatency,
            flags
        ) else {
            return
        }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, callbackQueue)
        guard FSEventStreamStart(newStream) else {
            stream = nil
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            return
        }
        KvistRuntimeMetrics.watcherStarted(path: paths[0])
    }

    func stop() {
        stateLock.lock()
        let callback = pendingCallback
        pendingCallback = nil
        pendingPaths = []
        pendingPathsOverflowed = false
        pendingFileTreePaths = []
        pendingCallbackGeneration += 1
        let stream = stream
        self.stream = nil
        stateLock.unlock()

        callback?.cancel()
        if let stream {
            KvistRuntimeMetrics.watcherStopped()
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    deinit {
        stop()
    }

    private func repositoryDidChange(
        paths: [String],
        flags: [FSEventStreamEventFlags]
    ) {
        stateLock.lock()
        guard stream != nil else {
            stateLock.unlock()
            return
        }
        var observedRelevantEvent = false
        for (path, eventFlags) in zip(paths, flags) {
            if Self.shouldIgnore(eventFlags) {
                continue
            }
            observedRelevantEvent = true
            if Self.requiresConservativeRescan(eventFlags) {
                pendingPaths = []
                pendingPathsOverflowed = true
                pendingFileTreePaths = []
                break
            }
            guard !pendingPathsOverflowed else { continue }
            if pendingPaths.count >= maximumPendingPathCount {
                // An event storm only needs one conservative full refresh.
                pendingPaths = []
                pendingPathsOverflowed = true
                pendingFileTreePaths = []
                break
            }
            pendingPaths.insert(path)
            if Self.affectsFileTree(eventFlags) {
                pendingFileTreePaths.insert(path)
            }
        }
        guard observedRelevantEvent else {
            stateLock.unlock()
            return
        }
        pendingCallbackGeneration += 1
        let generation = pendingCallbackGeneration
        let workItem = DispatchWorkItem { [weak self] in
            self?.deliverPendingChanges(generation: generation)
        }
        pendingCallback?.cancel()
        pendingCallback = workItem
        stateLock.unlock()

        callbackQueue.asyncAfter(
            deadline: .now() + burstQuietPeriod,
            execute: workItem
        )
    }

    private func deliverPendingChanges(generation: Int) {
        stateLock.lock()
        guard stream != nil,
              generation == pendingCallbackGeneration else {
            stateLock.unlock()
            return
        }
        let paths = pendingPathsOverflowed ? [] : Array(pendingPaths)
        let fileTreePaths = pendingPathsOverflowed
            ? nil
            : Array(pendingFileTreePaths)
        pendingPaths = []
        pendingPathsOverflowed = false
        pendingFileTreePaths = []
        pendingCallback = nil
        stateLock.unlock()

        onChange(paths, fileTreePaths)
    }

    private static func affectsFileTree(_ flags: FSEventStreamEventFlags) -> Bool {
        let topologyFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed
        )
        return flags & topologyFlags != 0
    }

    private static func shouldIgnore(_ flags: FSEventStreamEventFlags) -> Bool {
        flags & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0
    }

    private static func requiresConservativeRescan(
        _ flags: FSEventStreamEventFlags
    ) -> Bool {
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagEventIdsWrapped
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagMount
                | kFSEventStreamEventFlagUnmount
        )
        return flags & rescanFlags != 0
    }
}
