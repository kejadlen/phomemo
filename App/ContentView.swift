import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var viewModel: PrinterViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if viewModel.canLoadImage || viewModel.originalImage != nil {
                imageContent
            } else {
                scanningContent
            }

            Divider()
            statusBar
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Phomemo Printer")
                .font(.headline)
            Spacer()
            connectionIndicator
        }
        .padding()
    }

    private var connectionIndicator: some View {
        ConnectionIndicator(state: viewModel.connectionState, isReady: viewModel.isReady)
    }

    // MARK: - Scanning State

    private var scanningContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text(viewModel.statusMessage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Image Content

    private var imageContent: some View {
        VStack(spacing: 16) {
            if let original = viewModel.originalImage,
               let preview = viewModel.previewImage {
                imagePreviewRow(original: original, preview: preview)
            } else {
                dropZone
            }

            HStack(spacing: 12) {
                Button("Open Image...") {
                    openFilePicker()
                }
                .disabled(!viewModel.canLoadImage)

                if viewModel.originalImage != nil {
                    Button("Clear") {
                        viewModel.clearImage()
                    }
                }

                Spacer()

                PrintButton(action: viewModel.printImage, disabled: !viewModel.canPrint)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private func imagePreviewRow(original: CGImage, preview: CGImage) -> some View {
        HStack(spacing: 20) {
            ImagePreview(image: original, caption: "Original")
            ImagePreview(image: preview, caption: "Print Preview")
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Drop image here")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("or click Open Image")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 200)
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            StatusItem(
                icon: viewModel.hasPaper ? "doc.fill" : "doc",
                text: viewModel.hasPaper ? "Paper OK" : "No Paper",
                ok: viewModel.hasPaper
            )

            StatusItem(
                icon: viewModel.temperatureOK ? "thermometer.medium" : "thermometer.high",
                text: viewModel.temperatureOK ? "Temp OK" : "Too Hot",
                ok: viewModel.temperatureOK
            )

            StatusItem(
                icon: viewModel.coverClosed ? "door.left.hand.closed" : "door.left.hand.open",
                text: viewModel.coverClosed ? "Cover Closed" : "Cover Open",
                ok: viewModel.coverClosed
            )

            Spacer()

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadImage(from: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        viewModel.loadImage(from: url)
                    }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        viewModel.loadImage(from: url)
                    }
                }
            }
            return true
        }

        return false
    }
}

#Preview {
    ContentView(viewModel: PrinterViewModel())
}
