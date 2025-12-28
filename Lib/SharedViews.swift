import SwiftUI
import CoreGraphics

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
}

// MARK: - Connection Indicator

struct ConnectionIndicator: View {
    let state: ConnectionState
    var isReady: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 10, height: 10)
            Text(indicatorText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var indicatorColor: Color {
        switch state {
        case .disconnected: return .red
        case .scanning, .connecting: return .yellow
        case .connected: return isReady ? .green : .yellow
        }
    }

    private var indicatorText: String {
        switch state {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return isReady ? "Ready" : "Initializing..."
        }
    }
}

// MARK: - Status Item

struct StatusItem: View {
    let icon: String
    let text: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(ok ? .green : .red)
            Text(text)
                .font(.caption)
        }
    }
}
