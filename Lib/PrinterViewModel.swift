import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers

@Observable
final class PrinterViewModel: PhomemoWriterDelegate {
    // Connection state
    var connectionState: ConnectionState = .disconnected

    // Printer status
    var hasPaper: Bool = true
    var coverClosed: Bool = true
    var temperatureOK: Bool = true
    var isReady: Bool = false
    var isPrinting: Bool = false
    var printCompleted: Bool = false

    // Image state
    var originalImage: CGImage?
    var previewImage: CGImage?
    var imageURL: URL?

    // Status message
    var statusMessage: String = ""

    private var writer: PhomemoWriter?

    var canPrint: Bool {
        connectionState == .connected && isReady && originalImage != nil && !isPrinting
    }

    init() {
        startScanning()
    }

    func startScanning() {
        connectionState = .scanning
        statusMessage = "Searching for printer..."
        writer = PhomemoWriter(delegate: self)
    }

    func loadImage(from url: URL) {
        imageURL = url

        guard let phomemoImage = PhomemoImage(url: url) else {
            return
        }

        originalImage = phomemoImage.cgImage
        previewImage = phomemoImage.toMonochrome(dithered: true)
    }

    func loadImage(from itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first else { return }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                guard let data else { return }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("png")
                do {
                    try data.write(to: tempURL)
                    DispatchQueue.main.async {
                        self?.loadImage(from: tempURL)
                    }
                } catch {}
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        self?.loadImage(from: url)
                    }
                }
            }
        }
    }

    func printImage() {
        guard let url = imageURL, canPrint else { return }
        isPrinting = true
        writer?.printImage(from: url)
        statusMessage = "Printing..."
    }

    func clearImage() {
        originalImage = nil
        previewImage = nil
        imageURL = nil
    }

    // MARK: - PhomemoWriterDelegate

    func writerDidStartScanning(_ writer: PhomemoWriter) {
        connectionState = .scanning
        statusMessage = "Searching for printer..."
    }

    func writerDidConnect(_ writer: PhomemoWriter) {
        connectionState = .connecting
        statusMessage = "Connecting..."
    }

    func writerDidBecomeReady(_ writer: PhomemoWriter) {
        connectionState = .connected
        isReady = true
        updateStatusMessage()
    }

    func writer(_ writer: PhomemoWriter, didUpdatePaperStatus hasPaper: Bool) {
        self.hasPaper = hasPaper
        self.isReady = hasPaper && coverClosed && temperatureOK
        updateStatusMessage()
    }

    func writer(_ writer: PhomemoWriter, didUpdateCoverStatus closed: Bool) {
        self.coverClosed = closed
        self.isReady = hasPaper && coverClosed && temperatureOK
        updateStatusMessage()
    }

    func writer(_ writer: PhomemoWriter, didUpdateTemperatureStatus ok: Bool) {
        self.temperatureOK = ok
        self.isReady = hasPaper && coverClosed && temperatureOK
        updateStatusMessage()
    }

    func writerDidCompletePrint(_ writer: PhomemoWriter) {
        isPrinting = false
        printCompleted = true
        statusMessage = "Print complete!"
    }

    func writer(_ writer: PhomemoWriter, didFailWithError error: String) {
        isPrinting = false
        statusMessage = error
        if connectionState == .scanning || connectionState == .connecting {
            connectionState = .disconnected
        }
    }

    private func updateStatusMessage() {
        if !hasPaper {
            statusMessage = "No paper"
        } else if !coverClosed {
            statusMessage = "Cover open"
        } else if !temperatureOK {
            statusMessage = "Too hot - cooling down"
        } else if connectionState == .connected && isReady {
            statusMessage = "Ready"
        }
    }
}
