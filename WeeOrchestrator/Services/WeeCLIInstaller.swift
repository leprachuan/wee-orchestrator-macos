import Foundation

struct WeeCLIInstallation: Equatable {
    let launcherURL: URL
    let shellProfileURLs: [URL]
}

enum WeeCLIInstaller {
    static let repositoryURL = "https://github.com/leprachuan/Wee-Orchestrator.git"

    static let managedBlock = """
    # >>> Wee Orchestrator CLI >>>
    case ":$PATH:" in
      *":$HOME/.local/bin:"*) ;;
      *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
    # <<< Wee Orchestrator CLI <<<
    """

    static func install(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        workingDirectory: String,
        checkoutDirectory: String,
        fileManager: FileManager = .default
    ) throws -> WeeCLIInstallation {
        let binDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let launcherURL = binDirectory.appendingPathComponent("wee")
        let launcher = launcherScript(
            workingDirectory: expanded(workingDirectory, homeDirectory: homeDirectory),
            checkoutDirectory: expanded(checkoutDirectory, homeDirectory: homeDirectory),
            managedCheckoutDirectory: managedCheckoutURL(homeDirectory: homeDirectory).path
        )
        try launcher.write(to: launcherURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)

        let profiles = [".zprofile", ".bash_profile", ".profile"].map {
            homeDirectory.appendingPathComponent($0)
        }
        for profile in profiles {
            try installManagedPathBlock(in: profile, fileManager: fileManager)
        }
        return WeeCLIInstallation(launcherURL: launcherURL, shellProfileURLs: profiles)
    }

    static func launcherScript(
        workingDirectory: String,
        checkoutDirectory: String,
        managedCheckoutDirectory: String = "$HOME/Library/Application Support/WeeOrchestrator/CLI/Wee-Orchestrator"
    ) -> String {
        let working = shellSingleQuoted(workingDirectory)
        let checkout = shellSingleQuoted(checkoutDirectory)
        let managed = managedCheckoutDirectory.hasPrefix("$HOME/")
            ? "\"\(managedCheckoutDirectory)\""
            : shellSingleQuoted(managedCheckoutDirectory)
        return """
        #!/bin/zsh
        set -e

        candidates=(\(managed) \(working) \(checkout) "$HOME/Developer/Wee-Orchestrator" "/opt/n8n-copilot-shim-dev")
        source_dir=""
        for candidate in "${candidates[@]}"; do
          if [[ -f "$candidate/wee_cli.py" ]]; then
            source_dir="$candidate"
            break
          fi
        done

        if [[ -z "$source_dir" ]]; then
          print -u2 "Wee CLI runtime is not installed. Open Wee Orchestrator → Settings → Local API Source and install or select the checkout."
          exit 78
        fi

        if [[ -x "$source_dir/.venv/bin/python" ]]; then
          python="$source_dir/.venv/bin/python"
        elif command -v python3 >/dev/null 2>&1; then
          python="$(command -v python3)"
        else
          print -u2 "Wee CLI needs Python 3. Bootstrap the Local API Source from the Wee Orchestrator app."
          exit 69
        fi

        cd "$source_dir"
        exec "$python" "$source_dir/wee_cli.py" "$@"
        """ + "\n"
    }

    static func managedCheckoutURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/WeeOrchestrator/CLI", isDirectory: true)
            .appendingPathComponent("Wee-Orchestrator", isDirectory: true)
    }

    /// Maintain an app-owned CLI checkout so developer worktrees never need to
    /// be reset or updated just to provide the current shell command.
    static func updateManagedRuntime(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> URL {
        let checkout = managedCheckoutURL(homeDirectory: homeDirectory)
        let parent = checkout.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: checkout.appendingPathComponent(".git").path) {
            let dirty = try run("/usr/bin/git", ["-C", checkout.path, "status", "--porcelain"])
            guard dirty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIUpdateError("Managed CLI checkout has local changes; update was not applied")
            }
            _ = try run("/usr/bin/git", ["-C", checkout.path, "fetch", "--depth", "1", "origin", "main"])
            _ = try run("/usr/bin/git", ["-C", checkout.path, "merge", "--ff-only", "FETCH_HEAD"])
        } else {
            if fileManager.fileExists(atPath: checkout.path) {
                let contents = try fileManager.contentsOfDirectory(atPath: checkout.path)
                guard contents.isEmpty else {
                    throw CLIUpdateError("Managed CLI folder exists but is not a Git checkout")
                }
            }
            _ = try run("/usr/bin/git", [
                "clone", "--depth", "1", "--branch", "main", repositoryURL, checkout.path,
            ])
        }

        let head = try run("/usr/bin/git", ["-C", checkout.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let venvPython = checkout.appendingPathComponent(".venv/bin/python")
        let stamp = parent.appendingPathComponent("dependencies.commit")
        let installedHead = try? String(contentsOf: stamp, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fileManager.isExecutableFile(atPath: venvPython.path) || installedHead != head {
            if !fileManager.isExecutableFile(atPath: venvPython.path) {
                let python = try systemPython(fileManager: fileManager)
                _ = try run(python, ["-m", "venv", checkout.appendingPathComponent(".venv").path])
            }
            _ = try run(venvPython.path, [
                "-m", "pip", "install",
                "openai>=1.0.0", "httpx>=0.27.0", "rich>=13.7.0",
                "keyring>=25.0.0", "keyrings.alt>=5.0.0", "cryptography>=42.0.0",
                "github-copilot-sdk>=1.0.7",
            ])
            try (head + "\n").write(to: stamp, atomically: true, encoding: .utf8)
        }
        return checkout
    }

    private static func systemPython(fileManager: FileManager) throws -> String {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Developer/CommandLineTools/usr/bin/python3",
            "/usr/bin/python3",
        ]
        if let python = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return python
        }
        throw CLIUpdateError("Python 3 is required to install the managed Wee CLI")
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw CLIUpdateError(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private static func installManagedPathBlock(in profileURL: URL, fileManager: FileManager) throws {
        let start = "# >>> Wee Orchestrator CLI >>>"
        let end = "# <<< Wee Orchestrator CLI <<<"
        var contents = (try? String(contentsOf: profileURL, encoding: .utf8)) ?? ""
        if let startRange = contents.range(of: start),
           let endRange = contents.range(of: end, range: startRange.lowerBound..<contents.endIndex) {
            var blockEnd = endRange.upperBound
            if blockEnd < contents.endIndex, contents[blockEnd] == "\n" {
                blockEnd = contents.index(after: blockEnd)
            }
            contents.replaceSubrange(startRange.lowerBound..<blockEnd, with: "")
        }
        if !contents.isEmpty && !contents.hasSuffix("\n") { contents += "\n" }
        if !contents.isEmpty { contents += "\n" }
        contents += managedBlock + "\n"
        try contents.write(to: profileURL, atomically: true, encoding: .utf8)
    }

    private static func expanded(_ path: String, homeDirectory: URL) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return homeDirectory.path }
        if trimmed.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(trimmed.dropFirst(2))).path
        }
        return trimmed
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct CLIUpdateError: LocalizedError {
    let message: String

    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
