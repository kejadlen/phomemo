import SwiftUI
import AppKit

class ShareViewController: NSViewController {
    private var viewModel = FauxmemoViewModel()

    override var nibName: NSNib.Name? {
        nil
    }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 450))
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
    @Bindable var viewModel: FauxmemoViewModel
    let onCancel: () -> Void
    let onComplete: () -> Void

    @FocusState private var isPrintFocused: Bool

    private var isConnecting: Bool {
        viewModel.isConnecting
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Fauxmemo")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

            Divider()

            // Content
            ZStack {
                Color.white
                if let preview = viewModel.previewImage {
                    Image(decorative: preview, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                }
            }

            Divider()

            // Footer
            HStack {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Print", action: viewModel.printImage)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canPrint)
                    .focused($isPrintFocused)
            }
            .padding()
        }
        .frame(width: 340, height: 450)
        .onChange(of: viewModel.canPrint) { _, canPrint in
            if canPrint {
                isPrintFocused = true
            }
        }
        .onChange(of: viewModel.printCompleted) { _, completed in
            if completed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
    }
}
