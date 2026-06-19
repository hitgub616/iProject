import SwiftUI

/// The bottom detail list — Finder-style sortable columns, shared selection
/// with the Cover Flow. Click a header to sort; up/down moves selection, which
/// drives the flow.
struct ProjectListView: View {
    let projects: [Project]
    @Binding var selectedID: Project.ID?
    @Binding var sortOrder: [KeyPathComparator<Project>]
    let store: LibraryStore

    var body: some View {
        Table(projects, selection: $selectedID, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { p in
                HStack(spacing: 8) {
                    Button {
                        store.toggleFavorite(p.id)
                    } label: {
                        Image(systemName: p.isFavorite ? "star.fill" : "folder.fill")
                            .foregroundStyle(p.isFavorite ? Color.yellow : p.accent)
                    }
                    .buttonStyle(.plain)
                    .help(p.isFavorite ? "Remove from Favorites" : "Add to Favorites")

                    Text(p.name).fontWeight(.medium)
                }
            }
            .width(min: 150, ideal: 220)

            TableColumn("Path", value: \.displayPath) { p in
                Text(p.displayPath).foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 210)

            TableColumn("Type", value: \.kind.label) { p in
                Label(p.kind.label, systemImage: p.kind.symbol)
                    .labelStyle(.titleOnly)
                    .foregroundStyle(p.kind.color)
            }
            .width(min: 74, ideal: 100)

            TableColumn("Language", value: \.language) { p in
                Text(p.language).foregroundStyle(p.accent.opacity(0.9))
            }
            .width(min: 68, ideal: 94)

            TableColumn("Last Modified", value: \.lastModified) { p in
                Text(p.lastModifiedLabel).foregroundStyle(.secondary)
            }
            .width(min: 106, ideal: 130)

            TableColumn("Size", value: \.sizeSortKey) { p in
                Text(p.sizeLabel).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 56, ideal: 78)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollIndicators(.hidden, axes: .horizontal)
        .contextMenu(forSelectionType: Project.ID.self) { ids in
            if let id = ids.first, let p = projects.first(where: { $0.id == id }) {
                ForEach(Launcher.allCases) { app in
                    Button("Start with \(app.displayName)") { app.launch(p) }
                        .disabled(!app.isInstalled)
                }
                Divider()
                Button("Set Cover from Image…") { store.presentSetCover(for: id) }
                if store.isCustomCover(id) {
                    Button("Reset Cover") { store.resetCover(for: id) }
                }
                Divider()
                Button("Open in Finder") { openInFinder(p.url) }
                Button("Open with Terminal") { openInTerminal(p.url) }
                Divider()
                Button(store.isFavorite(id) ? "Remove from Favorites" : "Add to Favorites") {
                    store.toggleFavorite(id)
                }
                if store.isAdded(id) {
                    Button("Remove from Library", role: .destructive) {
                        store.removeFromLibrary(id)
                    }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let p = projects.first(where: { $0.id == id }) {
                openInFinder(p.url)
            }
        }
    }

    private func openInTerminal(_ url: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
