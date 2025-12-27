# Share Extension Design

## Overview

Add a Share Extension so users can print images directly from Photos, Safari, or any app with a share button.

## Requirements

- Show dithered preview before printing
- Scan for printer in parallel with image loading
- Wait for print completion before dismissing
- Handle errors gracefully

## Architecture

### Targets

- `Phomemo` - Main app (existing)
- `PhomemoShare` - Share Extension (new)

### Shared Code

Both targets share:
- `PhomemoWriter.swift` - BLE connection and printing
- `PhomemoImage.swift` - Image conversion
- `phomemo_image.swift` - CGImage extensions

### Extension Files

```
PhomemoShare/
├── ShareViewController.swift    # Extension entry point
├── ShareViewModel.swift         # State management
└── Info.plist                   # Extension config
```

## UI Layout

```
┌─────────────────────────────────────┐
│  Print to Phomemo          [Cancel] │
├─────────────────────────────────────┤
│   ┌─────────────┐                   │
│   │   Preview   │   ← Dithered      │
│   │   (mono)    │                   │
│   └─────────────┘                   │
│   [●] Connecting to printer...      │
│         [ Print ]                   │
└─────────────────────────────────────┘
```

## States

| State | Status | Print Button |
|-------|--------|--------------|
| Loading image | "Loading..." | Disabled |
| Image ready, scanning | "Searching for printer..." | Disabled |
| Image ready, connected | "Ready" | Enabled |
| Printing | "Printing..." | Disabled |
| Complete | Auto-dismiss | — |
| Error | Error message | Disabled |

## Error Handling

| Scenario | Behavior |
|----------|----------|
| No image | "No image found" |
| Bluetooth off | "Turn on Bluetooth" |
| Printer not found (30s) | "Printer not found" |
| Disconnect mid-print | "Printer disconnected" |
| Printer status error | Show specific error |

## Xcode Setup

1. Add Share Extension target
2. Add shared files to both targets
3. Configure Info.plist:
   - `NSExtensionActivationSupportsImageWithMaxCount: 1`
   - `NSExtensionPointIdentifier: com.apple.share-services`
   - `NSBluetoothAlwaysUsageDescription`

## Implementation Steps

1. Create Share Extension target in Xcode
2. Add shared source files to extension target
3. Create ShareViewModel with parallel image/printer loading
4. Create ShareViewController with SwiftUI view
5. Configure Info.plist for image activation
6. Test from Photos app
