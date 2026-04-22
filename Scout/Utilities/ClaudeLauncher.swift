import Foundation
import AppKit

/// Launches an interactive Claude session seeded with the context of an
/// action item. Two targets are supported — a Claude Code CLI session
/// (Ghostty + tmux when available, otherwise a fresh Ghostty window), or
/// Claude Desktop's main chat.
///
/// The full action-item context is always copied to the clipboard so the
/// user can paste it with Cmd+V as a reliable fallback if the platform's
/// native prefill mechanism is flaky.
enum ClaudeLauncher {
    enum DesktopMode {
        /// `claude://claude.ai/new` — main chat. Reliably opens a fresh chat
        /// with the prompt prefilled from any screen.
        case chat
        /// `claude://cowork/new` — dispatches into Cowork's composer with
        /// ``prefillOnly: true``. Works only when the Cowork screen is
        /// currently mountable, and appends to any existing composer text
        /// rather than replacing it.
        case cowork
    }

    enum Target {
        case ghostty(cwd: URL)
        case claudeDesktop(DesktopMode)
    }

    enum LaunchError: LocalizedError {
        case ghosttyNotInstalled
        case claudeDesktopNotInstalled
        case scriptWriteFailed(String)
        case urlBuildFailed

        var errorDescription: String? {
            switch self {
            case .ghosttyNotInstalled:
                return "Ghostty.app isn't installed. Install it from https://ghostty.org to use this option."
            case .claudeDesktopNotInstalled:
                return "Claude.app isn't installed. Download Claude Desktop from https://claude.ai/download to use this option."
            case .scriptWriteFailed(let msg):
                return "Couldn't prepare Claude launch helper: \(msg)"
            case .urlBuildFailed:
                return "Couldn't build claude:// URL."
            }
        }
    }

    static func launch(target: Target, prompt: String) throws {
        // Clipboard is the universal fallback. Ghostty's tmux-based flow
        // needs it for ⌘V into the claude TUI; the Claude Desktop URL-prefill
        // sometimes drops the `q` param during screen transitions, and the
        // clipboard lets the user recover with ⌘A ⌘V.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        switch target {
        case .ghostty(let cwd):         try launchGhostty(cwd: cwd)
        case .claudeDesktop(let mode):  try launchClaudeDesktop(prompt: prompt, mode: mode)
        }
    }

    /// Build the prompt text for a task — subject, plus body, recent
    /// comments, and any deep links.
    static func prompt(for task: ActionTask) -> String {
        var out = "Help me make progress on this action item:\n\n\(task.plainSubject)"
        if !task.body.isEmpty {
            out += "\n\n\(task.body)"
        }
        if !task.comments.isEmpty {
            let block = task.comments
                .map { c in
                    let ts = c.timestamp.isEmpty ? "" : " (\(c.timestamp))"
                    return "- \(c.author)\(ts): \(c.text)"
                }
                .joined(separator: "\n")
            out += "\n\nPrior comments:\n\(block)"
        }
        if !task.deepLinks.isEmpty {
            let block = task.deepLinks
                .map { "- \($0.displayLabel): \($0.openURL.absoluteString)" }
                .joined(separator: "\n")
            out += "\n\nLinks:\n\(block)"
        }
        return out
    }

    // MARK: - Ghostty

    private static let ghosttyBundleID = "com.mitchellh.ghostty"

    /// Common Homebrew + system paths. Scout.app is launched by macOS with
    /// a minimal PATH, so we probe absolute locations instead of relying on
    /// `which`.
    private static let tmuxPaths = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux",
    ]

    private static func launchGhostty(cwd: URL) throws {
        guard let ghosttyURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: ghosttyBundleID
        ) else {
            throw LaunchError.ghosttyNotInstalled
        }

        // Preferred: if the user runs tmux inside Ghostty (very common
        // setup, pushed by Ghostty's `command = tmux new-session -A` config
        // pattern), spawn a new tmux window directly in their session and
        // activate Ghostty. This is the only reliable way to get a fresh
        // terminal surface on macOS when Ghostty's secondary-instance
        // handler routes -e/--command= args through the primary window.
        if launchViaTmux(cwd: cwd) {
            activateGhostty(ghosttyURL: ghosttyURL)
            return
        }

        // Fallback: no tmux server → open a fresh Ghostty window with our
        // command via --command= (overrides the user's configured command).
        try launchFreshGhosttyWindow(ghosttyURL: ghosttyURL, cwd: cwd)
    }

    /// Returns true if a tmux session was found and a `claude` window was
    /// successfully spawned in it.
    private static func launchViaTmux(cwd: URL) -> Bool {
        guard let tmuxPath = tmuxPaths.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { return false }

        guard let session = firstTmuxSession(tmuxPath: tmuxPath) else {
            return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: tmuxPath)
        // Point tmux at the user's default socket dir explicitly. GUI apps
        // inherit `TMPDIR=/var/folders/…`, while tmux stores its socket at
        // `/tmp/tmux-$UID/default` under the shell convention.
        task.environment = tmuxEnvironment()
        task.arguments = [
            "new-window",
            "-t", "\(session):",
            "-c", cwd.path,
            "-n", "claude",
            "claude",
        ]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        return task.terminationStatus == 0
    }

    /// Lists tmux sessions and returns the first attached one (or the first
    /// session overall if none are attached).
    private static func firstTmuxSession(tmuxPath: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tmuxPath)
        task.environment = tmuxEnvironment()
        // "0 name" for attached, "1 name" for detached — sort puts
        // attached sessions first.
        task.arguments = [
            "list-sessions",
            "-F", "#{?session_attached,0,1} #{session_name}",
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        if task.terminationStatus != 0 { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let sorted = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .sorted()
        guard let first = sorted.first else { return nil }
        let parts = first.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return String(parts[1])
    }

    private static func tmuxEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TMPDIR"] = "/tmp"
        return env
    }

    private static func activateGhostty(ghosttyURL: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: ghosttyURL, configuration: config) { _, error in
            if let error {
                NSLog("ClaudeLauncher: activate(Ghostty) failed: \(error.localizedDescription)")
            }
        }
    }

    private static func launchFreshGhosttyWindow(ghosttyURL: URL, cwd: URL) throws {
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scout-launch-claude-\(UUID().uuidString).sh")
        do {
            try makeGhosttyScript(cwd: cwd).write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            throw LaunchError.scriptWriteFailed(error.localizedDescription)
        }

        // `--command=` is a Ghostty CLI config override — it wins over the
        // user's `command = …` line in ~/.config/ghostty/config for this
        // instance. `createsNewApplicationInstance = true` is required on
        // macOS so our args aren't silently dropped by app activation.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = true
        config.arguments = ["--command=\(scriptURL.path)"]

        NSWorkspace.shared.openApplication(at: ghosttyURL, configuration: config) { _, error in
            if let error {
                NSLog("ClaudeLauncher: openApplication(Ghostty) failed: \(error.localizedDescription)")
            }
        }
    }

    private static func makeGhosttyScript(cwd: URL) -> String {
        let cwdEsc = cwd.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        #!/bin/bash
        cd "\(cwdEsc)" || exit 1
        clear
        echo "Scout: action-item context copied to your clipboard."
        echo "When Claude prompts you, paste (Cmd+V) and press Enter to send."
        echo
        exec claude
        """
    }

    // MARK: - Claude Desktop

    private static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    private static func launchClaudeDesktop(prompt: String, mode: DesktopMode) throws {
        guard NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: claudeDesktopBundleID
        ) != nil else {
            throw LaunchError.claudeDesktopNotInstalled
        }

        var components = URLComponents()
        components.scheme = "claude"
        switch mode {
        case .chat:
            components.host = "claude.ai"
            components.path = "/new"
        case .cowork:
            components.host = "cowork"
            components.path = "/new"
        }
        components.queryItems = [URLQueryItem(name: "q", value: prompt)]

        guard let url = components.url else {
            throw LaunchError.urlBuildFailed
        }
        NSWorkspace.shared.open(url)
    }
}
