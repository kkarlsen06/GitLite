import Darwin
import Foundation
import KvistBenchmarkSupport

private enum HistoryRunnerError: LocalizedError {
    case usage(String)
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            return "\(message)\n\nUsage: KvistHistoryBenchmark --app /path/Kvist.app --output /path/results"
        case .failure(let message):
            return message
        }
    }
}

private struct Options {
    let appURL: URL
    let outputURL: URL

    static func parse(_ arguments: [String]) throws -> Options {
        var appURL: URL?
        var outputURL: URL?
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard option == "--app" || option == "--output" else {
                throw HistoryRunnerError.usage("Unknown option: \(option)")
            }
            guard index + 1 < arguments.count else {
                throw HistoryRunnerError.usage("Missing value after \(option)")
            }
            index += 1
            let value = URL(fileURLWithPath: arguments[index])
            if option == "--app" { appURL = value } else { outputURL = value }
            index += 1
        }
        guard let appURL, let outputURL else {
            throw HistoryRunnerError.usage("--app and --output are required")
        }
        return Options(
            appURL: appURL.standardizedFileURL,
            outputURL: outputURL.standardizedFileURL
        )
    }
}

private struct Fixture {
    let repositoryURL: URL
    let result: HistoryFixtureResult
}

@main
private struct KvistHistoryBenchmarkMain {
    static func main() {
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            exit(try run(options) ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ options: Options) throws -> Bool {
        let executableURL = options.appURL.appendingPathComponent("Contents/MacOS/Kvist")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw HistoryRunnerError.failure("Release app not found at \(executableURL.path)")
        }
        try FileManager.default.createDirectory(
            at: options.outputURL,
            withIntermediateDirectories: true
        )
        for artifact in ["history.json", "error.txt", "raw-results.json", "report.md"] {
            try? FileManager.default.removeItem(
                at: options.outputURL.appendingPathComponent(artifact)
            )
        }

        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Kvist-History-Benchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let fixture = try createFixture(at: temporaryURL.appendingPathComponent("fixture"))

        let process = Process()
        process.executableURL = executableURL
        process.environment = ProcessInfo.processInfo.environment.merging([
            "KVIST_PERFORMANCE_MODE": "history",
            "KVIST_PERFORMANCE_REPOSITORY": fixture.repositoryURL.path,
            "KVIST_PERFORMANCE_OUTPUT": options.outputURL.path,
            "KVIST_HISTORY_FIXTURE_COMMITS": "\(fixture.result.commitCount)",
            "KVIST_HISTORY_FIXTURE_MERGES": "\(fixture.result.mergeCommitCount)",
            "KVIST_HISTORY_FIXTURE_BRANCHES": "\(fixture.result.branchCount)",
            "KVIST_HISTORY_FIXTURE_TAGS": "\(fixture.result.tagCount)"
        ]) { _, benchmark in benchmark }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let resultURL = options.outputURL.appendingPathComponent("history.json")
        let deadline = Date().addingTimeInterval(900)
        while !FileManager.default.fileExists(atPath: resultURL.path),
              process.isRunning,
              Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard FileManager.default.fileExists(atPath: resultURL.path) else {
            let errorURL = options.outputURL.appendingPathComponent("error.txt")
            let detail = (try? String(contentsOf: errorURL, encoding: .utf8))
                ?? (Date() >= deadline
                    ? "History benchmark timed out after 900 seconds"
                    : "Kvist exited before producing history results")
            throw HistoryRunnerError.failure(detail)
        }

        let history = try JSONDecoder().decode(
            HistoryPerformanceResult.self,
            from: Data(contentsOf: resultURL)
        )
        guard history.fixture == fixture.result else {
            throw HistoryRunnerError.failure("App and runner fixture metadata disagree")
        }
        let app = try measureArtifacts(options.appURL)
        let guardrails = HistoryBenchmarkGuardrails.evaluate(app: app, history: history)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let report = HistoryBenchmarkReport(
            schemaVersion: 1,
            generatedAt: formatter.string(from: Date()),
            gitCommit: commandOutput("/usr/bin/git", ["rev-parse", "HEAD"]) ?? "unknown",
            gitTreeState: commandOutput("/usr/bin/git", ["status", "--porcelain"])
                .map { $0.isEmpty ? "clean" : "dirty" } ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            app: app,
            history: history,
            guardrails: guardrails
        )
        try write(report, to: options.outputURL)

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        let failures = guardrails.filter { !$0.passed }
        print("Raw results: \(options.outputURL.appendingPathComponent("raw-results.json").path)")
        print("Report: \(options.outputURL.appendingPathComponent("report.md").path)")
        if failures.isEmpty {
            print("All large-history performance guardrails passed.")
            return true
        }
        if let failureReport = BenchmarkGuardrails.failureReport(for: guardrails) {
            FileHandle.standardError.write(Data("\(failureReport)\n".utf8))
        }
        return false
    }

    private static func createFixture(at repositoryURL: URL) throws -> Fixture {
        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )
        try runCommand("/usr/bin/git", ["init", "--quiet", "-b", "main", repositoryURL.path])

        let process = Process()
        let input = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repositoryURL.path, "fast-import", "--quiet"]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()

        let writer = FastImportWriter(handle: input.fileHandleForWriting)
        var timestamp = 1_700_000_000
        try writer.commit(
            reference: "refs/heads/main",
            mark: 1,
            timestamp: timestamp,
            message: "Initial fixture commit",
            parent: nil,
            merge: nil,
            files: [("fixture.txt", "initial\n")]
        )

        var sideMarks: [Int] = []
        sideMarks.reserveCapacity(1_000)
        var nextMark = 2
        for branch in 0..<500 {
            let reference = String(format: "refs/heads/fixture/branch-%03d", branch)
            var parent = 1
            for version in 0..<2 {
                timestamp += 1
                let mark = nextMark
                nextMark += 1
                try writer.commit(
                    reference: reference,
                    mark: mark,
                    timestamp: timestamp,
                    message: String(format: "Branch %03d commit %d", branch, version + 1),
                    parent: parent,
                    merge: nil,
                    files: [(
                        String(format: "branches/branch-%03d.txt", branch),
                        "version \(version + 1)\n"
                    )]
                )
                sideMarks.append(mark)
                parent = mark
            }
        }

        timestamp = 1_700_010_000
        var mainParent = 1
        for index in 1...19_000 {
            timestamp += 1
            let mark = nextMark
            nextMark += 1
            let mergeMark = index.isMultiple(of: 19)
                ? sideMarks[(index / 19) - 1]
                : nil
            var files: [(String, String)] = []
            if index == 19_000 {
                files.reserveCapacity(1_000)
                for file in 0..<1_000 {
                    files.append((
                        String(format: "expanded/file-%04d.txt", file),
                        "file \(file)\n"
                    ))
                }
            } else {
                files.append(("history.txt", "commit \(index)\n"))
            }
            try writer.commit(
                reference: "refs/heads/main",
                mark: mark,
                timestamp: timestamp,
                message: index == 19_000 ? "Expansion fixture" : "Main commit \(index)",
                parent: mainParent,
                merge: mergeMark,
                files: files
            )
            mainParent = mark
        }

        for branch in 0..<500 {
            try writer.reset(
                String(format: "refs/heads/fixture/branch-%03d", branch),
                to: mainParent
            )
        }
        for tag in 0..<500 {
            try writer.reset(String(format: "refs/tags/fixture-%03d", tag), to: mainParent)
        }
        try writer.finish()
        process.waitUntilExit()
        let errorText = String(
            bytes: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            throw HistoryRunnerError.failure("git fast-import failed: \(errorText)")
        }

        try runCommand("/usr/bin/git", ["-C", repositoryURL.path, "reset", "--hard", "--quiet", "main"])
        let commits = try integerOutput(["-C", repositoryURL.path, "rev-list", "--all", "--count"])
        let merges = try integerOutput([
            "-C", repositoryURL.path, "rev-list", "--all", "--min-parents=2", "--count"
        ])
        let branches = try integerOutput([
            "-C", repositoryURL.path, "for-each-ref", "--count=100000", "--format=%(refname)",
            "refs/heads"
        ], countLines: true)
        let tags = try integerOutput([
            "-C", repositoryURL.path, "for-each-ref", "--count=100000", "--format=%(refname)",
            "refs/tags"
        ], countLines: true)
        let changedFiles = try integerOutput([
            "-C", repositoryURL.path, "diff", "--name-only", "HEAD^1", "HEAD"
        ], countLines: true)
        let result = HistoryFixtureResult(
            commitCount: commits,
            mergeCommitCount: merges,
            branchCount: branches,
            tagCount: tags,
            expandedCommitFileCount: changedFiles
        )
        guard commits >= 20_000, merges >= 1_000, branches >= 500,
              tags >= 500, changedFiles == 1_000 else {
            throw HistoryRunnerError.failure("Generated history fixture failed validation: \(result)")
        }
        return Fixture(repositoryURL: repositoryURL, result: result)
    }

    private static func integerOutput(
        _ arguments: [String],
        countLines: Bool = false
    ) throws -> Int {
        guard let output = commandOutput("/usr/bin/git", arguments) else {
            throw HistoryRunnerError.failure("Could not validate generated fixture")
        }
        if countLines {
            return output.split(whereSeparator: \.isNewline).count
        }
        guard let value = Int(output) else {
            throw HistoryRunnerError.failure("Expected integer from git, received \(output)")
        }
        return value
    }

    private static func measureArtifacts(_ appURL: URL) throws -> AppArtifactResult {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: Array(keys)
        ) else {
            throw HistoryRunnerError.failure("Could not enumerate \(appURL.path)")
        }
        var bundleBytes: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isRegularFile == true {
                bundleBytes += UInt64(values.fileSize ?? 0)
            }
        }
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Kvist-History-Artifact-\(UUID().uuidString).zip"
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }
        try runCommand("/usr/bin/ditto", ["-c", "-k", "--keepParent", appURL.path, zipURL.path])
        let compressedBytes = try zipURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return AppArtifactResult(
            bundleBytes: bundleBytes,
            compressedBytes: UInt64(compressedBytes)
        )
    }

    private static func write(_ report: HistoryBenchmarkReport, to outputURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(
            to: outputURL.appendingPathComponent("raw-results.json"),
            options: .atomic
        )
        var markdown = "# Kvist large-history performance benchmark\n\n"
        markdown += "Generated: \(report.generatedAt)  \n"
        markdown += "Commit: `\(report.gitCommit)` (\(report.gitTreeState))  \n"
        markdown += "System: \(report.operatingSystem)\n\n"
        markdown += "| Guardrail | Statistic | Measured | Required | Result |\n"
        markdown += "| --- | --- | ---: | ---: | :---: |\n"
        for guardrail in report.guardrails {
            markdown += "| \(guardrail.name) | \(guardrail.statistic) | "
            markdown += "\(format(guardrail.measured)) \(guardrail.unit) | "
            markdown += "\(guardrail.comparison.symbol) \(format(guardrail.limit)) "
            markdown += "\(guardrail.unit) | \(guardrail.passed ? "Pass" : "Fail") |\n"
        }
        markdown += "\n## Raw samples\n\n"
        markdown += "- Initial history (ms): \(samples(report.history.initialHistoryQueryMilliseconds))\n"
        markdown += "- Open to graph (ms): \(samples(report.history.repositoryOpenToRenderedGraphMilliseconds))\n"
        markdown += "- Pagination (ms): \(samples(report.history.paginationMilliseconds))\n"
        markdown += "- Scope switch (ms): \(samples(report.history.scopeSwitchMilliseconds))\n"
        markdown += "- Reference parse/display (ms): \(samples(report.history.referenceParseAndDisplayMilliseconds))\n"
        markdown += "- 5,000-row footprint deltas (MiB): \(samples(report.history.fiveThousandRowFootprintDeltaMiB))\n"
        markdown += "- Commit expansion (ms): \(samples(report.history.commitExpansionMilliseconds))\n"
        try markdown.write(
            to: outputURL.appendingPathComponent("report.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func samples(_ values: [Double]) -> String {
        values.map(format).joined(separator: ", ")
    }

    private static func commandOutput(_ executable: String, _ arguments: [String]) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(
                bytes: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func runCommand(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HistoryRunnerError.failure(
                "Command failed (\(process.terminationStatus)): \(executable) "
                    + arguments.joined(separator: " ")
            )
        }
    }
}

private final class FastImportWriter {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
        buffer.reserveCapacity(1_048_576)
    }

    func commit(
        reference: String,
        mark: Int,
        timestamp: Int,
        message: String,
        parent: Int?,
        merge: Int?,
        files: [(String, String)]
    ) throws {
        append("commit \(reference)\nmark :\(mark)\n")
        append("author Kvist Benchmark <benchmark@kvist.invalid> \(timestamp) +0000\n")
        append("committer Kvist Benchmark <benchmark@kvist.invalid> \(timestamp) +0000\n")
        appendData(message)
        if let parent { append("from :\(parent)\n") }
        if let merge { append("merge :\(merge)\n") }
        for (path, contents) in files {
            append("M 100644 inline \(path)\n")
            appendData(contents)
        }
        append("\n")
        try flushIfNeeded()
    }

    func reset(_ reference: String, to mark: Int) throws {
        append("reset \(reference)\nfrom :\(mark)\n\n")
        try flushIfNeeded()
    }

    func finish() throws {
        append("done\n")
        try flush()
        try handle.close()
    }

    private func appendData(_ value: String) {
        let data = Data(value.utf8)
        append("data \(data.count)\n")
        buffer.append(data)
        append("\n")
    }

    private func append(_ value: String) {
        buffer.append(contentsOf: value.utf8)
    }

    private func flushIfNeeded() throws {
        if buffer.count >= 1_048_576 { try flush() }
    }

    private func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}
