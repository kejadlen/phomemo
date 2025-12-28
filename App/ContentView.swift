import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: PrinterViewModel

    private var statusIconState: StatusIconState {
        switch viewModel.connectionState {
        case .disconnected:
            return .error
        case .scanning, .connecting:
            return .loading
        case .connected:
            return viewModel.isReady ? .ready : .loading
        }
    }

    var body: some View {
        PrinterView(
            previewImage: viewModel.previewImage,
            originalImage: viewModel.originalImage,
            statusIconState: statusIconState,
            statusMessage: viewModel.statusMessage,
            canPrint: viewModel.canPrint,
            onPrint: viewModel.printImage
        ) {
            Button("Clear") {
                viewModel.clearImage()
            }
            .opacity(viewModel.originalImage != nil ? 1 : 0)
        } dropContent: {
            DropZone(
                onImageSelected: viewModel.loadImage,
                isDisabled: !viewModel.canLoadImage
            )
        }
        .frame(minWidth: 500)
    }
}

#Preview {
    ContentView(viewModel: PrinterViewModel())
}
