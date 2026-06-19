import SwiftUI

// MARK: - App palette

enum Palette {
    /// Deterministic hash so a project always gets the same colors.
    private static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603 // FNV-1a
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    /// A rich two-stop gradient seeded by the project name, in the spirit of
    /// the iTunes-style mockup covers.
    static func gradient(for seed: String) -> (Color, Color) {
        let h = hash(seed)
        let hue = Double(h % 360) / 360.0
        let hue2 = (hue + 0.08 + Double((h >> 16) % 12) / 200.0).truncatingRemainder(dividingBy: 1.0)
        let top = Color(hue: hue, saturation: 0.62, brightness: 0.80)
        let bottom = Color(hue: hue2, saturation: 0.85, brightness: 0.42)
        return (top, bottom)
    }

    static func accent(for seed: String) -> Color {
        let h = hash(seed)
        let hue = Double(h % 360) / 360.0
        return Color(hue: hue, saturation: 0.70, brightness: 0.92)
    }
}

// MARK: - Cover Flow geometry
//
// Values mirror the canonical iTunes Cover Flow recreation (Ashish Gogula's
// motion study + Apple's Core Animation behaviour): the centre cover faces the
// viewer flat and sits closest; side covers fan to ±50° and recede in depth,
// stacking at a fixed gap. The single animated `position` value is chased by a
// spring (mass 1, stiffness 150, damping 30) so rapid key taps stay coherent.

struct CoverFlowMetrics {
    var cardSize: CGFloat = 300

    var rotation: Double = 50          // side cover Y rotation, degrees
    var perspective: CGFloat = 1000    // emulates translateZ depth via scale
    var sideDepth: CGFloat = 220       // z push-back of side covers (px)

    var centerGap: CGFloat { cardSize * 0.625 }   // 250 @ 400
    var stackSpacing: CGFloat { cardSize * 0.25 } // 100 @ 400
    var cornerRadius: CGFloat { cardSize * 0.045 }

    /// The spring that drives the whole flow.
    static let spring = Animation.interpolatingSpring(mass: 1, stiffness: 150, damping: 30)
}

/// Layout/visual result for a single card at the current flow position.
struct CardTransform {
    var xOffset: CGFloat
    var angle: Double
    var scale: CGFloat
    var zIndex: Double
    var dim: Double        // 0 = full bright (centre), up to ~0.5 for side cards
    var reflectionOpacity: Double

    static func compute(index: Int, position: Double, m: CoverFlowMetrics) -> CardTransform {
        let pos = Double(index) - position
        let a = abs(pos)

        // rotateY: smooth pass through centre, then clamp to ±rotation.
        let angle: Double = a < 0.5
            ? -pos * (m.rotation * 2)
            : (pos < 0 ? m.rotation : -m.rotation)

        // translateX: tight near centre, fixed stacking gap further out.
        let x: CGFloat
        if a < 1 {
            x = CGFloat(pos) * m.centerGap
        } else {
            let extra = CGFloat(a - 1) * m.stackSpacing
            x = pos < 0 ? -(m.centerGap + extra) : (m.centerGap + extra)
        }

        // translateZ → scale: centre pops to 0 (largest), sides recede.
        let zDepth: CGFloat = a > 0.5 ? m.sideDepth : CGFloat(a) * (m.sideDepth * 2)
        let scale = m.perspective / (m.perspective + zDepth)

        let zIndex = 1000 - a * 10

        // brightness: bright within the central half, then ramp down.
        let dim = min(0.5, max(0, a - 0.15) * 0.55)
        let refl = a < 0.5 ? 0.32 : 0.18

        return CardTransform(xOffset: x, angle: angle, scale: scale,
                             zIndex: zIndex, dim: dim, reflectionOpacity: refl)
    }
}

// MARK: - Shared chrome colors

extension Color {
    static let stageTop = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let stageBottom = Color(red: 0.02, green: 0.02, blue: 0.03)
    static let chrome = Color(red: 0.13, green: 0.13, blue: 0.15)
    static let chromeBorder = Color.white.opacity(0.08)
    static let listAlt = Color.white.opacity(0.03)
}
