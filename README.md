# IPMsgX for macOS

A modern, native macOS client for the [IP Messenger](https://ipmsg.org) LAN messaging protocol — built from scratch in Swift and SwiftUI.

IP Messenger is a lightweight, serverless instant messaging protocol for local area networks. Messages are exchanged directly over UDP — no internet connection, no accounts, no central server required. It is widely used in office environments, particularly in Japan.

---

## Screenshots

> _Coming soon_

---

## Features

- Native macOS app built with Swift and SwiftUI
- Fully compatible with the IP Messenger protocol (Windows and macOS clients)
- End-to-end encrypted messaging using RSA-1024 + AES-256-CBC
- Message history and conversation view
- File attachment support
- Absence / do-not-disturb mode
- Menu bar integration
- Multi-network interface and broadcast address support

---

## Requirements

- macOS 15.0 (Sequoia) or later
- Apple Silicon or Intel Mac (64-bit)

---

## Installation

Download the latest release DMG from the [Releases](../../releases) page, open it, and drag **IPMsgX.app** to your Applications folder.

> **Note:** IPMsgX is ad-hoc signed and not notarized. On first launch, right-click the app and choose **Open** to bypass Gatekeeper.

---

## Building from Source

This project uses the Swift Package Manager — no Xcode project file required.

```bash
# Clone the repo
git clone https://github.com/yogiee/IPMsgX.git
cd IPMsgX

# Debug build
swift build

# Release app bundle (outputs to build/IPMsgX.app)
bash scripts/build-app.sh release
```

---

## Protocol Compatibility

IPMsgX is compatible with:

- **IP Messenger for Windows** — the original client by H.Shirouzu ([ipmsg.org](https://ipmsg.org))
- **IP Messenger for macOS** — by G.Ishiwata ([ishwt.net](https://ishwt.net/en/software/ipmsg/))
- Any other client implementing the IPMSG UDP protocol

### Encryption

Key exchange follows the GETPUBKEY / ANSPUBKEY handshake from the original protocol:

- Recipient's RSA-1024 public key encrypts the session key
- Message body is encrypted with AES-256-CBC (or Blowfish-128-CBC for older clients)
- Optional SHA-256 message signature for authenticity

---

## Acknowledgements

This project is an independent Swift rewrite and is not a fork of any existing codebase.
The IP Messenger protocol design and the original macOS implementation were used as reference:

| | |
|---|---|
| **IP Messenger protocol** | H.Shirouzu — [ipmsg.org](https://ipmsg.org) |
| **IP Messenger for macOS** | G.Ishiwata — [ishwt.net/en/software/ipmsg](https://ishwt.net/en/software/ipmsg/) |

The original macOS source (Objective-C) is © 2001–2019 G.Ishiwata, All Rights Reserved, and is **not** included in this repository.

---

## License

IPMsgX is released for personal use. No warranty is provided.
