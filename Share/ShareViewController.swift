import SwiftUI
import AppKit

class ShareViewController: NSViewController {
    private var viewModel = PrinterViewModel()

    override var nibName: NSNib.Name? {
        nil
    }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        loadSharedImage()

        let shareView = ShareView(
            viewModel: viewModel,
            onCancel: { [weak self] in self?.cancel() },
            onComplete: { [weak self] in self?.complete() }
        )

        let hostingView = NSHostingView(rootView: shareView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func loadSharedImage() {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            return
        }

        var itemProviders: [NSItemProvider] = []

        for item in inputItems {
            if let attachments = item.attachments {
                itemProviders.append(contentsOf: attachments)
            }
        }

        viewModel.loadImage(from: itemProviders)
    }

    private func cancel() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: error)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

// MARK: - SwiftUI View

struct ShareView: View {
    @Bindable var viewModel: PrinterViewModel
    let onCancel: () -> Void
    let onComplete: () -> Void

    private var isConnecting: Bool {
        viewModel.connectionState != .connected || !viewModel.isReady
    }

    var body: some View {
        PrinterView(
            previewImage: viewModel.previewImage,
            canPrint: viewModel.canPrint,
            isConnecting: isConnecting,
            onPrint: viewModel.printImage,
            onClear: onCancel
        ) {
            ImagePreviewPlaceholder()
        }
        .frame(width: 400, height: 400)
        .onChange(of: viewModel.printCompleted) { _, completed in
            if completed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
    }
}
