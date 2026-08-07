import AppKit
import Foundation

enum RepositoryTerminalLauncher {
    static func open(
        repositoryURL: URL,
        sshRepository: SSHRepository?,
        bundleIdentifier: String = TerminalPreferences.selectedBundleIdentifier(),
        workspace: NSWorkspace = .shared,
        onFailure: ((Error) -> Void)? = nil
    ) throws {
        guard let terminalURL = workspace.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            throw RepositoryTerminalError.terminalNotFound(
                name: TerminalPreferences.displayName(
                    forBundleIdentifier: bundleIdentifier,
                    applicationURL: nil
                )
            )
        }

        let targetURL: URL
        let applicationURL: URL
        if let sshRepository {
            // Terminals that cannot run a .command file accept the open without
            // ever starting the session, so hand SSH to a shell-script runner.
            targetURL = try makeSSHCommandFile(for: sshRepository)
            applicationURL = TerminalPreferences.shellScriptApplicationURL(
                bundleIdentifier: bundleIdentifier,
                applicationURL: terminalURL,
                defaultHandlerURL: workspace.urlForApplication(toOpen: targetURL)
            )
        } else {
            targetURL = repositoryURL
            applicationURL = terminalURL
        }
        let terminalName = TerminalPreferences.displayName(forApplicationAt: applicationURL)
        workspace.open(
            [targetURL],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            guard let error else { return }
            onFailure?(
                RepositoryTerminalError.launchFailed(
                    name: terminalName,
                    reason: error.localizedDescription
                )
            )
        }
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
    case terminalNotFound(name: String)
    case commandFileCreationFailed
    case launchFailed(name: String, reason: String)
    case unreadableApplication

    var errorDescription: String? {
        switch self {
        case let .terminalNotFound(name):
            "\(name) could not be found. Choose another terminal app in Settings."
        case .commandFileCreationFailed:
            "Kvist could not prepare the SSH terminal session."
        case let .launchFailed(name, reason):
            "\(name) could not open the repository. \(reason)"
        case .unreadableApplication:
            "Kvist could not read that app's identifier. Choose an application bundle."
        }
    }
}
