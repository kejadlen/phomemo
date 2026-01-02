import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var viewModel: FauxmemoViewModel

    var body: some View {
        ImageWell(image: viewModel.previewImage, onImageDropped: viewModel.loadImage)
            .frame(minWidth: 300, minHeight: 300)
            .overlay { dropHint }
            .overlay(alignment: .topTrailing) { clearButton }
            .overlay(alignment: .bottom) {
                actionButton
                    .padding()
            }
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
    private var actionButton: some View {
        if viewModel.previewImage == nil {
            Button("Open Image...", action: openFilePicker)
                .buttonStyle(.glass)
                .tint(.accentColor)
                .controlSize(.extraLarge)
                .frame(maxWidth: .infinity)
        } else if viewModel.isConnecting {
            ProgressView()
                .controlSize(.regular)
                .frame(maxWidth: .infinity)
        } else {
            Button(action: viewModel.printImage) {
                Label("Print", systemImage: "printer.fill")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(.accentColor)
            .controlSize(.extraLarge)
            .disabled(!viewModel.canPrint)
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
    private var dropHint: some View {
        if viewModel.previewImage == nil {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .light))
                Text("Drop image here")
                    .font(.title3)
            }
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
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
}

#Preview {
    ContentView(viewModel: FauxmemoViewModel())
}
