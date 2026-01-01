# PhomemoManager Typestate Refactor

## Goal

Refactor PhomemoManager to use the typestate pattern, simplifying the delegate from 8 methods to 1 state-change callback.

## Core Types

```swift
struct NotReadyReason: OptionSet {
    let rawValue: Int
    static let noPaper    = NotReadyReason(rawValue: 1 << 0)
    static let coverOpen  = NotReadyReason(rawValue: 1 << 1)
    static let overheated = NotReadyReason(rawValue: 1 << 2)
}

enum PrinterState {
    case disconnected
    case scanning
    case connecting
    case ready(ReadyPrinter)
    case printing
    case notReady(NotReadyReason)
    case error(String)
}

struct ReadyPrinter {
    private let manager: PhomemoManager

    func print(_ image: PhomemoImage) {
        manager.printImage(image)
    }
}
```

`ReadyPrinter` is only obtainable via `.ready(ReadyPrinter)` state—compile-time guarantee you can only print when ready.

## Delegate

```swift
protocol PhomemoManagerDelegate: AnyObject {
    func manager(_ manager: PhomemoManager, didChangeState state: PrinterState)
}
```

Replaces 8 delegate methods with 1.

## State Management

PhomemoManager tracks `statusFlags: NotReadyReason` internally. On BLE status notifications:
- Empty flags → `.ready(ReadyPrinter(manager: self))`
- Non-empty flags → `.notReady(statusFlags)`

State transitions:
- Init → `.disconnected`
- Bluetooth on → `.scanning`
- Peripheral found → `.connecting`
- Characteristics discovered + flags empty → `.ready`
- Status notification with issue → `.notReady(reason)`
- `print()` called → `.printing`
- Print complete (0x0f, 0x0c) → `.ready`
- Disconnect/error → `.error` or `.disconnected`

## Print Flow

1. ViewModel pattern-matches `.ready(let printer)`
2. Calls `printer.print(image)`
3. Manager sets `state = .printing`
4. Writes image data to peripheral
5. On print complete notification, sets `state = .ready(ReadyPrinter(...))`
6. UI observes state change

## ViewModel Usage

```swift
@Observable
final class PhomemoViewModel: PhomemoManagerDelegate {
    private(set) var state: PrinterState = .disconnected

    var canPrint: Bool {
        if case .ready = state, previewImage != nil { return true }
        return false
    }

    func printImage() {
        guard case .ready(let printer) = state,
              let image = phomemoImage else { return }
        printer.print(image)
    }

    func manager(_ manager: PhomemoManager, didChangeState state: PrinterState) {
        self.state = state
    }
}
```
