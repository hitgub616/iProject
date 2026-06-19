import SwiftUI
import AppKit

/// Decoded-thumbnail cache so animating the flow never re-decodes from disk.
enum ThumbCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func image(_ url: URL) -> NSImage? {
        if let hit = cache.object(forKey: url.path as NSString) { return hit }
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache.setObject(img, forKey: url.path as NSString)
        return img
    }
}

/// The raw artwork: a cached screenshot/GUI image, or a generated metadata cover.
struct CoverFace: View {
    let project: Project

    var body: some View {
        switch project.cover {
        case .image(let url):
            if let img = ThumbCache.image(url) {
                Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
            } else {
                GeneratedCoverView(project: project)
            }
        case .generated, .pending:
            GeneratedCoverView(project: project)
        }
    }
}

/// A metadata cover in the spirit of the mockup: vivid gradient, big initials,
/// a kind glyph and the project name.
struct GeneratedCoverView: View {
    let project: Project

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [project.palette.0, project.palette.1],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.28), .clear],
                               center: .topLeading, startRadius: 0, endRadius: s * 0.95)
                    .blendMode(.softLight)

                VStack(spacing: s * 0.035) {
                    Spacer(minLength: 0)
                    Image(systemName: project.kind.symbol)
                        .font(.system(size: s * 0.15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(project.initials)
                        .font(.system(size: s * 0.30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: s * 0.01, y: s * 0.005)
                    Spacer(minLength: 0)
                    Text(project.name)
                        .font(.system(size: s * 0.058, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, s * 0.09)
                        .padding(.bottom, s * 0.08)
                }
            }
            .frame(width: s, height: s)
        }
    }
}

/// A single Cover Flow card: glossy rounded face + mirrored floor reflection.
struct CoverCardView: View {
    let project: Project
    let metrics: CoverFlowMetrics
    var dim: Double = 0
    var reflectionOpacity: Double = 0.3

    private var radius: CGFloat { metrics.cornerRadius }
    private var rrect: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    var body: some View {
        VStack(spacing: metrics.cardSize * 0.012) {
            face
            reflection
        }
    }

    private var face: some View {
        CoverFace(project: project)
            .frame(width: metrics.cardSize, height: metrics.cardSize)
            .overlay(
                LinearGradient(colors: [.white.opacity(0.20), .clear, .clear],
                               startPoint: .topLeading, endPoint: .bottom)
                    .blendMode(.screen)
            )
            .overlay(Color.black.opacity(dim))
            .clipShape(rrect)
            .overlay(rrect.strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.55),
                    radius: metrics.cardSize * 0.06, x: 0, y: metrics.cardSize * 0.045)
    }

    private var reflection: some View {
        CoverFace(project: project)
            .frame(width: metrics.cardSize, height: metrics.cardSize)
            .overlay(Color.black.opacity(dim))
            .clipShape(rrect)
            .scaleEffect(x: 1, y: -1)
            .frame(width: metrics.cardSize, height: metrics.cardSize * 0.42, alignment: .top)
            .clipped()
            .mask(
                LinearGradient(colors: [.white.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .bottom)
            )
            .opacity(reflectionOpacity)
            .allowsHitTesting(false)
    }
}
