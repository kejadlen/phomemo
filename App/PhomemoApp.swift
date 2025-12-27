import SwiftUI

@main
struct PhomemoApp: App {
    @State private var viewModel = PrinterViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
    }
}
