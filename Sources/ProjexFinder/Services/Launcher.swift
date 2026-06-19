import SwiftUI
import AppKit

/// LLM / editor desktop apps a project folder can be opened into.
enum Launcher: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case cursor = "Cursor"
    case codex = "Codex"
    case antigravity = "Antigravity"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var symbol: String {
        switch self {
        case .claude:      return "sparkles"
        case .cursor:      return "cursorarrow.rays"
        case .codex:       return "chevron.left.forwardslash.chevron.right"
        case .antigravity: return "atom"
        }
    }

    /// Candidate .app file names (display name first), plus bundle-id fallbacks.
    private var appNames: [String] {
        switch self {
        case .claude:      return ["Claude"]
        case .cursor:      return ["Cursor"]
        case .codex:       return ["Codex"]
        case .antigravity: return ["Antigravity"]
        }
    }

    private var bundleIDs: [String] {
        switch self {
        case .claude:      return ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        case .cursor:      return ["com.todesktop.230313mzl4w4u92"]
        case .codex:       return ["com.openai.codex"]
        case .antigravity: return ["com.google.antigravity"]
        }
    }

    func appURL() -> URL? {
        let fm = FileManager.default
        let dirs = ["/Applications", "\(NSHomeDirectory())/Applications", "/System/Applications"]
        for name in appNames {
            for dir in dirs {
                let p = "\(dir)/\(name).app"
                if fm.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
            }
        }
        for bid in bundleIDs {
            if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) { return u }
        }
        return nil
    }

    var isInstalled: Bool {
        // Claude opens via the Claude Code CLI, not the desktop app.
        self == .claude ? Launcher.claudeCLIURL() != nil : appURL() != nil
    }

    func launch(_ project: Project) {
        if self == .claude { Launcher.openInClaudeCode(project); return }
        guard let appURL = appURL() else { NSSound.beep(); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([project.url], withApplicationAt: appURL,
                                configuration: cfg, completionHandler: nil)
    }

    // MARK: - Claude Code

    static func claudeCLIURL() -> URL? {
        let cands = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
        ]
        for c in cands where FileManager.default.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        return nil
    }

    /// Open a login-shell Terminal in the project dir and start Claude Code.
    static func openInClaudeCode(_ project: Project) {
        let quoted = "'" + project.url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let body = "#!/bin/zsh -l\ncd \(quoted)\nclaude\n"
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("projex-claude-\(UUID().uuidString).command")
        do {
            try body.write(to: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            NSWorkspace.shared.open(tmp)
        } catch {
            NSSound.beep()
        }
    }
}

/// Open a folder in Finder showing its contents; reveal (select) a file or .app.
func openInFinder(_ url: URL) {
    let isApp = url.pathExtension.lowercased() == "app"
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
    if isDir.boolValue && !isApp {
        NSWorkspace.shared.open(url)                       // enter the folder
    } else {
        NSWorkspace.shared.activateFileViewerSelecting([url])  // reveal the item
    }
}

/// Reusable context-menu content: launchers + cover management + Open in Finder.
/// Used by both the list rows and the cover cards.
struct ProjectContextMenu: View {
    let project: Project
    let store: LibraryStore

    var body: some View {
        ForEach(Launcher.allCases) { app in
            Button {
                app.launch(project)
            } label: {
                Label("Start with \(app.displayName)", systemImage: app.symbol)
            }
            .disabled(!app.isInstalled)
        }

        Divider()

        Button {
            store.presentSetCover(for: project.id)
        } label: {
            Label("Set Cover from Image…", systemImage: "photo")
        }
        if store.isCustomCover(project.id) {
            Button {
                store.resetCover(for: project.id)
            } label: {
                Label("Reset Cover", systemImage: "arrow.uturn.backward")
            }
        }

        Divider()

        Button {
            openInFinder(project.url)
        } label: {
            Label("Open in Finder", systemImage: "folder")
        }
    }
}
