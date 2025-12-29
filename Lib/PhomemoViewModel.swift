import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers

@Observable
final class PhomemoViewModel: PhomemoWriterDelegate {
    // Connection state
    var connectionState: ConnectionState = .disconnected

    // Printer status
    private var hasPaper: Bool = true
    private var coverClosed: Bool = true
    private var temperatureOK: Bool = true
    private var printerConnected: Bool = false
    var isPrinting: Bool = false

    var isReady: Bool {
        printerConnected && hasPaper && coverClosed && temperatureOK
    }
    var printCompleted: Bool = false

    // Image state
    private var phomemoImage: PhomemoImage?

    private var writer: PhomemoWriter!

    var canPrint: Bool {
        connectionState == .connected && isReady && previewImage != nil && !isPrinting
    }

    var previewImage: CGImage? {
        self.phomemoImage?.dithered
    }

    init() {
        connectionState = .scanning
        writer = PhomemoWriter(delegate: self)
    }

    func loadImage(from url: URL) {
        guard let image = PhomemoImage(url: url) else {
            return
        }

        phomemoImage = image
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
        guard let image = phomemoImage, canPrint else { return }
        isPrinting = true
        writer.printImage(image)
    }

    func clearImage() {
        phomemoImage = nil
    }

    // MARK: - PhomemoWriterDelegate

    func writerDidStartScanning(_ writer: PhomemoWriter) {
        connectionState = .scanning
    }

    func writerDidConnect(_ writer: PhomemoWriter) {
        connectionState = .connecting
    }

    func writerDidBecomeReady(_ writer: PhomemoWriter) {
        connectionState = .connected
        printerConnected = true
    }

    func writer(_ writer: PhomemoWriter, didUpdatePaperStatus hasPaper: Bool) {
        self.hasPaper = hasPaper
    }

    func writer(_ writer: PhomemoWriter, didUpdateCoverStatus closed: Bool) {
        self.coverClosed = closed
    }

    func writer(_ writer: PhomemoWriter, didUpdateTemperatureStatus ok: Bool) {
        self.temperatureOK = ok
    }

    func writerDidCompletePrint(_ writer: PhomemoWriter) {
        isPrinting = false
        printCompleted = true
    }

    func writer(_ writer: PhomemoWriter, didFailWithError error: String) {
        isPrinting = false
        if connectionState == .scanning || connectionState == .connecting {
            connectionState = .disconnected
        }
    }
}
