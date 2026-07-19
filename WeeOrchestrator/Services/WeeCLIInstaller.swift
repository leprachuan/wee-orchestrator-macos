import Foundation

struct WeeCLIInstallation: Equatable {
    let launcherURL: URL
    let shellProfileURLs: [URL]
}

enum WeeCLIInstaller {
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
            checkoutDirectory: expanded(checkoutDirectory, homeDirectory: homeDirectory)
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

    static func launcherScript(workingDirectory: String, checkoutDirectory: String) -> String {
        let working = shellSingleQuoted(workingDirectory)
        let checkout = shellSingleQuoted(checkoutDirectory)
        return """
        #!/bin/zsh
        set -e

        candidates=(\(working) \(checkout) "$HOME/Developer/Wee-Orchestrator" "/opt/n8n-copilot-shim-dev")
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
