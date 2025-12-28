import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: PrinterViewModel

    private var previewAspectRatio: CGFloat? {
        guard let preview = viewModel.previewImage else { return nil }
        return CGFloat(preview.width) / CGFloat(preview.height)
    }

    private var isConnecting: Bool {
        viewModel.connectionState != .connected || !viewModel.isReady
    }

    var body: some View {
        PrinterView(
            previewImage: viewModel.previewImage,
            canPrint: viewModel.canPrint,
            isConnecting: isConnecting,
            onPrint: viewModel.printImage,
            onClear: viewModel.clearImage
        ) {
            DropZone(onImageSelected: viewModel.loadImage)
        }
        .frame(minWidth: 300, minHeight: 300)
        .navigationTitle("")
    }
}

#Preview {
    ContentView(viewModel: PrinterViewModel())
}
