import WebKit
import AppKit

/// Renders a project's web front-end (a static / built index.html) in an
/// offscreen WKWebView and snapshots it, so the cover shows the REAL UI rather
/// than a metadata placeholder. Pages that render blank (e.g. a Vite/Next dev
/// shell that needs a server) are rejected so the caller can fall back.
@MainActor
final class WebPreviewRenderer: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var settleWork: DispatchWorkItem?
    private var finished = false

    func render(entry: URL, accessDir: URL,
                viewport: CGSize = CGSize(width: 1280, height: 800)) async -> CGImage? {
        await withCheckedContinuation { cont in
            finished = false
            continuation = cont

            let cfg = WKWebViewConfiguration()
            let wv = WKWebView(frame: CGRect(origin: .zero, size: viewport), configuration: cfg)
            wv.navigationDelegate = self

            // Host in a transparent on-screen window so WebKit actually
            // composites the page (an ordered-out window may not render).
            let win = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: viewport.width, height: viewport.height),
                styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = wv
            win.alphaValue = 0.0
            win.ignoresMouseEvents = true
            win.level = .init(Int(CGWindowLevelForKey(.desktopWindow)))
            win.orderFrontRegardless()

            webView = wv
            window = win

            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in self?.finish(nil) }
            wv.loadFileURL(entry, allowingReadAccessTo: accessDir)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Let scripts/fonts/layout settle, then snapshot.
        let work = DispatchWorkItem { [weak self] in self?.snapshot() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    private func snapshot() {
        guard let wv = webView else { finish(nil); return }
        let cfg = WKSnapshotConfiguration()
        cfg.rect = wv.bounds
        wv.takeSnapshot(with: cfg) { [weak self] image, _ in
            guard let self else { return }
            guard let image,
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                self.finish(nil); return
            }
            self.finish(Self.isBlank(cg) ? nil : cg)
        }
    }

    private func finish(_ cg: CGImage?) {
        guard !finished else { return }
        finished = true
        settleWork?.cancel(); settleWork = nil
        window?.orderOut(nil); window = nil; webView = nil
        let c = continuation; continuation = nil
        c?.resume(returning: cg)
    }

    /// True when the snapshot is essentially uniform (white shell / solid color),
    /// meaning nothing real rendered.
    static func isBlank(_ cg: CGImage) -> Bool {
        let n = 16
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8,
                                  bytesPerRow: n * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let data = ctx.data else { return false }
        let p = data.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var lumas = [Double](); lumas.reserveCapacity(n * n)
        for i in 0..<(n * n) {
            let r = Double(p[i * 4]), g = Double(p[i * 4 + 1]), b = Double(p[i * 4 + 2])
            lumas.append(0.299 * r + 0.587 * g + 0.114 * b)
        }
        let mean = lumas.reduce(0, +) / Double(lumas.count)
        let variance = lumas.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lumas.count)
        return variance < 80
    }
}
