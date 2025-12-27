import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers

enum ShareState: Equatable {
    case loading
    case ready
    case printing
    case completed
    case error(String)
}

@Observable
final class ShareViewModel: PhomemoWriterDelegate {
    // Image state
    var previewImage: CGImage?
    var imageURL: URL?
    private var imageLoaded = false

    // Printer state
    var printerConnected = false
    var printerReady = false

    // Overall state
    var state: ShareState = .loading
    var statusMessage = "Loading..."

    private var writer: PhomemoWriter?
    private var scanTimeoutTask: Task<Void, Never>?

    var canPrint: Bool {
        imageLoaded && printerConnected && printerReady && state == .ready
    }

    init() {
        startPrinterScan()
    }

    deinit {
        scanTimeoutTask?.cancel()
    }

    // MARK: - Image Loading

    func loadImage(from itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first else {
            state = .error("No image found")
            statusMessage = "No image found"
            return
        }

        // Try loading as image data
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
                DispatchQueue.main.async {
                    self?.handleImageData(data, error: error)
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
                DispatchQueue.main.async {
                    if let url = item as? URL {
                        self?.handleImageURL(url)
                    } else {
                        self?.state = .error("Failed to load image")
                        self?.statusMessage = "Failed to load image"
                    }
                }
            }
        } else {
            state = .error("Unsupported image format")
            statusMessage = "Unsupported image format"
        }
    }

    private func handleImageData(_ data: Data?, error: Error?) {
        guard let data = data else {
            state = .error("Failed to load image")
            statusMessage = "Failed to load image"
            return
        }

        // Write to temp file for PhomemoImage
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        do {
            try data.write(to: tempURL)
            handleImageURL(tempURL)
        } catch {
            state = .error("Failed to process image")
            statusMessage = "Failed to process image"
        }
    }

    private func handleImageURL(_ url: URL) {
        imageURL = url

        guard let phomemoImage = PhomemoImage(url: url) else {
            state = .error("Failed to convert image")
            statusMessage = "Failed to convert image"
            return
        }

        previewImage = phomemoImage.toMonochrome(dithered: true)
        imageLoaded = true
        updateState()
    }

    // MARK: - Printer Connection

    private func startPrinterScan() {
        writer = PhomemoWriter(delegate: self)

        // 30 second timeout
        scanTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if !printerConnected {
                state = .error("Printer not found")
                statusMessage = "Printer not found. Make sure it's on."
            }
        }
    }

    // MARK: - Printing

    func printImage() {
        guard let url = imageURL, canPrint else { return }

        state = .printing
        statusMessage = "Printing..."
        writer?.printImage(from: url)
    }

    // MARK: - State Management

    private func updateState() {
        if case .error = state { return }
        if case .printing = state { return }
        if case .completed = state { return }

        if !imageLoaded {
            state = .loading
            statusMessage = "Loading..."
        } else if !printerConnected {
            state = .loading
            statusMessage = "Searching for printer..."
        } else if !printerReady {
            state = .loading
            statusMessage = "Connecting..."
        } else {
            state = .ready
            statusMessage = "Ready"
        }
    }

    // MARK: - PhomemoWriterDelegate

    func writerDidStartScanning(_ writer: PhomemoWriter) {
        updateState()
    }

    func writerDidConnect(_ writer: PhomemoWriter) {
        printerConnected = true
        scanTimeoutTask?.cancel()
        updateState()
    }

    func writerDidBecomeReady(_ writer: PhomemoWriter) {
        printerReady = true
        updateState()
    }

    func writer(_ writer: PhomemoWriter, didUpdatePaperStatus hasPaper: Bool) {
        if !hasPaper {
            state = .error("No paper")
            statusMessage = "No paper in printer"
        }
    }

    func writer(_ writer: PhomemoWriter, didUpdateCoverStatus closed: Bool) {
        if !closed {
            state = .error("Cover open")
            statusMessage = "Close the printer cover"
        }
    }

    func writer(_ writer: PhomemoWriter, didUpdateTemperatureStatus ok: Bool) {
        if !ok {
            state = .error("Too hot")
            statusMessage = "Printer too hot - wait to cool down"
        }
    }

    func writerDidCompletePrint(_ writer: PhomemoWriter) {
        state = .completed
        statusMessage = "Done!"
    }

    func writer(_ writer: PhomemoWriter, didFailWithError error: String) {
        state = .error(error)
        statusMessage = error
    }
}
