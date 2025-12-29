import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var viewModel: PhomemoViewModel

    var body: some View {
        PhomemoView(viewModel: viewModel, onCancel: viewModel.clearImage) {
            DropZone(onImageSelected: viewModel.loadImage)
        }
        .frame(minWidth: 300, minHeight: 300)
        .navigationTitle("")
        .onChange(of: viewModel.previewImage) { _, newImage in
            guard let window = NSApp.keyWindow else { return }

            if let image = newImage {
                let aspectRatio = CGFloat(image.width) / CGFloat(image.height)
                let currentHeight = window.contentView?.bounds.height ?? 400
                let newWidth = currentHeight * aspectRatio

                window.setContentSize(NSSize(width: newWidth, height: currentHeight))
                window.contentAspectRatio = NSSize(width: aspectRatio, height: 1)
            } else {
                window.contentAspectRatio = NSSize.zero
            }
        }
    }
}

#Preview {
    ContentView(viewModel: PhomemoViewModel())
}
