import Foundation

/// Scans a workspace folder and infers per-project metadata.
enum ProjectScanner {

    static let heavyDirs: Set<String> = [
        "node_modules", ".git", "venv", ".venv", "env", "__pycache__",
        "build", "dist", ".next", "Pods", "site-packages", "DerivedData",
        ".dart_tool", "target", ".gradle", ".idea", ".vscode", "coverage",
        ".cache", "out", ".turbo", ".expo", ".pytest_cache", ".mypy_cache"
    ]

    static let langByExt: [String: String] = [
        "swift": "Swift", "ts": "TypeScript", "tsx": "TypeScript",
        "js": "JavaScript", "jsx": "JavaScript", "mjs": "JavaScript", "cjs": "JavaScript",
        "py": "Python", "dart": "Dart", "go": "Go", "rs": "Rust",
        "java": "Java", "kt": "Kotlin", "rb": "Ruby", "php": "PHP",
        "html": "HTML", "css": "CSS", "scss": "SCSS", "c": "C", "h": "C",
        "cpp": "C++", "cc": "C++", "hpp": "C++", "cs": "C#", "sh": "Shell",
        "ipynb": "Jupyter", "vue": "Vue", "svelte": "Svelte"
    ]

    /// Markup languages are only chosen when nothing more specific exists.
    static let markupLangs: Set<String> = ["HTML", "CSS", "SCSS"]

    struct Analysis {
        var kind: ProjectKind
        var language: String
        var sizeBytes: Int64
        var summary: String?
    }

    // MARK: - Fast first pass: list the projects without walking them.

    static func immediateProjects(in root: URL) -> [Project] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [Project] = []
        for url in entries {
            let rv = try? url.resourceValues(forKeys: Set(keys))
            let isDir = rv?.isDirectory ?? false
            let isPackage = rv?.isPackage ?? false
            guard isDir || isPackage else { continue }

            let mtime = rv?.contentModificationDate ?? .distantPast
            result.append(Project(
                id: url.path,
                name: url.lastPathComponent,
                url: url,
                displayPath: tildePath(url),
                kind: .other,
                language: "—",
                sizeBytes: nil,
                lastModified: mtime,
                cover: .pending
            ))
        }
        return result.sorted { $0.lastModified > $1.lastModified }
    }

    /// Build a placeholder project for an arbitrary file or folder (used when
    /// the user adds an item to the library).
    static func placeholder(for url: URL) -> Project {
        let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return Project(
            id: url.path, name: url.lastPathComponent, url: url,
            displayPath: tildePath(url), kind: .other, language: "—",
            sizeBytes: nil, lastModified: rv?.contentModificationDate ?? .distantPast,
            cover: .pending)
    }

    // MARK: - Deep analysis for a single project.

    static func analyze(_ url: URL) -> Analysis {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        if !isDir.boolValue { return analyzeFile(url) }

        let name = url.lastPathComponent.lowercased()

        // .app bundles are finished desktop apps — no deep walk needed.
        if name.hasSuffix(".app") {
            return Analysis(kind: .desktop, language: "App",
                            sizeBytes: directorySize(url, cap: 6000), summary: "macOS app")
        }

        var markers: Set<String> = []
        var pkgText = "", reqText = ""

        let rootFiles = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        for f in rootFiles {
            let lf = f.lowercased()
            switch lf {
            case "package.json":
                markers.insert("node")
                pkgText = readSmall(url.appendingPathComponent(f))
            case "pubspec.yaml": markers.insert("flutter")
            case "requirements.txt", "pyproject.toml", "environment.yml", "pipfile":
                markers.insert("python")
                reqText += readSmall(url.appendingPathComponent(f)).lowercased()
            case "cargo.toml": markers.insert("rust")
            case "go.mod": markers.insert("go")
            case "package.swift": markers.insert("xcode")
            case "index.html": markers.insert("html")
            default:
                if lf.hasSuffix(".xcodeproj") || lf.hasSuffix(".xcworkspace") { markers.insert("xcode") }
            }
        }

        var extCounts: [String: Int] = [:]
        var sizes: Int64 = 0

        if let en = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            var visited = 0
            for case let f as URL in en {
                let comp = f.lastPathComponent
                if heavyDirs.contains(comp) { en.skipDescendants(); continue }
                visited += 1
                if visited > 12000 { break }
                let rv = try? f.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if rv?.isDirectory == true { continue }
                sizes += Int64(rv?.fileSize ?? 0)
                let ext = f.pathExtension.lowercased()
                if langByExt[ext] != nil { extCounts[ext, default: 0] += 1 }
                if comp.lowercased() == "index.html" { markers.insert("html") }
            }
        }

        let kind = inferKind(markers: markers, pkg: pkgText.lowercased(), req: reqText, exts: extCounts)
        let language = topLanguage(exts: extCounts, markers: markers)
        // Every project gets a description: real (README/manifest) → else one
        // composed from its structure. No project is left without one.
        let summary = extractSummary(root: url, rootFiles: rootFiles, pkg: pkgText)
            ?? composedSummary(markers: markers, pkg: pkgText.lowercased(),
                               req: reqText, exts: extCounts, kind: kind, language: language)
        return Analysis(kind: kind, language: language, sizeBytes: sizes, summary: summary)
    }

    /// A brief description synthesized from the project's structure, used when
    /// no README/manifest description exists. Generic — works for any folder.
    static func composedSummary(markers: Set<String>, pkg: String, req: String,
                                exts: [String: Int], kind: ProjectKind, language: String) -> String {
        var fw: String?
        if markers.contains("flutter") { fw = "Flutter" }
        else if pkg.contains("next") { fw = "Next.js" }
        else if pkg.contains("nuxt") { fw = "Nuxt" }
        else if pkg.contains("astro") { fw = "Astro" }
        else if pkg.contains("svelte") { fw = "Svelte" }
        else if pkg.contains("vue") { fw = "Vue" }
        else if pkg.contains("react") { fw = pkg.contains("vite") ? "React + Vite" : "React" }
        else if pkg.contains("vite") { fw = "Vite" }
        else if pkg.contains("electron") { fw = "Electron" }
        else if pkg.contains("tauri") { fw = "Tauri" }
        else if pkg.contains("@nestjs") { fw = "NestJS" }
        else if pkg.contains("express") { fw = "Express" }
        else if req.contains("streamlit") { fw = "Streamlit" }
        else if req.contains("fastapi") { fw = "FastAPI" }
        else if req.contains("flask") { fw = "Flask" }
        else if req.contains("django") { fw = "Django" }
        else if req.contains("gradio") { fw = "Gradio" }

        let noun: String
        switch kind {
        case .web:     noun = "web app"
        case .mobile:  noun = "mobile app"
        case .desktop: noun = "desktop app"
        case .backend: noun = "service"
        case .dataML:  noun = "data/ML project"
        case .tool:    noun = "tool"
        case .game:    noun = "game"
        case .library: noun = "library"
        case .other:   noun = "project"
        }

        var head: String
        if let fw { head = "\(fw) \(noun)" }
        else if language != "—" { head = "\(language) \(noun)" }
        else { head = noun.prefix(1).uppercased() + noun.dropFirst() }

        // Detail for data/ML: name a couple of detected libraries.
        if kind == .dataML {
            let libMap: [(String, String)] = [
                ("pandas", "pandas"), ("scikit", "scikit-learn"), ("sklearn", "scikit-learn"),
                ("torch", "PyTorch"), ("tensorflow", "TensorFlow"), ("xgboost", "XGBoost"),
                ("lightgbm", "LightGBM"), ("keras", "Keras"), ("numpy", "NumPy"),
            ]
            var libs: [String] = []
            for (k, v) in libMap where req.contains(k) && !libs.contains(v) { libs.append(v) }
            if !libs.isEmpty { head += " · " + libs.prefix(2).joined(separator: ", ") }
            else if exts["ipynb"] != nil { head += " · Jupyter notebooks" }
        }
        return head
    }

    // MARK: - Short summary phrase (README / manifest)

    static func extractSummary(root: URL, rootFiles: [String], pkg: String) -> String? {
        // 1) README — first descriptive paragraph, else its H1 (usually the
        //    most accurate "what is this project").
        if let readme = rootFiles.first(where: { $0.lowercased().hasPrefix("readme") }) {
            let text = readSmall(root.appendingPathComponent(readme), limit: 6000)
            if let tag = readmeTagline(text), let phrase = toPhrase(tag),
               phrase.lowercased() != root.lastPathComponent.lowercased() {
                return phrase
            }
        }
        // 2) package.json "description" fallback.
        if let desc = firstMatch(in: pkg, pattern: #""description"\s*:\s*"([^"]{3,})""#),
           let phrase = toPhrase(desc) { return phrase }
        return nil
    }

    private static func readmeTagline(_ text: String) -> String? {
        var h1: String?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                if h1 == nil { h1 = stripMarkdown(line.replacingOccurrences(of: "#", with: "")) }
                continue
            }
            // skip badges / images / quotes / lists / tables / code / html
            if "![>|=`".contains(line.first!) || line.hasPrefix("- ") || line.hasPrefix("* ")
                || line.hasPrefix("<") || line.hasPrefix("```") { continue }
            let cleaned = stripMarkdown(line)
            if cleaned.count >= 4 { return cleaned }
        }
        return h1
    }

    private static func stripMarkdown(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[*_`#>]"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func toPhrase(_ s: String, maxLen: Int = 52) -> String? {
        var t = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        // first sentence only → phrase feel
        if let dot = t.firstIndex(where: { $0 == "." || $0 == "。" || $0 == "\n" }) {
            let head = String(t[t.startIndex..<dot]).trimmingCharacters(in: .whitespaces)
            if head.count >= 6 { t = head }
        }
        if t.count > maxLen {
            var cut = String(t.prefix(maxLen))
            if let sp = cut.lastIndex(of: " ") { cut = String(cut[cut.startIndex..<sp]) }
            t = cut + "…"
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;-—–·"))
        return t.count >= 3 ? t : nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func analyzeFile(_ url: URL) -> Analysis {
        let ext = url.pathExtension.lowercased()
        let lang = langByExt[ext] ?? "—"
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "bmp", "svg"]
        let summary: String = imageExts.contains(ext) ? "Image file"
            : ext == "pdf" ? "PDF document"
            : lang != "—" ? "\(lang) file" : "File"
        let kind: ProjectKind
        switch ext {
        case "html", "htm":                      kind = .web
        case "swift":                            kind = .desktop
        case "py", "ipynb":                      kind = .dataML
        case "js", "ts", "tsx", "jsx", "vue":    kind = .web
        case "go", "rs":                         kind = .backend
        case "png", "jpg", "jpeg", "webp", "gif", "heic", "pdf", "fig", "sketch":
            kind = .other
        default:                                 kind = .tool
        }
        return Analysis(kind: kind, language: lang, sizeBytes: size, summary: summary)
    }

    // MARK: - Inference helpers

    private static func topLanguage(exts: [String: Int], markers: Set<String>) -> String {
        // Aggregate per-language counts.
        var counts: [String: Int] = [:]
        for (ext, n) in exts { if let lang = langByExt[ext] { counts[lang, default: 0] += n } }

        let code = counts.filter { !markupLangs.contains($0.key) }
        if let best = code.max(by: { $0.value < $1.value }) { return best.key }
        if let best = counts.max(by: { $0.value < $1.value }) { return best.key }

        if markers.contains("flutter") { return "Dart" }
        if markers.contains("node") { return "JavaScript" }
        if markers.contains("python") { return "Python" }
        return "—"
    }

    private static func inferKind(markers: Set<String>, pkg: String, req: String, exts: [String: Int]) -> ProjectKind {
        if markers.contains("flutter") { return .mobile }
        if markers.contains("xcode") { return .desktop }

        if markers.contains("node") {
            if pkg.contains("electron") || pkg.contains("tauri") { return .desktop }
            let webFw = ["next", "react", "vue", "svelte", "vite", "astro", "nuxt", "gatsby", "remix"]
            if webFw.contains(where: pkg.contains) { return .web }
            let backendFw = ["express", "fastify", "@nestjs", "koa", "hapi"]
            if backendFw.contains(where: pkg.contains) { return .backend }
            return markers.contains("html") ? .web : .backend
        }

        if markers.contains("python") {
            let webFw = ["streamlit", "flask", "fastapi", "django", "dash", "gradio", "uvicorn"]
            if webFw.contains(where: req.contains) { return .backend }
            let mlFw = ["torch", "tensorflow", "scikit", "sklearn", "pandas", "numpy", "matplotlib", "xgboost", "lightgbm", "keras"]
            if mlFw.contains(where: req.contains) { return .dataML }
            return .tool
        }

        if markers.contains("rust") { return .tool }
        if markers.contains("go") { return .backend }
        if markers.contains("html") { return .web }
        if exts.keys.contains("ipynb") { return .dataML }
        return .other
    }

    /// The best static/built HTML entry point to render as a preview, if any.
    static func htmlEntry(for url: URL) -> URL? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        guard isDir.boolValue else {
            return ["html", "htm"].contains(url.pathExtension.lowercased()) ? url : nil
        }
        let candidates = [
            "dist/index.html", "build/index.html", "out/index.html",
            "build/web/index.html", "public/index.html", "index.html", "src/index.html",
        ]
        for c in candidates {
            let f = url.appendingPathComponent(c)
            if fm.fileExists(atPath: f.path) { return f }
        }
        return nil
    }

    // MARK: - Utilities

    static func directorySize(_ url: URL, cap: Int) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey],
                                     options: [.skipsHiddenFiles]) else { return 0 }
        var visited = 0
        for case let f as URL in en {
            if heavyDirs.contains(f.lastPathComponent) { en.skipDescendants(); continue }
            visited += 1
            if visited > cap { break }
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    private static func readSmall(_ url: URL, limit: Int = 16_000) -> String {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return "" }
        let slice = data.prefix(limit)
        return String(data: slice, encoding: .utf8) ?? ""
    }

    static func tildePath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = url.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}
