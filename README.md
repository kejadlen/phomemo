# Fauxmemo

Print images to a Phomemo T02 thermal printer from macOS.

Fork of [jeffrafter/phomemo](https://github.com/jeffrafter/phomemo), which builds on [vivier/phomemo-tools](https://github.com/vivier/phomemo-tools).

## Features

- Drag, drop, or paste images
- Floyd-Steinberg dithering
- Liquid glass UI (macOS 26)

## Requirements

- macOS 26.0+
- Phomemo T02 paired via Bluetooth

## Setup

1. Pair your T02 in System Settings → Bluetooth
2. Launch Fauxmemo
3. Drop an image or click "Open Image..."
4. Click Print

### Why pair first?

The T02 sends status notifications (paper out, cover open, print complete) over an encrypted BLE channel. Without pairing, the app can send images but receives no feedback—you won't know if the printer ran out of paper mid-print.

Pair once in System Settings to establish the encrypted channel. After that, Fauxmemo connects automatically.

## Troubleshooting

**Printer not detected:** Hold the button 3 seconds to enter pairing mode, or 20 seconds to hard reset.

**Already connected elsewhere:** The printer connects to one device at a time. Close other apps.

**USB not working:** The USB port charges only; use Bluetooth to print.
