import Foundation
import SwiftUI

/// High-level classification of a project, inferred from its files.
enum ProjectKind: String, Codable, CaseIterable {
    case web
    case mobile
    case desktop
    case backend
    case dataML
    case tool
    case game
    case library
    case other

    var label: String {
        switch self {
        case .web:     return "Web App"
        case .mobile:  return "Mobile App"
        case .desktop: return "Desktop App"
        case .backend: return "Backend"
        case .dataML:  return "Data / ML"
        case .tool:    return "Tool"
        case .game:    return "Game"
        case .library: return "Library"
        case .other:   return "Project"
        }
    }

    /// SF Symbol used in the list + as the glyph on generated covers.
    var symbol: String {
        switch self {
        case .web:     return "globe"
        case .mobile:  return "iphone"
        case .desktop: return "macwindow"
        case .backend: return "server.rack"
        case .dataML:  return "chart.xyaxis.line"
        case .tool:    return "wrench.and.screwdriver"
        case .game:    return "gamecontroller"
        case .library: return "shippingbox"
        case .other:   return "folder"
        }
    }

    /// Color tied to the project Type — used in the now-playing box and list.
    var color: Color {
        switch self {
        case .web:     return Color(red: 0.30, green: 0.62, blue: 1.00)
        case .mobile:  return Color(red: 0.32, green: 0.82, blue: 0.52)
        case .desktop: return Color(red: 0.68, green: 0.52, blue: 1.00)
        case .backend: return Color(red: 1.00, green: 0.62, blue: 0.32)
        case .dataML:  return Color(red: 0.28, green: 0.82, blue: 0.80)
        case .tool:    return Color(red: 0.96, green: 0.80, blue: 0.36)
        case .game:    return Color(red: 1.00, green: 0.46, blue: 0.62)
        case .library: return Color(red: 0.82, green: 0.62, blue: 0.46)
        case .other:   return Color(red: 0.64, green: 0.68, blue: 0.74)
        }
    }
}

/// Where a project's cover artwork comes from.
enum CoverSource: Hashable {
    case pending             // not resolved yet
    case image(URL)          // a cached square thumbnail on disk
    case generated           // draw a metadata cover natively
}

struct Project: Identifiable, Hashable {
    let id: String           // absolute path, stable identity
    let name: String
    let url: URL
    let displayPath: String  // ~/… form
    var kind: ProjectKind
    var language: String
    var sizeBytes: Int64?    // nil until computed in the background
    var lastModified: Date
    var cover: CoverSource
    var isFavorite: Bool = false
    var summary: String? = nil      // short phrase from README / manifest

    /// Two-stop gradient seed colors, deterministic from the project name.
    var palette: (Color, Color) { Palette.gradient(for: name) }
    var accent: Color { Palette.accent(for: name) }

    /// Initials shown on a generated cover (up to 2 chars).
    var initials: String {
        let cleaned = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let words = cleaned.split(separator: " ").filter { !$0.isEmpty }
        if let first = words.first?.first {
            if words.count >= 2, let second = words[1].first {
                return String(first).uppercased() + String(second).uppercased()
            }
            return String(first).uppercased()
        }
        return "•"
    }

    /// Non-optional key for Table column sorting.
    var sizeSortKey: Int64 { sizeBytes ?? 0 }

    var sizeLabel: String {
        guard let bytes = sizeBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var lastModifiedLabel: String { DateFmt.relative(lastModified) }
}

enum DateFmt {
    static func relative(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter(); f.dateFormat = "'Today,' h:mm a"; return f.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            let f = DateFormatter(); f.dateFormat = "'Yesterday,' h:mm a"; return f.string(from: date)
        }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: date)
    }
}
