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
    var previewImage: CGImage?
    private var phomemoImage: PhomemoImage?

    private var writer: PhomemoWriter?

    var canPrint: Bool {
        connectionState == .connected && isReady && previewImage != nil && !isPrinting
    }

    init() {
        startScanning()
    }

    func startScanning() {
        connectionState = .scanning
        writer = PhomemoWriter(delegate: self)
    }

    func loadImage(from url: URL) {
        guard let image = PhomemoImage(url: url) else {
            return
        }

        phomemoImage = image
        previewImage = image.toMonochrome(dithered: true)
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
        writer?.printImage(image)
    }

    func clearImage() {
        previewImage = nil
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
        isReady = true
    }

    func writer(_ writer: PhomemoWriter, didUpdatePaperStatus hasPaper: Bool) {
        self.hasPaper = hasPaper
        self.isReady = hasPaper && coverClosed && temperatureOK
    }

    func writer(_ writer: PhomemoWriter, didUpdateCoverStatus closed: Bool) {
        self.coverClosed = closed
        self.isReady = hasPaper && coverClosed && temperatureOK
    }

    func writer(_ writer: PhomemoWriter, didUpdateTemperatureStatus ok: Bool) {
        self.temperatureOK = ok
        self.isReady = hasPaper && coverClosed && temperatureOK
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
