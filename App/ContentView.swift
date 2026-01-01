import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var viewModel: PhomemoViewModel

    var body: some View {
        ImageWell(image: viewModel.previewImage, onImageDropped: viewModel.loadImage)
            .frame(minWidth: 300, minHeight: 300)
            .overlay { openButton }
            .overlay(alignment: .topTrailing) { clearButton }
            .overlay(alignment: .bottomTrailing) { printButton }
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

    @ViewBuilder
    private var openButton: some View {
        if viewModel.previewImage == nil {
            Button("Open Image...", action: openFilePicker)
                .buttonStyle(.bordered)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadImage(from: url)
        }
    }

    @ViewBuilder
    private var clearButton: some View {
        if viewModel.previewImage != nil {
            Button(action: viewModel.clearImage) {
                Image(systemName: "xmark")
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    @ViewBuilder
    private var printButton: some View {
        if viewModel.previewImage != nil {
            if viewModel.isConnecting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .padding(10)
            } else {
                Button(action: viewModel.printImage) {
                    Image(systemName: "printer.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(!viewModel.canPrint)
                .padding(10)
            }
        }
    }
}

#Preview {
    ContentView(viewModel: PhomemoViewModel())
}
