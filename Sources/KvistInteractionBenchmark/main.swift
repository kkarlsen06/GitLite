import Darwin
import Foundation
import KvistBenchmarkSupport

private enum InteractionRunnerError: LocalizedError {
    case usage(String)
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            return "\(message)\n\nUsage: KvistInteractionBenchmark --app /path/Kvist.app --output /path/results"
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
            let argument = arguments[index]
            guard argument == "--app" || argument == "--output" else {
                throw InteractionRunnerError.usage("Unknown option: \(argument)")
            }
            guard index + 1 < arguments.count else {
                throw InteractionRunnerError.usage("Missing value after \(argument)")
            }
            index += 1
            let value = URL(fileURLWithPath: arguments[index])
            if argument == "--app" {
                appURL = value
            } else {
                outputURL = value
            }
            index += 1
        }
        guard let appURL, let outputURL else {
            throw InteractionRunnerError.usage("--app and --output are required")
        }
        return Options(
            appURL: appURL.standardizedFileURL,
            outputURL: outputURL.standardizedFileURL
        )
    }
}

@main
private struct KvistInteractionBenchmarkMain {
    static func main() {
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            let passed = try run(options)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ options: Options) throws -> Bool {
        let executableURL = options.appURL.appendingPathComponent("Contents/MacOS/Kvist")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw InteractionRunnerError.failure(
                "Release app executable not found at \(executableURL.path)"
            )
        }
        try FileManager.default.createDirectory(
            at: options.outputURL,
            withIntermediateDirectories: true
        )
        for artifact in ["interactions.json", "error.txt", "raw-results.json", "report.md"] {
            try? FileManager.default.removeItem(
                at: options.outputURL.appendingPathComponent(artifact)
            )
        }

        let runURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Kvist-Interaction-Benchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: runURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runURL) }
        let repositoryURL = try createFixture(at: runURL.appendingPathComponent("fixture"))

        let process = Process()
        process.executableURL = executableURL
        process.environment = ProcessInfo.processInfo.environment.merging([
            "KVIST_PERFORMANCE_MODE": "interaction",
            "KVIST_PERFORMANCE_REPOSITORY": repositoryURL.path,
            "KVIST_PERFORMANCE_OUTPUT": options.outputURL.path
        ]) { _, benchmark in benchmark }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let resultURL = options.outputURL.appendingPathComponent("interactions.json")
        let deadline = Date().addingTimeInterval(300)
        while !FileManager.default.fileExists(atPath: resultURL.path),
              process.isRunning,
              Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard FileManager.default.fileExists(atPath: resultURL.path) else {
            let detail: String
            let errorURL = options.outputURL.appendingPathComponent("error.txt")
            if let data = try? Data(contentsOf: errorURL),
               let message = String(data: data, encoding: .utf8) {
                detail = message
            } else if Date() >= deadline {
                detail = "Interaction benchmark timed out after 300 seconds"
            } else {
                detail = "Kvist exited before producing interaction results"
            }
            throw InteractionRunnerError.failure(detail)
        }

        let interactions = try JSONDecoder().decode(
            InteractionPerformanceResult.self,
            from: Data(contentsOf: resultURL)
        )
        let app = try measureArtifacts(options.appURL)
        let guardrails = InteractionBenchmarkGuardrails.evaluate(
            app: app,
            interactions: interactions
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let report = InteractionBenchmarkReport(
            schemaVersion: 1,
            generatedAt: formatter.string(from: Date()),
            gitCommit: commandOutput("/usr/bin/git", ["rev-parse", "HEAD"]) ?? "unknown",
            gitTreeState: commandOutput("/usr/bin/git", ["status", "--porcelain"])
                .map { $0.isEmpty ? "clean" : "dirty" } ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            app: app,
            interactions: interactions,
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
            print("All interaction performance guardrails passed.")
            return true
        }
        if let failureReport = BenchmarkGuardrails.failureReport(for: guardrails) {
            FileHandle.standardError.write(Data("\(failureReport)\n".utf8))
        }
        return false
    }

    private static func createFixture(at repositoryURL: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )

        let maximumLine = Data((String(repeating: "x", count: 255) + "\n").utf8)
        var maximumSource = Data(capacity: InteractionBenchmarkLimits.maximumSourceFileBytes)
        for _ in 0..<4_096 {
            maximumSource.append(maximumLine)
        }
        guard maximumSource.count == InteractionBenchmarkLimits.maximumSourceFileBytes else {
            throw InteractionRunnerError.failure("Maximum-size source fixture is malformed")
        }
        try maximumSource.write(
            to: repositoryURL.appendingPathComponent("maximum-source.swift"),
            options: .atomic
        )

        let largeLines = (1...InteractionBenchmarkLimits.largeSourceLineCount)
            .map { "let line\($0) = \($0)" }
            .joined(separator: "\n")
        try Data(largeLines.utf8).write(
            to: repositoryURL.appendingPathComponent("twenty-thousand-lines.swift"),
            options: .atomic
        )
        try Data(String(
            repeating: "l",
            count: InteractionBenchmarkLimits.longestSourceLineCharacters
        ).utf8).write(
            to: repositoryURL.appendingPathComponent("twenty-thousand-character-line.swift"),
            options: .atomic
        )

        let changedLinesPerSide = InteractionBenchmarkLimits.largeDiffChangedLineCount / 2
        let original = (1...changedLinesPerSide)
            .map { "let original\($0) = \($0)" }
            .joined(separator: "\n") + "\n"
        let changed = (1...changedLinesPerSide)
            .map { "let changed\($0) = \($0 + changedLinesPerSide)" }
            .joined(separator: "\n") + "\n"
        let diffURL = repositoryURL.appendingPathComponent("large-diff.swift")
        try Data(original.utf8).write(to: diffURL, options: .atomic)

        try runCommand("/usr/bin/git", ["init", "--quiet", "-b", "main", repositoryURL.path])
        try runCommand("/usr/bin/git", ["-C", repositoryURL.path, "config", "user.name", "Kvist Benchmark"])
        try runCommand("/usr/bin/git", ["-C", repositoryURL.path, "config", "user.email", "benchmark@kvist.invalid"])
        try runCommand("/usr/bin/git", ["-C", repositoryURL.path, "add", "."])
        try runCommand("/usr/bin/git", ["-C", repositoryURL.path, "commit", "--quiet", "-m", "Interaction fixture"])
        try Data(changed.utf8).write(to: diffURL, options: .atomic)
        return repositoryURL
    }

    private static func measureArtifacts(_ appURL: URL) throws -> AppArtifactResult {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: Array(keys)
        ) else {
            throw InteractionRunnerError.failure("Could not enumerate \(appURL.path)")
        }
        var bundleBytes: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isRegularFile == true {
                bundleBytes += UInt64(values.fileSize ?? 0)
            }
        }

        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Kvist-Interaction-Artifact-\(UUID().uuidString).zip"
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }
        try runCommand("/usr/bin/ditto", ["-c", "-k", "--keepParent", appURL.path, zipURL.path])
        let compressedBytes = try zipURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return AppArtifactResult(
            bundleBytes: bundleBytes,
            compressedBytes: UInt64(compressedBytes)
        )
    }

    private static func write(
        _ report: InteractionBenchmarkReport,
        to outputURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(
            to: outputURL.appendingPathComponent("raw-results.json"),
            options: .atomic
        )

        var markdown = "# Kvist interaction performance benchmark\n\n"
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
        markdown += "- Maximum source open (ms): \(sampleList(report.interactions.maximumSourceOpenMilliseconds))\n"
        markdown += "- 20,000-character line open (ms): \(sampleList(report.interactions.largeLineOpenMilliseconds))\n"
        markdown += "- Large diff open (ms): \(sampleList(report.interactions.largeDiffOpenMilliseconds))\n"
        markdown += "- Typing input-to-display (ms): \(sampleList(report.interactions.typingInputToDisplayMilliseconds))\n"
        markdown += "- Near-end line jump (ms): \(sampleList(report.interactions.lineJumpMilliseconds))\n"
        try markdown.write(
            to: outputURL.appendingPathComponent("report.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func sampleList(_ values: [Double]) -> String {
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
            throw InteractionRunnerError.failure(
                "Command failed (\(process.terminationStatus)): \(executable) " +
                    arguments.joined(separator: " ")
            )
        }
    }
}
