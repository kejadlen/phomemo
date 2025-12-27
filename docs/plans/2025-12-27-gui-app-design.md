# Phomemo GUI Application Design

## Overview

Convert the command-line Phomemo printer tool into a SwiftUI macOS GUI application.

## Requirements

- SwiftUI framework
- Drag & drop + file picker for image selection
- Live dithered monochrome preview
- Auto-connect to T02 printer with status indicator
- Status bar showing printer state (paper, temperature, cover)
- Scan for printer before enabling image selection

## Architecture

### Layers

1. **View Layer (SwiftUI)** - `PhomemoApp`, `ContentView`, status bar
2. **ViewModel Layer** - `PrinterViewModel` (@Observable)
3. **Model Layer** - `PhomemoWriter` (modified), `PhomemoImage` (unchanged)

### State Flow

1. Scanning - "Searching for printer..." with spinner, drop zone disabled
2. Connected - Polling for printer status, drop zone disabled
3. Ready - Printer confirmed ready, drop zone active
4. Image loaded - Show original + preview, print button enabled

## UI Layout

```
┌─────────────────────────────────────────┐
│  Phomemo Printer                    [●] │  ← Title + connection indicator
├─────────────────────────────────────────┤
│   ┌─────────────┐  ┌─────────────┐     │
│   │  Original   │  │  Preview    │     │
│   │   Image     │  │ (dithered)  │     │
│   └─────────────┘  └─────────────┘     │
│   [ Drop image here or click to open ]  │
│              [ Print ]                  │
├─────────────────────────────────────────┤
│  Paper OK  •  Temp OK  •  Cover Closed  │  ← Status bar
└─────────────────────────────────────────┘
```

## File Structure

- `PhomemoApp.swift` - NEW: SwiftUI app entry point
- `ContentView.swift` - NEW: Main UI
- `PrinterViewModel.swift` - NEW: State management
- `PhomemoWriter.swift` - MODIFY: Add delegate, remove auto-print
- `PhomemoImage.swift` - UNCHANGED
- `Scanner.swift` - DELETE: Merged into writer
- `main.swift` - DELETE: Replaced by SwiftUI lifecycle
