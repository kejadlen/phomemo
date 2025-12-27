import SwiftUI
import AppKit

class ShareViewController: NSViewController {
    private var viewModel = ShareViewModel()

    override var nibName: NSNib.Name? {
        // Return nil to skip NIB loading - we use SwiftUI
        return nil
    }

    override func loadView() {
        // Create the view programmatically
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Extract image from share extension context
        loadSharedImage()

        // Set up SwiftUI view
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
    @Bindable var viewModel: ShareViewModel
    let onCancel: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                Spacer()
                Text("Print to Phomemo")
                    .font(.headline)
                Spacer()
                // Spacer for symmetry
                Button("Cancel") {}
                    .buttonStyle(.plain)
                    .hidden()
            }
            .padding()

            Divider()

            VStack(spacing: 20) {
                // Preview
                if let preview = viewModel.previewImage {
                    Image(decorative: preview, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 250)
                        .background(Color(white: 0.95))
                        .cornerRadius(12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.95))
                        .frame(height: 200)
                        .overlay {
                            ProgressView()
                        }
                }

                // Status
                HStack(spacing: 8) {
                    if viewModel.state == .loading || viewModel.state == .printing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if viewModel.state == .ready {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if case .error = viewModel.state {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }

                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Print button
                Button(action: {
                    viewModel.printImage()
                }) {
                    Label("Print", systemImage: "printer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canPrint)
            }
            .padding()
        }
        .frame(width: 400, height: 450)
        .onChange(of: viewModel.state) { _, newState in
            if newState == .completed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
    }
}
