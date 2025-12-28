import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers
import AppKit

// MARK: - Connection State

enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
}

// MARK: - Image Preview

struct ImagePreview: View {
    let image: CGImage
    var caption: String?
    var maxHeight: CGFloat = 200

    var body: some View {
        VStack {
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(decorative: image, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: maxHeight)
                .background(Color(white: 0.95))
                .cornerRadius(8)
        }
    }
}

// MARK: - Image Preview Placeholder

struct ImagePreviewPlaceholder: View {
    var height: CGFloat = 200
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(white: 0.95))
            .frame(height: height)
            .overlay {
                ProgressView()
            }
    }
}

// MARK: - Drop Zone

struct DropZone: View {
    let onImageSelected: (URL) -> Void
    var isDisabled: Bool = false

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Drop image here")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button("Open Image...", action: openFilePicker)
                    .buttonStyle(.bordered)
                    .disabled(isDisabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: handleDrop)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            onImageSelected(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        onImageSelected(url)
                    }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        onImageSelected(url)
                    }
                }
            }
            return true
        }

        return false
    }
}

// MARK: - Phomemo View

struct PhomemoView<DropContent: View>: View {
    @Bindable var viewModel: PhomemoViewModel
    let onCancel: () -> Void
    let dropContent: () -> DropContent

    init(
        viewModel: PhomemoViewModel,
        onCancel: @escaping () -> Void,
        @ViewBuilder dropContent: @escaping () -> DropContent
    ) {
        self.viewModel = viewModel
        self.onCancel = onCancel
        self.dropContent = dropContent
    }

    private var isConnecting: Bool {
        viewModel.connectionState != .connected || !viewModel.isReady
    }

    var body: some View {
        Group {
            if let preview = viewModel.previewImage {
                Image(decorative: preview, scale: 1.0)
                    .resizable()
            } else {
                dropContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            if viewModel.previewImage != nil {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding()
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.previewImage != nil {
                Group {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                    } else {
                        Button(action: viewModel.printImage) {
                            Label("Print", systemImage: "printer")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!viewModel.canPrint)
                    }
                }
                .padding()
            }
        }
    }
}
