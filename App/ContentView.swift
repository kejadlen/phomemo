import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: PhomemoViewModel

    var body: some View {
        PhomemoView(viewModel: viewModel, onClear: viewModel.clearImage) {
            DropZone(onImageSelected: viewModel.loadImage)
        }
        .frame(minWidth: 300, minHeight: 300)
        .navigationTitle("")
    }
}

#Preview {
    ContentView(viewModel: PhomemoViewModel())
}
