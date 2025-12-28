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
        HStack(spacing: 6) {
            Circle()
                .fill(connectionColor)
                .frame(width: 10, height: 10)
            Text(connectionText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .disconnected: return .red
        case .scanning: return .yellow
        case .connecting: return .yellow
        case .connected: return viewModel.isReady ? .green : .yellow
        }
    }

    private var connectionText: String {
        switch viewModel.connectionState {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return viewModel.isReady ? "Ready" : "Initializing..."
        }
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

                Button {
                    viewModel.printImage()
                } label: {
                    Label("Print", systemImage: "printer")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canPrint)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private func imagePreviewRow(original: CGImage, preview: CGImage) -> some View {
        HStack(spacing: 20) {
            VStack {
                Text("Original")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(decorative: original, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .background(Color(white: 0.95))
                    .cornerRadius(8)
            }

            VStack {
                Text("Print Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(decorative: preview, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .background(Color(white: 0.95))
                    .cornerRadius(8)
            }
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
            statusItem(
                icon: viewModel.hasPaper ? "doc.fill" : "doc",
                text: viewModel.hasPaper ? "Paper OK" : "No Paper",
                ok: viewModel.hasPaper
            )

            statusItem(
                icon: viewModel.temperatureOK ? "thermometer.medium" : "thermometer.high",
                text: viewModel.temperatureOK ? "Temp OK" : "Too Hot",
                ok: viewModel.temperatureOK
            )

            statusItem(
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

    private func statusItem(icon: String, text: String, ok: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(ok ? .green : .red)
            Text(text)
                .font(.caption)
        }
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
