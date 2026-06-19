import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Picks the most "front page / GUI"-like image for a project and caches a
/// square thumbnail. Falls back to `.generated` when nothing visual exists.
enum CoverResolver {

    private static let imageExts: Set<String> =
        ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "bmp"]

    static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ProjexFinder/covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Public

    static func resolve(_ project: Project) -> CoverSource {
        // Finished .app bundle → use its real icon.
        if project.url.pathExtension.lowercased() == "app" {
            if let url = cachedAppIcon(for: project.url) { return .image(url) }
            return .generated
        }

        // Single file added to the library: use it directly if it's an image.
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: project.url.path, isDirectory: &isDir)
        if !isDir.boolValue {
            if imageExts.contains(project.url.pathExtension.lowercased()),
               let url = cachedThumbnail(for: project.url) { return .image(url) }
            return .generated
        }

        let candidates = candidateImages(in: project.url)
        guard let best = candidates
            .map({ Scored(url: $0.url, w: $0.w, h: $0.h, score: score($0, root: project.url)) })
            .filter({ $0.score >= 2.0 })
            .max(by: { $0.score < $1.score })
        else { return .generated }

        if let url = cachedThumbnail(for: best.url) { return .image(url) }
        return .generated
    }

    // MARK: - Candidate gathering

    private struct Cand { let url: URL; let w: Int; let h: Int }
    private struct Scored { let url: URL; let w: Int; let h: Int; let score: Double }

    private static func candidateImages(in root: URL) -> [Cand] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [Cand] = []
        var visited = 0
        for case let f as URL in en {
            let comp = f.lastPathComponent
            if ProjectScanner.heavyDirs.contains(comp) { en.skipDescendants(); continue }
            visited += 1
            if visited > 1500 { break }
            guard imageExts.contains(f.pathExtension.lowercased()) else { continue }
            if let (w, h) = dimensions(f) { out.append(Cand(url: f, w: w, h: h)) }
            if out.count > 400 { break }
        }
        return out
    }

    // MARK: - Scoring

    private static func score(_ c: Cand, root: URL) -> Double {
        let name = c.url.lastPathComponent.lowercased()
        let rel = c.url.path.lowercased()
            .replacingOccurrences(of: root.path.lowercased(), with: "")
        var s = 1.0

        let minSide = min(c.w, c.h)
        if minSide >= 800 { s += 3 }
        else if minSide >= 500 { s += 2 }
        else if minSide >= 300 { s += 0.5 }
        else { s -= 3 }

        let ar = c.h > 0 ? Double(c.w) / Double(c.h) : 0
        s += (ar >= 0.4 && ar <= 2.6) ? 1 : -1.5

        let uiHints = ["screenshot", "screen", "scr-", "scr_", "simulator", "preview",
                       "hero", "cover", "og-image", "og_", "mockup", "guide", "demo",
                       "landing", "home", "메인", "화면", "캡처", "앱"]
        if uiHints.contains(where: name.contains) { s += 4 }

        let goodDirs = ["/screenshots/", "/screenshot/", "/docs/", "/.github/", "/assets/",
                        "/public/", "/static/", "/images/", "/img/", "/preview"]
        if goodDirs.contains(where: rel.contains) { s += 1.5 }
        if rel.split(separator: "/").count <= 1 { s += 1.5 }    // sits at project root

        let chartHints = ["backtest", "portfolio", "plot", "figure", "_chart", "result",
                          "weights", "allocation", "performance", "equity", "drawdown"]
        if chartHints.contains(where: name.contains) { s -= 1.0 }

        let badName = ["placeholder", "favicon", "logo-", "icon-", "sprite", "thumb_",
                       "avatar", "qr", "badge"]
        if badName.contains(where: name.contains) { s -= 3 }

        let badPath = ["/build/", "/dist/", "/.dart_tool/", "/node_modules/", "/debug_captures/",
                       "/__pycache__/", "/test/", "/tests/", "/coverage/", "/cache/", "/.git/"]
        if badPath.contains(where: rel.contains) { s -= 3 }

        if name.contains("_crop") || name.contains("-crop") { s -= 2 }
        return s
    }

    /// Public entry for a user-chosen cover image → cached square thumbnail.
    static func makeSquareThumbnail(from url: URL) -> URL? { cachedThumbnail(for: url) }

    // MARK: - Web preview cache (rendered by WebPreviewRenderer)

    static func existingWebPreview(seed: String) -> URL? {
        let dest = cacheDir.appendingPathComponent(fnv(seed) + "-web.png")
        return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
    }

    /// Cache a rendered web snapshot, cropping the TOP square (the front page).
    static func cacheWebPreview(_ image: CGImage, seed: String) -> URL? {
        let dest = cacheDir.appendingPathComponent(fnv(seed) + "-web.png")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        let side = min(image.width, image.height)
        let x = (image.width - side) / 2
        guard let cropped = image.cropping(to: CGRect(x: x, y: 0, width: side, height: side)) else { return nil }
        let target = 700
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: target, height: target, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: target, height: target))
        guard let out = ctx.makeImage(), writePNG(out, to: dest) else { return nil }
        return dest
    }

    // MARK: - Thumbnail cache

    private static func cachedThumbnail(for source: URL) -> URL? {
        let key = cacheKey(for: source)
        let dest = cacheDir.appendingPathComponent(key + ".png")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        guard let img = squareThumbnail(from: source), writePNG(img, to: dest) else { return nil }
        return dest
    }

    private static func cachedAppIcon(for appURL: URL) -> URL? {
        let key = cacheKey(for: appURL) + "-icon"
        let dest = cacheDir.appendingPathComponent(key + ".png")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        var rect = CGRect(x: 0, y: 0, width: 512, height: 512)
        guard let cg = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let square = centerCropSquare(cg, target: 512),
              writePNG(square, to: dest) else { return nil }
        return dest
    }

    private static func cacheKey(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? Int) ?? 0
        return fnv("\(url.path)|\(Int(mtime))|\(size)")
    }

    // MARK: - Image processing

    private static func dimensions(_ url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }
        guard let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    private static func squareThumbnail(from url: URL, target: Int = 640) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1500
        ]
        guard let down = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return centerCropSquare(down, target: target)
    }

    private static func centerCropSquare(_ image: CGImage, target: Int) -> CGImage? {
        let w = image.width, h = image.height
        let side = min(w, h)
        let rect = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)
        guard let cropped = image.cropping(to: rect) else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: target, height: target, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return cropped }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: target, height: target))
        return ctx.makeImage()
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}

// FNV-1a hex string, shared helper.
func fnv(_ s: String) -> String {
    var h: UInt64 = 1469598103934665603
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    return String(h, radix: 16)
}
