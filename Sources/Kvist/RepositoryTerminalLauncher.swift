import AppKit
import Foundation

enum RepositoryTerminalLauncher {
    static func open(
        repositoryURL: URL,
        sshRepository: SSHRepository?,
        workspace: NSWorkspace = .shared
    ) throws {
        guard let terminalURL = workspace.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else {
            throw RepositoryTerminalError.terminalNotFound
        }

        let targetURL: URL
        if let sshRepository {
            targetURL = try makeSSHCommandFile(for: sshRepository)
        } else {
            targetURL = repositoryURL
        }
        workspace.open(
            [targetURL],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    static func sshArguments(for repository: SSHRepository) -> [String] {
        SSHConnection.interactiveArguments(
            host: repository.host,
            command: remoteShellCommand(path: repository.path)
        )
    }

    static func commandFileContents(for repository: SSHRepository) -> String {
        let command = ([SSHConnection.executableURL.path] + sshArguments(for: repository))
            .map(shellQuote)
            .joined(separator: " ")
        return """
        #!/bin/sh
        /bin/rm -f -- "$0"
        exec \(command)
        """ + "\n"
    }

    private static func makeSSHCommandFile(for repository: SSHRepository) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Kvist-SSH-\(UUID().uuidString).command"
        )
        do {
            try commandFileContents(for: repository).write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: fileURL.path
            )
            return fileURL
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw RepositoryTerminalError.commandFileCreationFailed
        }
    }

    private static func remoteShellCommand(path: String) -> String {
        let script = "cd \(shellQuote(path)) && exec \"${SHELL:-/bin/sh}\" -l"
        return "/bin/sh -c \(shellQuote(script))"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum RepositoryTerminalError: LocalizedError {
    case terminalNotFound
    case commandFileCreationFailed

    var errorDescription: String? {
        switch self {
        case .terminalNotFound:
            "Terminal could not be found."
        case .commandFileCreationFailed:
            "Kvist could not prepare the SSH terminal session."
        }
    }
}
