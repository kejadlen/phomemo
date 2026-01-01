import SwiftUI
import CoreGraphics
import AppKit

// MARK: - Image Well

struct ImageWell: NSViewRepresentable {
    var image: CGImage?
    var onImageDropped: (NSImage) -> Void

    func makeNSView(context: Context) -> ObservableImageView {
        let imageView = ObservableImageView()
        imageView.isEditable = true
        imageView.allowsCutCopyPaste = true
        imageView.refusesFirstResponder = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .none
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.onImageChanged = onImageDropped
        return imageView
    }

    func updateNSView(_ nsView: ObservableImageView, context: Context) {
        if let cgImage = image {
            nsView.image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } else {
            nsView.image = nil
        }
    }
}

class ObservableImageView: NSImageView {
    var onImageChanged: ((NSImage) -> Void)?

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let result = super.performDragOperation(sender)
        if result, let image = self.image {
            onImageChanged?(image)
        }
        return result
    }

    @objc func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard) else { return }
        self.image = image
        onImageChanged?(image)
    }
}
