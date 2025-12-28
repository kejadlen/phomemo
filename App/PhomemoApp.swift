import SwiftUI

@main
struct PhomemoApp: App {
    @State private var viewModel = PhomemoViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
    }
}
