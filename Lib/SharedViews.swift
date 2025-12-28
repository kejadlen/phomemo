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

// MARK: - Print Button

struct PrintButton: View {
    let action: () -> Void
    var disabled: Bool = false
    var fullWidth: Bool = false

    var body: some View {
        Button(action: action) {
            if fullWidth {
                Label("Print", systemImage: "printer")
                    .frame(maxWidth: .infinity)
            } else {
                Label("Print", systemImage: "printer")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled)
    }
}

// MARK: - Status Icon

enum StatusIconState {
    case loading
    case ready
    case error
}

struct StatusIcon: View {
    let state: StatusIconState
    var scale: CGFloat = 1.0

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .scaleEffect(scale)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Drop Zone

struct DropZone: View {
    let onImageSelected: (URL) -> Void
    var isDisabled: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Drop image here")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Button("Open Image...", action: openFilePicker)
                    .disabled(isDisabled)
            }
        }
        .frame(height: 200)
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

// MARK: - Status Row

struct StatusRow: View {
    let iconState: StatusIconState
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            StatusIcon(state: iconState, scale: 0.8)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Printer View

struct PrinterView<LeadingButton: View, DropContent: View>: View {
    let previewImage: CGImage?
    let originalImage: CGImage?
    let statusIconState: StatusIconState
    let statusMessage: String
    let canPrint: Bool
    let onPrint: () -> Void
    let leadingButton: () -> LeadingButton
    let dropContent: () -> DropContent

    init(
        previewImage: CGImage?,
        originalImage: CGImage? = nil,
        statusIconState: StatusIconState,
        statusMessage: String,
        canPrint: Bool,
        onPrint: @escaping () -> Void,
        @ViewBuilder leadingButton: @escaping () -> LeadingButton = { EmptyView() },
        @ViewBuilder dropContent: @escaping () -> DropContent = { EmptyView() }
    ) {
        self.previewImage = previewImage
        self.originalImage = originalImage
        self.statusIconState = statusIconState
        self.statusMessage = statusMessage
        self.canPrint = canPrint
        self.onPrint = onPrint
        self.leadingButton = leadingButton
        self.dropContent = dropContent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                leadingButton()
                Spacer()
                StatusRow(iconState: statusIconState, message: statusMessage)
            }
            .padding()

            Divider()

            // Content
            VStack(spacing: 20) {
                if let preview = previewImage {
                    if let original = originalImage {
                        HStack(spacing: 20) {
                            ImagePreview(image: original, caption: "Original")
                            ImagePreview(image: preview, caption: "Print Preview")
                        }
                    } else {
                        ImagePreview(image: preview, maxHeight: 250)
                    }
                } else {
                    dropContent()
                }

                PrintButton(action: onPrint, disabled: !canPrint, fullWidth: true)
                    .controlSize(.large)
            }
            .padding()
        }
    }
}
