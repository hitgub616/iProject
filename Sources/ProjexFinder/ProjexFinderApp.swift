import SwiftUI

@main
struct ProjexFinderApp: App {
    @State private var store = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1040, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Folder to Library…") { store.presentAddFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Add File to Library…") { store.presentAddFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Change Workspace Folder…") { store.presentChooseRoot() }
                Divider()
            }
            CommandGroup(after: .toolbar) {
                Button("Rescan Workspace") { store.load() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
