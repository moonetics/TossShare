# TossShare for macOS 🌌📲

<p align="center">
  <img src="Assets/Logo With Text_transparent.png" alt="TossShare Logo" width="360" />
</p>

<p align="center">
  <b>Seamless, native Quick Share (Nearby Connections) client for macOS.</b><br/>
  Bidirectional wireless transfer between Samsung Galaxy / Android devices and Mac with zero third-party software required on your phone.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple" alt="macOS 13.0+" />
  <img src="https://img.shields.io/badge/Swift-6.0-orange?logo=swift" alt="Swift 6.0" />
  <img src="https://img.shields.io/badge/Protocol-Quick%20Share%20%2F%20Nearby-brightgreen" alt="Protocol Quick Share" />
  <img src="https://img.shields.io/badge/Architecture-Universal%20Binary%20(arm64%20%2B%20x86__64)-purple" alt="Universal Binary" />
  <img src="https://img.shields.io/badge/Tests-72%2F72%20Passed-success" alt="Tests Passed" />
</p>

---

## ✨ Features

- 📡 **Native Quick Share Discovery**: Discovers Samsung Galaxy and Android devices via mDNS (`_FC9F5ED42C8A._tcp`) and advertises Mac seamlessly using Apple `NetService`.
- 🔐 **Zero Compromise Security**: Full UKEY2 Curve P-256 key exchange with SHA-512 commitment, visual 4-digit PIN confirmation, AES-256-CBC payload encryption, and HMAC-SHA256 authentication.
- 🔁 **Bidirectional File Transfer**:
  - **Mac ➔ Samsung**: Drag-and-drop any files or folders to the Radar view or Menu Bar popover. Folders are automatically flattened recursively.
  - **Samsung ➔ Mac**: Tap "Share" ➔ "Quick Share" on Samsung and select your Mac. Interactive approval modal appears on Mac with real-time transfer progress.
- 📁 **Smart Batch Organization**:
  - Single file transfers save directly into `~/Downloads/`.
  - Multi-file batches are automatically organized into clean timestamped folders: `~/Downloads/TossShare - <Sender> (<Date Time>)`.
- 🔔 **Interactive System Notifications**:
  - Banner notifications on successful transfers.
  - Clicking single-file notifications highlights the file in Finder (`activateFileViewerSelecting`).
  - Clicking multi-file notifications opens directly into the batch subfolder in Finder (`NSWorkspace.open`).
- 📋 **Bidirectional Clipboard Sharing**:
  - Right-click any device in the Radar to send clipboard text or URLs.
  - Text sent from phone is atomically copied to Mac clipboard with a preview notification.
- 🎯 **Radar & Menu Bar Interface**:
  - Concentric radar UI showing proximity, real device names, and live transfer states.
  - Lightweight Menu Bar drop zone for ultra-quick transfers without opening the main window.
- 📱 **QR Code Fallback Pairing**: Built-in QR pairing sheet for AP-isolated Wi-Fi networks and hotspot environments.

---

## 🛠️ Architecture

```
Sources/
├── TossShareCore/          # Protocol engine, cryptography, and network transport
│   ├── Client/             # NearbyBonjourServiceResolver, NearbySenderSession, FileItemCollector
│   ├── Discovery/          # MDNSDiscoveryService, DeviceRegistry, EndpointInfoParser
│   ├── Models/             # PeerDevice, TransferSession, TransferItem
│   ├── Protocol/           # QuickShareProtocolEngine (UKEY2, D2D Framing, SecureMessage)
│   ├── Protobuf/           # SwiftProtobuf messages (OfflineFrame, SharingFrame, UKEY2)
│   ├── Server/             # NearbyReceiverServer (NetService Bonjour publisher & TCP receiver)
│   └── Storage/            # TransferFileManager (batch folder resolution & deduplication)
├── TossShareUI/            # Native SwiftUI components
│   ├── RadarView/          # Concentric radar animation, device avatars, modal dialogs
│   ├── MenuBar/            # MenuBarExtra popover, drop zone, active transfer cards
│   └── Notification/       # UNUserNotificationCenter integration & click navigation
├── TossShareExtension/     # macOS Finder Share Extension
└── TossShareApp/           # Main application entry point & lifecycle management
```

---

## 🚀 Getting Started

### Prerequisites

- macOS 13.0 (Ventura) or newer
- Xcode 16+ or Swift 6.0 toolchain
- Samsung Galaxy / Android device connected to the same Wi-Fi network with Quick Share set to "Anyone nearby"

### Build & Run from Source

1. **Clone the repository**:
   ```bash
   git clone https://github.com/moonetics/TossShare.git
   cd TossShare
   ```

2. **Run Unit Tests**:
   ```bash
   swift test
   ```
   *All 72 core, discovery, crypto, protocol, and UI integration tests will execute.*

3. **Launch in Live Debug Mode**:
   ```bash
   ./scripts/run-debug.sh
   ```
   *Compiles the release binary, packs `/Applications/TossShare.app`, and runs with colored ANSI protocol tracing.*

4. **Package Standalone `.app`**:
   ```bash
   ./scripts/package-app.sh
   ```
   *Builds a Universal Binary (`arm64` + `x86_64`) bundle complete with icons and metadata.*

---

## 🧪 Testing

TossShare has a comprehensive unit and integration test suite covering:
- ✅ Wire format protobuf encoding/decoding
- ✅ UKEY2 handshake & cipher commitment calculation
- ✅ mDNS endpoint info serialization & deserialization
- ✅ Reverse DNS hostname resolution
- ✅ Multi-file batch subfolder creation & duplicate collision avoidance
- ✅ Recursive folder flattening & hidden file filtering (`.DS_Store`)
- ✅ Business rules: AP isolation detection, 0.5s drain delay, 30s consent timeout

Run all tests via:
```bash
swift test
```

---

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
