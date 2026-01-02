import SwiftUI

@main
struct FauxmemoApp: App {
    @State private var viewModel = FauxmemoViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
