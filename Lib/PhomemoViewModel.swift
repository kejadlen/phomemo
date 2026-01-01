import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers
import AppKit

@Observable
final class PhomemoViewModel: PhomemoManagerDelegate {
    private(set) var state: PrinterState = .disconnected
    private var phomemoImage: PhomemoImage?
    private var manager: PhomemoManager!

    private(set) var printCompleted: Bool = false

    var canPrint: Bool {
        if case .ready = state, previewImage != nil { return true }
        return false
    }

    var isConnecting: Bool {
        switch state {
        case .disconnected, .scanning, .connecting:
            return true
        case .ready, .printing, .notReady, .error:
            return false
        }
    }

    var previewImage: CGImage? {
        phomemoImage?.dithered
    }

    init() {
        manager = PhomemoManager(delegate: self)
    }

    func loadImage(from url: URL) {
        guard let image = PhomemoImage(url: url) else {
            return
        }

        phomemoImage = image
    }

    func loadImage(from nsImage: NSImage) {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let image = PhomemoImage(cgImage: cgImage) else {
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
        guard case .ready(let printer) = state, let image = phomemoImage else { return }
        printer.print(image)
    }

    func clearImage() {
        phomemoImage = nil
    }

    // MARK: - PhomemoManagerDelegate

    func manager(_ manager: PhomemoManager, didChangeState state: PrinterState) {
        // Detect print completion: .printing → .ready
        if case .printing = self.state, case .ready = state {
            printCompleted = true
        }
        self.state = state
    }
}
