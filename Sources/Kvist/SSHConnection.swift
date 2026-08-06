import Foundation

enum SSHConnection {
    static let executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
    static let controlPersistSeconds = 120

    private static let controlDirectory: URL? = {
        guard let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }

        let directory = cachesDirectory
            .appendingPathComponent("Kvist/SSH", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            return directory
        } catch {
            // SSH remains usable without multiplexing if the cache directory is
            // unavailable. The caller still receives the normal connection error.
            return nil
        }
    }()

    static var options: [String] {
        options(controlDirectory: controlDirectory, batchMode: true)
    }

    static func options(
        controlDirectory: URL?,
        batchMode: Bool = true
    ) -> [String] {
        var arguments: [String] = []
        if batchMode {
            arguments += ["-o", "BatchMode=yes"]
        }
        arguments += [
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new"
        ]
        if let controlDirectory {
            arguments += [
                "-o", "ControlMaster=auto",
                "-o", "ControlPersist=\(controlPersistSeconds)",
                "-o", "ControlPath=\(controlDirectory.path)/%C"
            ]
        }
        return arguments
    }

    static func arguments(host: String, command: String) -> [String] {
        options + ["--", host, command]
    }

    static func interactiveArguments(host: String, command: String) -> [String] {
        options(controlDirectory: controlDirectory, batchMode: false)
            + ["-t", "--", host, command]
    }

    static var rsyncRemoteShell: String {
        rsyncRemoteShell(controlDirectory: controlDirectory)
    }

    static func rsyncRemoteShell(controlDirectory: URL?) -> String {
        ([executableURL.path] + options(controlDirectory: controlDirectory))
            .map(shellQuote)
            .joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
