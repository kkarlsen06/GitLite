import Darwin
import Foundation
import KvistBenchmarkSupport

private struct BenchmarkOptions {
    let appURL: URL
    let outputURL: URL
    let repositories: [(name: String, url: URL)]
    let launchSamples: Int
    let gitSamples: Int
    let externalRefreshSamples: Int
    let eventStormTrials: Int
    let idleSamples: Int
    let idleDurationSeconds: Double
    let settleDurationSeconds: Double
    let launchTimeoutSeconds: Double
    let tabsOnly: Bool

    static func parse(_ arguments: [String]) throws -> BenchmarkOptions {
        var appURL: URL?
        var outputURL: URL?
        var repositories: [(String, URL)] = []
        var launchSamples = 20
        var gitSamples = 30
        var externalRefreshSamples = 30
        var eventStormTrials = 10
        var idleSamples = 5
        var idleDuration = 10.0
        var settleDuration = 5.0
        var launchTimeout = 60.0
        var tabsOnly = false
        var index = 0

        func value(after option: String) throws -> String {
            guard index + 1 < arguments.count else {
                throw BenchmarkError.usage("Missing value after \(option)")
            }
            index += 1
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--app":
                appURL = URL(fileURLWithPath: try value(after: argument))
            case "--output":
                outputURL = URL(fileURLWithPath: try value(after: argument), isDirectory: true)
            case "--repository":
                let repository = try value(after: argument)
                guard let separator = repository.firstIndex(of: "="),
                      separator != repository.startIndex else {
                    throw BenchmarkError.usage(
                        "Repositories use --repository Name=/absolute/path"
                    )
                }
                let name = String(repository[..<separator])
                let path = String(repository[repository.index(after: separator)...])
                repositories.append((name, URL(fileURLWithPath: path, isDirectory: true)))
            case "--launch-samples":
                launchSamples = try positiveInteger(try value(after: argument), option: argument)
            case "--git-samples":
                gitSamples = try positiveInteger(try value(after: argument), option: argument)
            case "--external-refresh-samples":
                externalRefreshSamples = try positiveInteger(
                    try value(after: argument),
                    option: argument
                )
            case "--event-storm-trials":
                eventStormTrials = try positiveInteger(
                    try value(after: argument),
                    option: argument
                )
            case "--idle-samples":
                idleSamples = try positiveInteger(try value(after: argument), option: argument)
            case "--idle-duration":
                idleDuration = try positiveDouble(try value(after: argument), option: argument)
            case "--settle-duration":
                settleDuration = try positiveDouble(try value(after: argument), option: argument)
            case "--launch-timeout":
                launchTimeout = try positiveDouble(try value(after: argument), option: argument)
            case "--tabs-only":
                tabsOnly = true
            case "--help", "-h":
                print(usage)
                exit(EXIT_SUCCESS)
            default:
                throw BenchmarkError.usage("Unknown option: \(argument)")
            }
            index += 1
        }

        guard let appURL, let outputURL, tabsOnly || !repositories.isEmpty else {
            throw BenchmarkError.usage(
                "--app, --output, and at least one --repository are required unless --tabs-only is used"
            )
        }
        if let violation = BenchmarkMinimums.violation(
            launchSamples: launchSamples,
            gitSamples: gitSamples,
            externalRefreshSamples: externalRefreshSamples,
            eventStormTrials: eventStormTrials,
            idleSamples: idleSamples,
            idleDurationSeconds: idleDuration
        ) {
            throw BenchmarkError.usage(violation)
        }

        return BenchmarkOptions(
            appURL: appURL.standardizedFileURL,
            outputURL: outputURL.standardizedFileURL,
            repositories: repositories,
            launchSamples: launchSamples,
            gitSamples: gitSamples,
            externalRefreshSamples: externalRefreshSamples,
            eventStormTrials: eventStormTrials,
            idleSamples: idleSamples,
            idleDurationSeconds: idleDuration,
            settleDurationSeconds: settleDuration,
            launchTimeoutSeconds: launchTimeout,
            tabsOnly: tabsOnly
        )
    }

    private static func positiveInteger(_ value: String, option: String) throws -> Int {
        guard let parsed = Int(value), parsed > 0 else {
            throw BenchmarkError.usage("\(option) requires a positive integer")
        }
        return parsed
    }

    private static func positiveDouble(_ value: String, option: String) throws -> Double {
        guard let parsed = Double(value), parsed > 0 else {
            throw BenchmarkError.usage("\(option) requires a positive number")
        }
        return parsed
    }

    static let usage = """
    Usage: KvistBenchmark --app /path/Kvist.app --output /path/results \\
      --repository GitLite=/path/gitlite \\
      --repository Paeonia=/path/paeonia \\
      --repository Tidex=/path/tidex

    Use --tabs-only for the isolated 20-temporary-repository workload.

    The minimum sample counts are enforced: 20 launches, 30 Git operations,
    30 external refreshes, 10 event storms per repository, and 5 idle intervals
    of at least 10 seconds each.
    """
}

private enum BenchmarkError: LocalizedError {
    case usage(String)
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): return "\(message)\n\n\(BenchmarkOptions.usage)"
        case .failure(let message): return message
        }
    }
}

private struct TimestampEvent: Decodable {
    let uptimeNanoseconds: UInt64
    let repositoryPath: String?
}

private struct GitOperationEvent: Decodable {
    let repositoryPath: String
    let sampleCount: Int
    let workingTreeRefreshMilliseconds: [Double]
    let initialRepositoryLoadingMilliseconds: [Double]
}

private struct ExternalRefreshEvent: Decodable {
    let repositoryPath: String
    let sampleCount: Int
    let eventStormTrialCount: Int
    let eventStormFileCount: Int
    let externalEditToPublicationMilliseconds: [Double]
    let eventStormSettleMilliseconds: [Double]
    let eventStormWriteMilliseconds: [Double]
    let sampleWorkingTreeSnapshotCounts: [Int]
    let sampleFullSnapshotCounts: [Int]
    let eventStormWorkingTreeSnapshotCounts: [Int]
    let eventStormFullSnapshotCounts: [Int]
}

private struct TabRestorationEvent: Decodable {
    let restoredTabCount: Int
    let loadedRepositoryCount: Int
    let inactiveGitCommandCount: Int
    let inactiveWatcherCount: Int
}

private struct TabPhaseEvent: Decodable {
    let loadedRepositoryCount: Int
    let activeWatcherCount: Int
    let activeGitProcessCount: Int
    let outstandingRepositoryTaskCount: Int
}

private struct TabLifecycleEvent: Decodable {
    let restoredTabCount: Int
    let initiallyLoadedRepositoryCount: Int
    let inactiveGitCommandCountBeforeSelection: Int
    let inactiveWatcherCountBeforeSelection: Int
    let initialQuiescentWatcherCount: Int
    let unopenedSwitchMilliseconds: [Double]
    let loadedSwitchMilliseconds: [Double]
    let rapidCycleCount: Int
    let rapidCycleWatcherCount: Int
    let orphanGitProcessCount: Int
    let orphanRepositoryTaskCount: Int
    let maximumMainThreadStallMilliseconds: Double
    let returnedToOriginalTab: Bool
}

private struct BenchmarkReport: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let gitCommit: String
    let gitTreeState: String
    let operatingSystem: String
    let processorCount: Int
    let app: AppArtifactResult
    let configuration: ConfigurationRecord
    let repositories: [RepositoryResult]
    let tabs: TabPerformanceResult
    let guardrails: [GuardrailResult]
}

private struct ConfigurationRecord: Codable {
    let buildConfiguration: String
    let launchSamplesPerRepository: Int
    let gitSamplesPerOperationPerRepository: Int
    let externalRefreshSamplesPerRepository: Int
    let eventStormTrialsPerRepository: Int
    let eventStormFilesPerTrial: Int
    let idleSamplesPerRepository: Int
    let idleDurationSeconds: Double
    let settleDurationSeconds: Double
    let temporaryTabFixtureCount: Int
    let loadedTabSwitchSamples: Int
    let rapidTabCycleCount: Int
}

private struct ProcessResources {
    let userNanoseconds: UInt64
    let systemNanoseconds: UInt64
    let wakeups: UInt64
    let physicalFootprintBytes: UInt64
    let lifetimeMaxPhysicalFootprintBytes: UInt64
}

private struct RunningApp {
    let process: Process
    let startedAtUptimeNanoseconds: UInt64
    let runDirectory: URL
}

@main
private struct KvistBenchmarkMain {
    static func main() {
        do {
            let options = try BenchmarkOptions.parse(Array(CommandLine.arguments.dropFirst()))
            let succeeded = try run(options: options)
            exit(succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(options: BenchmarkOptions) throws -> Bool {
        let executableURL = options.appURL.appendingPathComponent("Contents/MacOS/Kvist")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw BenchmarkError.failure("Release app executable not found at \(executableURL.path)")
        }
        for repository in options.repositories {
            guard FileManager.default.fileExists(atPath: repository.url.appendingPathComponent(".git").path) else {
                throw BenchmarkError.failure("\(repository.name) is not a Git repository: \(repository.url.path)")
            }
        }

        try FileManager.default.createDirectory(
            at: options.outputURL,
            withIntermediateDirectories: true
        )
        let runsURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kvist-performance-runs-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: runsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runsURL) }

        let appResult = try measureArtifacts(appURL: options.appURL)
        let tabFixtureURLs = try createTabFixtures(in: runsURL, count: 20)
        print("[20 tabs] measuring lazy restoration, switching, cycling, memory, and idle use")
        let tabResult = try measureTabs(
            executableURL: executableURL,
            fixtureURLs: tabFixtureURLs,
            runsURL: runsURL,
            settleDuration: options.settleDurationSeconds,
            idleDuration: options.idleDurationSeconds,
            timeout: options.launchTimeoutSeconds
        )
        var repositoryResults: [RepositoryResult] = []

        for repository in options.repositories {
            let fixtureURL = try makeTemporaryRepositoryCopy(
                source: repository.url,
                destination: runsURL
                    .appendingPathComponent("repository-fixtures", isDirectory: true)
                    .appendingPathComponent(repository.name, isDirectory: true)
            )
            let fixture = (name: repository.name, url: fixtureURL)
            print("[\(repository.name)] measuring \(options.gitSamples) samples per Git operation")
            let git = try measureGitOperations(
                executableURL: executableURL,
                repository: fixture,
                sampleCount: options.gitSamples,
                runsURL: runsURL,
                timeout: options.launchTimeoutSeconds * 10
            )

            print(
                "[\(repository.name)] measuring \(options.externalRefreshSamples) " +
                "external refreshes and \(options.eventStormTrials) event storms"
            )
            let externalRefresh = try measureExternalRefreshes(
                executableURL: executableURL,
                repository: fixture,
                sampleCount: options.externalRefreshSamples,
                eventStormTrials: options.eventStormTrials,
                runsURL: runsURL,
                timeout: options.launchTimeoutSeconds * 10
            )

            var launches: [Double] = []
            var startupPeaks: [Double] = []
            for sample in 1...options.launchSamples {
                print("[\(repository.name)] launch \(sample)/\(options.launchSamples)")
                let result = try measureLaunch(
                    executableURL: executableURL,
                    repository: fixture,
                    sample: sample,
                    runsURL: runsURL,
                    timeout: options.launchTimeoutSeconds
                )
                launches.append(result.launchMilliseconds)
                startupPeaks.append(result.startupPeakMiB)
            }

            var settled: [Double] = []
            var idleCPU: [Double] = []
            var idleWakeups: [Double] = []
            for sample in 1...options.idleSamples {
                print(
                    "[\(repository.name)] idle \(sample)/\(options.idleSamples) " +
                    "(\(format(options.idleDurationSeconds)) s)"
                )
                let result = try measureIdle(
                    executableURL: executableURL,
                    repository: fixture,
                    sample: sample,
                    runsURL: runsURL,
                    settleDuration: options.settleDurationSeconds,
                    idleDuration: options.idleDurationSeconds,
                    timeout: options.launchTimeoutSeconds
                )
                settled.append(result.settledMiB)
                idleCPU.append(result.cpuPercent)
                idleWakeups.append(result.wakeupsPerSecond)
            }

            repositoryResults.append(
                RepositoryResult(
                    name: repository.name,
                    path: repository.url.path,
                    launchToInitialFrameMilliseconds: launches,
                    startupPeakPhysicalFootprintMiB: startupPeaks,
                    settledPhysicalFootprintMiB: settled,
                    idleCPUPercent: idleCPU,
                    idleWakeupsPerSecond: idleWakeups,
                    workingTreeRefreshMilliseconds: git.workingTreeRefreshMilliseconds,
                    initialRepositoryLoadingMilliseconds: git.initialRepositoryLoadingMilliseconds,
                    externalEditToPublicationMilliseconds: externalRefresh.externalEditToPublicationMilliseconds,
                    eventStormSettleMilliseconds: externalRefresh.eventStormSettleMilliseconds,
                    eventStormWriteMilliseconds: externalRefresh.eventStormWriteMilliseconds,
                    externalEditWorkingTreeSnapshotCounts: externalRefresh.sampleWorkingTreeSnapshotCounts,
                    externalEditFullSnapshotCounts: externalRefresh.sampleFullSnapshotCounts,
                    eventStormWorkingTreeSnapshotCounts: externalRefresh.eventStormWorkingTreeSnapshotCounts,
                    eventStormFullSnapshotCounts: externalRefresh.eventStormFullSnapshotCounts
                )
            )
        }

        let legacyGuardrails = BenchmarkGuardrails.evaluate(
            app: appResult,
            repositories: repositoryResults
        )
        let guardrails = legacyGuardrails + TabBenchmarkGuardrails.evaluate(tabResult)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let report = BenchmarkReport(
            schemaVersion: 2,
            generatedAt: formatter.string(from: Date()),
            gitCommit: commandOutput("/usr/bin/git", ["rev-parse", "HEAD"]) ?? "unknown",
            gitTreeState: commandOutput("/usr/bin/git", ["status", "--porcelain"])
                .map { $0.isEmpty ? "clean" : "dirty" } ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            processorCount: ProcessInfo.processInfo.processorCount,
            app: appResult,
            configuration: ConfigurationRecord(
                buildConfiguration: "release",
                launchSamplesPerRepository: options.launchSamples,
                gitSamplesPerOperationPerRepository: options.gitSamples,
                externalRefreshSamplesPerRepository: options.externalRefreshSamples,
                eventStormTrialsPerRepository: options.eventStormTrials,
                eventStormFilesPerTrial: BenchmarkMinimums.eventStormFiles,
                idleSamplesPerRepository: options.idleSamples,
                idleDurationSeconds: options.idleDurationSeconds,
                settleDurationSeconds: options.settleDurationSeconds,
                temporaryTabFixtureCount: tabFixtureURLs.count,
                loadedTabSwitchSamples: tabResult.loadedSwitchMilliseconds.count,
                rapidTabCycleCount: tabResult.rapidCycleCount
            ),
            repositories: repositoryResults,
            tabs: tabResult,
            guardrails: guardrails
        )
        try write(report: report, outputURL: options.outputURL)

        let failures = guardrails.filter { !$0.passed }
        print("Raw results: \(options.outputURL.appendingPathComponent("raw-results.json").path)")
        print("Report: \(options.outputURL.appendingPathComponent("report.md").path)")
        if failures.isEmpty {
            print("All performance guardrails passed.")
            return true
        }
        print("\(failures.count) performance guardrail(s) failed.")
        if let failureReport = BenchmarkGuardrails.failureReport(for: guardrails) {
            FileHandle.standardError.write(Data("\(failureReport)\n".utf8))
        }
        return false
    }

    private static func createTabFixtures(in runsURL: URL, count: Int) throws -> [URL] {
        let root = runsURL.appendingPathComponent("tab-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try (0..<count).map { index in
            let repositoryURL = root.appendingPathComponent(
                String(format: "repository-%02d", index + 1),
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: repositoryURL,
                withIntermediateDirectories: true
            )
            try Data("unique fixture \(index + 1)\n".utf8).write(
                to: repositoryURL.appendingPathComponent("fixture.txt"),
                options: .atomic
            )
            try runCommand(executable: "/usr/bin/git", arguments: ["init", "--quiet", repositoryURL.path])
            try runCommand(executable: "/usr/bin/git", arguments: ["-C", repositoryURL.path, "config", "user.name", "Kvist Benchmark"])
            try runCommand(executable: "/usr/bin/git", arguments: ["-C", repositoryURL.path, "config", "user.email", "benchmark@kvist.invalid"])
            try runCommand(executable: "/usr/bin/git", arguments: ["-C", repositoryURL.path, "add", "fixture.txt"])
            try runCommand(executable: "/usr/bin/git", arguments: ["-C", repositoryURL.path, "commit", "--quiet", "-m", "Fixture \(index + 1)"])
            return repositoryURL
        }
    }

    private static func makeTemporaryRepositoryCopy(
        source: URL,
        destination: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try runCommand(
            executable: "/usr/bin/git",
            arguments: [
                "clone",
                "--quiet",
                "--no-hardlinks",
                source.standardizedFileURL.path,
                destination.path
            ]
        )
        try runCommand(
            executable: "/usr/bin/git",
            arguments: ["-C", destination.path, "config", "core.untrackedCache", "false"]
        )
        try runCommand(
            executable: "/usr/bin/git",
            arguments: ["-C", destination.path, "update-index", "--no-untracked-cache"]
        )
        // A checkout and its index can share the same filesystem timestamp,
        // making every read-only status rehash most tracked files as racy-clean.
        // Advance one timestamp tick before recording the clone's settled index.
        Thread.sleep(forTimeInterval: 1.1)
        try runCommand(
            executable: "/usr/bin/git",
            arguments: ["-C", destination.path, "update-index", "--refresh"]
        )
        try runCommand(
            executable: "/usr/bin/git",
            arguments: ["-C", destination.path, "commit-graph", "write", "--reachable"]
        )
        return destination
    }

    private static func measureTabs(
        executableURL: URL,
        fixtureURLs: [URL],
        runsURL: URL,
        settleDuration: Double,
        idleDuration: Double,
        timeout: Double
    ) throws -> TabPerformanceResult {
        guard fixtureURLs.count == 20 else {
            throw BenchmarkError.failure("Tab benchmark requires exactly 20 fixtures")
        }

        let baseline = try launchApp(
            executableURL: executableURL,
            repositoryURL: fixtureURLs[0],
            mode: "idle",
            label: "tabs-single-baseline",
            runsURL: runsURL
        )
        let singleTabFootprint: UInt64
        do {
            let _: TimestampEvent = try waitForJSON(
                at: baseline.runDirectory.appendingPathComponent("repository-loaded.json"),
                process: baseline.process,
                timeout: timeout
            )
            Thread.sleep(forTimeInterval: settleDuration)
            singleTabFootprint = try processResources(
                pid: baseline.process.processIdentifier
            ).physicalFootprintBytes
        } catch {
            stop(baseline.process)
            throw error
        }
        stop(baseline.process)

        let running = try launchApp(
            executableURL: executableURL,
            repositoryURL: fixtureURLs[0],
            mode: "tabs",
            label: "tabs-20",
            runsURL: runsURL,
            tabRepositoryURLs: fixtureURLs
        )
        defer { stop(running.process) }
        let restoration: TabRestorationEvent = try waitForJSON(
            at: running.runDirectory.appendingPathComponent("tabs-restored.json"),
            process: running.process,
            timeout: timeout
        )
        let initial: TabPhaseEvent = try waitForJSON(
            at: running.runDirectory.appendingPathComponent("tabs-initially-ready.json"),
            process: running.process,
            timeout: timeout
        )
        Thread.sleep(forTimeInterval: settleDuration)
        let unopenedFootprint = try processResources(
            pid: running.process.processIdentifier
        ).physicalFootprintBytes
        try signal("continue-after-initial", to: running.runDirectory)

        let allVisited: TabPhaseEvent = try waitForJSON(
            at: running.runDirectory.appendingPathComponent("tabs-all-visited.json"),
            process: running.process,
            timeout: timeout * 10
        )
        Thread.sleep(forTimeInterval: settleDuration)
        let retainedFootprint = try processResources(
            pid: running.process.processIdentifier
        ).physicalFootprintBytes
        try signal("continue-after-all-visited", to: running.runDirectory)

        let beforeRapid: TabPhaseEvent = try waitForJSON(
            at: running.runDirectory.appendingPathComponent("tabs-before-rapid-cycle.json"),
            process: running.process,
            timeout: timeout
        )
        Thread.sleep(forTimeInterval: settleDuration)
        let beforeRapidFootprint = try processResources(
            pid: running.process.processIdentifier
        ).physicalFootprintBytes
        try signal("continue-before-rapid-cycle", to: running.runDirectory)

        let lifecycle: TabLifecycleEvent = try waitForJSON(
            at: running.runDirectory.appendingPathComponent("tabs-result.json"),
            process: running.process,
            timeout: timeout * 10
        )
        guard lifecycle.unopenedSwitchMilliseconds.count == 19,
              lifecycle.loadedSwitchMilliseconds.count == 100,
              lifecycle.rapidCycleCount == 100 else {
            throw BenchmarkError.failure("Tab measurement returned an incomplete sample set")
        }
        Thread.sleep(forTimeInterval: settleDuration)
        let idleBefore = try processResources(pid: running.process.processIdentifier)
        let idleStartedAt = DispatchTime.now().uptimeNanoseconds
        Thread.sleep(forTimeInterval: max(idleDuration, 20))
        let idleFinishedAt = DispatchTime.now().uptimeNanoseconds
        let idleAfter = try processResources(pid: running.process.processIdentifier)
        let idleCPU = (idleAfter.userNanoseconds - idleBefore.userNanoseconds)
            + (idleAfter.systemNanoseconds - idleBefore.systemNanoseconds)
        let elapsedSeconds = Double(idleFinishedAt - idleStartedAt) / 1_000_000_000

        _ = initial
        _ = allVisited
        _ = beforeRapid
        return TabPerformanceResult(
            fixtureCount: restoration.restoredTabCount,
            initiallyLoadedRepositoryCount: lifecycle.initiallyLoadedRepositoryCount,
            inactiveGitCommandCountBeforeSelection: lifecycle.inactiveGitCommandCountBeforeSelection,
            inactiveWatcherCountBeforeSelection: lifecycle.inactiveWatcherCountBeforeSelection,
            initialQuiescentWatcherCount: lifecycle.initialQuiescentWatcherCount,
            unopenedTabsFootprintDeltaMiB: footprintDelta(
                unopenedFootprint,
                relativeTo: singleTabFootprint
            ),
            unopenedSwitchMilliseconds: lifecycle.unopenedSwitchMilliseconds,
            retainedTabsFootprintDeltaMiB: footprintDelta(
                retainedFootprint,
                relativeTo: singleTabFootprint
            ),
            loadedSwitchMilliseconds: lifecycle.loadedSwitchMilliseconds,
            rapidCycleCount: lifecycle.rapidCycleCount,
            rapidCycleWatcherCount: lifecycle.rapidCycleWatcherCount,
            orphanGitProcessCount: lifecycle.orphanGitProcessCount,
            orphanRepositoryTaskCount: lifecycle.orphanRepositoryTaskCount,
            rapidCycleFootprintDeltaMiB: footprintDelta(
                idleBefore.physicalFootprintBytes,
                relativeTo: beforeRapidFootprint
            ),
            maximumMainThreadStallMilliseconds: lifecycle.maximumMainThreadStallMilliseconds,
            returnedToOriginalTab: lifecycle.returnedToOriginalTab,
            idleCPUPercent: Double(idleCPU) / Double(idleFinishedAt - idleStartedAt) * 100,
            idleWakeupsPerSecond: Double(idleAfter.wakeups - idleBefore.wakeups) / elapsedSeconds
        )
    }

    private static func signal(_ name: String, to directory: URL) throws {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            throw BenchmarkError.failure("Could not create benchmark handoff \(url.path)")
        }
    }

    private static func footprintDelta(_ bytes: UInt64, relativeTo baseline: UInt64) -> Double {
        Double(Int64(bytes) - Int64(baseline)) / 1_048_576
    }

    private static func measureArtifacts(appURL: URL) throws -> AppArtifactResult {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            throw BenchmarkError.failure("Could not enumerate \(appURL.path)")
        }
        var bundleBytes: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isRegularFile == true {
                bundleBytes += UInt64(values.fileSize ?? 0)
            }
        }

        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kvist-performance-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zipURL) }
        try runCommand(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--keepParent", appURL.path, zipURL.path]
        )
        let zipValues = try zipURL.resourceValues(forKeys: [.fileSizeKey])
        return AppArtifactResult(
            bundleBytes: bundleBytes,
            compressedBytes: UInt64(zipValues.fileSize ?? 0)
        )
    }

    private static func measureGitOperations(
        executableURL: URL,
        repository: (name: String, url: URL),
        sampleCount: Int,
        runsURL: URL,
        timeout: Double
    ) throws -> GitOperationEvent {
        let running = try launchApp(
            executableURL: executableURL,
            repositoryURL: repository.url,
            mode: "git",
            label: "\(repository.name)-git",
            runsURL: runsURL,
            gitSamples: sampleCount
        )
        defer { stop(running.process) }
        let resultURL = running.runDirectory.appendingPathComponent("git-operations.json")
        let result: GitOperationEvent = try waitForJSON(
            at: resultURL,
            process: running.process,
            timeout: timeout
        )
        guard result.sampleCount == sampleCount,
              result.workingTreeRefreshMilliseconds.count == sampleCount,
              result.initialRepositoryLoadingMilliseconds.count == sampleCount else {
            throw BenchmarkError.failure("Git measurement returned an incomplete sample set")
        }
        return result
    }

    private static func measureExternalRefreshes(
        executableURL: URL,
        repository: (name: String, url: URL),
        sampleCount: Int,
        eventStormTrials: Int,
        runsURL: URL,
        timeout: Double
    ) throws -> ExternalRefreshEvent {
        let running = try launchApp(
            executableURL: executableURL,
            repositoryURL: repository.url,
            mode: "refresh",
            label: "\(repository.name)-external-refresh",
            runsURL: runsURL,
            refreshSamples: sampleCount,
            eventStormTrials: eventStormTrials
        )
        defer { stop(running.process) }
        let result: ExternalRefreshEvent = try waitForJSON(
            at: running.runDirectory.appendingPathComponent("external-refresh.json"),
            process: running.process,
            timeout: timeout
        )
        let resultRepositoryURL = URL(
            fileURLWithPath: result.repositoryPath,
            isDirectory: true
        ).resolvingSymlinksInPath()
        guard resultRepositoryURL == repository.url.resolvingSymlinksInPath(),
              result.sampleCount == sampleCount,
              result.eventStormTrialCount == eventStormTrials,
              result.eventStormFileCount == BenchmarkMinimums.eventStormFiles,
              result.externalEditToPublicationMilliseconds.count == sampleCount,
              result.sampleWorkingTreeSnapshotCounts.count == sampleCount,
              result.sampleFullSnapshotCounts.count == sampleCount,
              result.eventStormSettleMilliseconds.count == eventStormTrials,
              result.eventStormWriteMilliseconds.count == eventStormTrials,
              result.eventStormWorkingTreeSnapshotCounts.count == eventStormTrials,
              result.eventStormFullSnapshotCounts.count == eventStormTrials else {
            throw BenchmarkError.failure(
                "External refresh measurement returned an incomplete sample set: " +
                "repository=\(result.repositoryPath) expectedRepository=" +
                "\(repository.url.standardizedFileURL.path), " +
                "samples=\(result.sampleCount)/\(sampleCount), " +
                "storms=\(result.eventStormTrialCount)/\(eventStormTrials), " +
                "files=\(result.eventStormFileCount)/\(BenchmarkMinimums.eventStormFiles), " +
                "arrays=[edits:\(result.externalEditToPublicationMilliseconds.count), " +
                "sampleWT:\(result.sampleWorkingTreeSnapshotCounts.count), " +
                "sampleFull:\(result.sampleFullSnapshotCounts.count), " +
                "stormSettle:\(result.eventStormSettleMilliseconds.count), " +
                "stormWrite:\(result.eventStormWriteMilliseconds.count), " +
                "stormWT:\(result.eventStormWorkingTreeSnapshotCounts.count), " +
                "stormFull:\(result.eventStormFullSnapshotCounts.count)]"
            )
        }
        return result
    }

    private static func measureLaunch(
        executableURL: URL,
        repository: (name: String, url: URL),
        sample: Int,
        runsURL: URL,
        timeout: Double
    ) throws -> (launchMilliseconds: Double, startupPeakMiB: Double) {
        let running = try launchApp(
            executableURL: executableURL,
            repositoryURL: repository.url,
            mode: "launch",
            label: "\(repository.name)-launch-\(sample)",
            runsURL: runsURL
        )
        defer { stop(running.process) }
        let frame: TimestampEvent = try waitForJSON(
            at: running.runDirectory.appendingPathComponent("initial-frame.json"),
            process: running.process,
            timeout: timeout
        )
        let loaded: TimestampEvent = try waitForJSON(
            at: running.runDirectory.appendingPathComponent("repository-loaded.json"),
            process: running.process,
            timeout: timeout
        )
        guard let loadedRepositoryPath = loaded.repositoryPath,
              URL(fileURLWithPath: loadedRepositoryPath, isDirectory: true)
                .resolvingSymlinksInPath()
                == repository.url.resolvingSymlinksInPath() else {
            throw BenchmarkError.failure("Kvist loaded the wrong repository during launch")
        }
        let resources = try processResources(pid: running.process.processIdentifier)
        return (
            Double(frame.uptimeNanoseconds - running.startedAtUptimeNanoseconds) / 1_000_000,
            mebibytes(resources.lifetimeMaxPhysicalFootprintBytes)
        )
    }

    private static func measureIdle(
        executableURL: URL,
        repository: (name: String, url: URL),
        sample: Int,
        runsURL: URL,
        settleDuration: Double,
        idleDuration: Double,
        timeout: Double
    ) throws -> (settledMiB: Double, cpuPercent: Double, wakeupsPerSecond: Double) {
        let running = try launchApp(
            executableURL: executableURL,
            repositoryURL: repository.url,
            mode: "idle",
            label: "\(repository.name)-idle-\(sample)",
            runsURL: runsURL
        )
        defer { stop(running.process) }
        let _: TimestampEvent = try waitForJSON(
            at: running.runDirectory.appendingPathComponent("initial-frame.json"),
            process: running.process,
            timeout: timeout
        )
        let _: TimestampEvent = try waitForJSON(
            at: running.runDirectory.appendingPathComponent("repository-loaded.json"),
            process: running.process,
            timeout: timeout
        )
        Thread.sleep(forTimeInterval: settleDuration)
        let before = try processResources(pid: running.process.processIdentifier)
        let intervalStart = DispatchTime.now().uptimeNanoseconds
        Thread.sleep(forTimeInterval: idleDuration)
        let intervalEnd = DispatchTime.now().uptimeNanoseconds
        let after = try processResources(pid: running.process.processIdentifier)
        let elapsedSeconds = Double(intervalEnd - intervalStart) / 1_000_000_000
        let cpuNanoseconds = (after.userNanoseconds - before.userNanoseconds)
            + (after.systemNanoseconds - before.systemNanoseconds)
        return (
            mebibytes(before.physicalFootprintBytes),
            Double(cpuNanoseconds) / Double(intervalEnd - intervalStart) * 100,
            Double(after.wakeups - before.wakeups) / elapsedSeconds
        )
    }

    private static func launchApp(
        executableURL: URL,
        repositoryURL: URL,
        mode: String,
        label: String,
        runsURL: URL,
        gitSamples: Int? = nil,
        refreshSamples: Int? = nil,
        eventStormTrials: Int? = nil,
        tabRepositoryURLs: [URL]? = nil
    ) throws -> RunningApp {
        let runDirectory = runsURL.appendingPathComponent(label, isDirectory: true)
        if FileManager.default.fileExists(atPath: runDirectory.path) {
            try FileManager.default.removeItem(at: runDirectory)
        }
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = executableURL
        var environment = ProcessInfo.processInfo.environment
        environment["KVIST_PERFORMANCE_MODE"] = mode
        environment["KVIST_PERFORMANCE_REPOSITORY"] = repositoryURL.standardizedFileURL.path
        environment["KVIST_PERFORMANCE_OUTPUT"] = runDirectory.path
        if let gitSamples {
            environment["KVIST_PERFORMANCE_GIT_SAMPLES"] = String(gitSamples)
        }
        if let refreshSamples {
            environment["KVIST_PERFORMANCE_REFRESH_SAMPLES"] = String(refreshSamples)
        }
        if let eventStormTrials {
            environment["KVIST_PERFORMANCE_STORM_TRIALS"] = String(eventStormTrials)
        }
        if let tabRepositoryURLs {
            environment["KVIST_PERFORMANCE_TAB_REPOSITORIES"] = tabRepositoryURLs
                .map { $0.standardizedFileURL.path }
                .joined(separator: "\n")
        }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let start = DispatchTime.now().uptimeNanoseconds
        try process.run()
        return RunningApp(
            process: process,
            startedAtUptimeNanoseconds: start,
            runDirectory: runDirectory
        )
    }

    private static func waitForJSON<Value: Decodable>(
        at url: URL,
        process: Process,
        timeout: Double
    ) throws -> Value {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let value = try? JSONDecoder().decode(Value.self, from: data) {
                return value
            }
            if !process.isRunning {
                let errorURL = url.deletingLastPathComponent().appendingPathComponent("error.txt")
                let detail = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? "no error detail"
                throw BenchmarkError.failure(
                    "Kvist exited before producing \(url.lastPathComponent): \(detail)"
                )
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw BenchmarkError.failure("Timed out waiting for \(url.lastPathComponent)")
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private static func processResources(pid: pid_t) throws -> ProcessResources {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pid_rusage(
                pid,
                RUSAGE_INFO_V4,
                UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self)
            )
        }
        guard result == 0 else {
            throw BenchmarkError.failure("proc_pid_rusage failed for pid \(pid): errno \(errno)")
        }
        return ProcessResources(
            userNanoseconds: info.ri_user_time,
            systemNanoseconds: info.ri_system_time,
            wakeups: info.ri_pkg_idle_wkups + info.ri_interrupt_wkups,
            physicalFootprintBytes: info.ri_phys_footprint,
            lifetimeMaxPhysicalFootprintBytes: info.ri_lifetime_max_phys_footprint
        )
    }

    private static func write(report: BenchmarkReport, outputURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let rawData = try encoder.encode(report)
        try rawData.write(to: outputURL.appendingPathComponent("raw-results.json"), options: .atomic)
        try markdown(report: report).write(
            to: outputURL.appendingPathComponent("report.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func markdown(report: BenchmarkReport) -> String {
        var lines = [
            "# Kvist release performance report",
            "",
            "Generated: \(report.generatedAt)  ",
            "Commit: `\(report.gitCommit)` (\(report.gitTreeState))  ",
            "System: \(report.operatingSystem), \(report.processorCount) logical CPUs  ",
            "Build: release",
            "",
            "Raw machine-readable samples are in [`raw-results.json`](raw-results.json).",
            "",
            "## Guardrails",
            "",
            "| Status | Repository | Metric | Statistic | Measured | Limit |",
            "| --- | --- | --- | --- | ---: | ---: |"
        ]
        for guardrail in report.guardrails {
            lines.append(
                "| \(guardrail.passed ? "PASS" : "FAIL") | " +
                "\(guardrail.repository ?? "All") | \(guardrail.name) | " +
                "\(guardrail.statistic) | \(format(guardrail.measured)) \(guardrail.unit) | " +
                "\(guardrail.comparison.symbol) \(format(guardrail.limit)) \(guardrail.unit) |"
            )
        }

        lines += [
            "",
            "## Summary",
            "",
            "| Repository | Metric | Samples | Median | p95 |",
            "| --- | --- | ---: | ---: | ---: |",
            "| All | App bundle | 1 | \(format(mebibytes(report.app.bundleBytes))) MiB | \(format(mebibytes(report.app.bundleBytes))) MiB |",
            "| All | Compressed app | 1 | \(format(mebibytes(report.app.compressedBytes))) MiB | \(format(mebibytes(report.app.compressedBytes))) MiB |",
            "| 20 tabs | Unopened-tab footprint delta | 1 | \(format(report.tabs.unopenedTabsFootprintDeltaMiB)) MiB | \(format(report.tabs.unopenedTabsFootprintDeltaMiB)) MiB |",
            "| 20 tabs | Unopened-tab switch | \(report.tabs.unopenedSwitchMilliseconds.count) | \(format(median(report.tabs.unopenedSwitchMilliseconds))) ms | \(format(percentile95(report.tabs.unopenedSwitchMilliseconds))) ms |",
            "| 20 tabs | Loaded-tab switch | \(report.tabs.loadedSwitchMilliseconds.count) | \(format(median(report.tabs.loadedSwitchMilliseconds))) ms | \(format(percentile95(report.tabs.loadedSwitchMilliseconds))) ms |",
            "| 20 tabs | Retained state footprint delta | 1 | \(format(report.tabs.retainedTabsFootprintDeltaMiB)) MiB | \(format(report.tabs.retainedTabsFootprintDeltaMiB)) MiB |",
            "| 20 tabs | Rapid-cycle footprint delta | 1 | \(format(report.tabs.rapidCycleFootprintDeltaMiB)) MiB | \(format(report.tabs.rapidCycleFootprintDeltaMiB)) MiB |",
            "| 20 tabs | Maximum main-thread stall | 1 | \(format(report.tabs.maximumMainThreadStallMilliseconds)) ms | \(format(report.tabs.maximumMainThreadStallMilliseconds)) ms |",
            "| 20 tabs | Idle CPU | 1 | \(format(report.tabs.idleCPUPercent)) % | \(format(report.tabs.idleCPUPercent)) % |",
            "| 20 tabs | Idle wakeups | 1 | \(format(report.tabs.idleWakeupsPerSecond)) /s | \(format(report.tabs.idleWakeupsPerSecond)) /s |"
        ]
        for repository in report.repositories {
            let metrics: [(String, [Double], String)] = [
                ("Launch to initial frame", repository.launchToInitialFrameMilliseconds, "ms"),
                ("Startup peak physical footprint", repository.startupPeakPhysicalFootprintMiB, "MiB"),
                ("Settled physical footprint", repository.settledPhysicalFootprintMiB, "MiB"),
                ("Idle CPU", repository.idleCPUPercent, "%"),
                ("Idle wakeups", repository.idleWakeupsPerSecond, "/s"),
                ("Working-tree refresh", repository.workingTreeRefreshMilliseconds, "ms"),
                ("Initial repository loading", repository.initialRepositoryLoadingMilliseconds, "ms"),
                ("External edit to publication", repository.externalEditToPublicationMilliseconds, "ms"),
                ("Event storm settle", repository.eventStormSettleMilliseconds, "ms"),
                ("Event storm writes", repository.eventStormWriteMilliseconds, "ms")
            ]
            for metric in metrics {
                lines.append(
                    "| \(repository.name) | \(metric.0) | \(metric.1.count) | " +
                    "\(format(median(metric.1))) \(metric.2) | " +
                    "\(format(percentile95(metric.1))) \(metric.2) |"
                )
            }
        }

        lines += [
            "",
            "## Raw samples",
            "",
            "### 20 tabs",
            "",
            "- Unopened-tab switch (ms): \(report.tabs.unopenedSwitchMilliseconds.map(format).joined(separator: ", "))",
            "",
            "- Loaded-tab switch (ms): \(report.tabs.loadedSwitchMilliseconds.map(format).joined(separator: ", "))",
            ""
        ]
        for repository in report.repositories {
            lines += ["### \(repository.name)", ""]
            let metrics: [(String, [Double], String)] = [
                ("Launch to initial frame", repository.launchToInitialFrameMilliseconds, "ms"),
                ("Startup peak physical footprint", repository.startupPeakPhysicalFootprintMiB, "MiB"),
                ("Settled physical footprint", repository.settledPhysicalFootprintMiB, "MiB"),
                ("Idle CPU", repository.idleCPUPercent, "%"),
                ("Idle wakeups", repository.idleWakeupsPerSecond, "/s"),
                ("Working-tree refresh", repository.workingTreeRefreshMilliseconds, "ms"),
                ("Initial repository loading", repository.initialRepositoryLoadingMilliseconds, "ms"),
                ("External edit to publication", repository.externalEditToPublicationMilliseconds, "ms"),
                ("Event storm settle", repository.eventStormSettleMilliseconds, "ms"),
                ("Event storm writes", repository.eventStormWriteMilliseconds, "ms"),
                ("External edit working-tree snapshots", repository.externalEditWorkingTreeSnapshotCounts.map(Double.init), "count"),
                ("External edit full snapshots", repository.externalEditFullSnapshotCounts.map(Double.init), "count"),
                ("Event storm working-tree snapshots", repository.eventStormWorkingTreeSnapshotCounts.map(Double.init), "count"),
                ("Event storm full snapshots", repository.eventStormFullSnapshotCounts.map(Double.init), "count")
            ]
            for metric in metrics {
                lines.append("- \(metric.0) (\(metric.2)): \(metric.1.map(format).joined(separator: ", "))")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func runCommand(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BenchmarkError.failure("Command failed: \(executable) \(arguments.joined(separator: " "))")
        }
    }

    private static func commandOutput(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
