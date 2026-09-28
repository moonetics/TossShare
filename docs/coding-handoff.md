# AI Coding Agent Handoff Document: TossShare for macOS
## Phased Implementation Plan & Ready-to-Copy Prompts

> Dokumen ini dibuat berdasarkan framework `prd-architect` sebagai jembatan langsung dari spesifikasi **Product Requirements Document (PRD)** menuju **Arsitektur Teknis & Eksekusi Koding**.
> 
> Roadmap implementasi disusun menjadi **7 Fase Terstruktur (Phase 0 s/d Phase 6)** dengan **Ready-to-Copy Prompts** mandiri di tiap fase agar AI Coding Agent (Google Antigravity, OpenAI Codex, Cursor, Claude Code) dapat mengeksekusi pembangunan aplikasi native macOS berbasis Swift 6 ini secara fokus, modular, dan teruji tanpa kehilangan konteks.

---

## 🗺️ Roadmap Eksekusi Bertahap (Overview)

| Fase | Nama Fase | Fokus & Deliverable Utama | Dokumen Acuan di PRD |
| :--- | :--- | :--- | :--- |
| **Phase 0** | **Project Setup, Tooling & Docs Reader** | SPM/Xcode setup, Swift 6 strict concurrency, arsitektur modular (`TossShareCore`, `TossShareUI`, `TossShareExtension`), baca PRD | `docs/PRD.md` (Visi, Scope, No-Gos) & `docs/decision-log.md` |
| **Phase 1** | **Design System, Tokens & Primitives** | Token warna macOS (Dynamic Light/Dark), tipografi, spacing, radar concentric pulse tokens, primitive components SwiftUI, accessibility | `docs/PRD.md` (UX & Aksesibilitas, Wireframe Radar) |
| **Phase 2** | **Domain Entities, Data Models & Mocks** | Model entitas `PeerDevice`, `TransferSession`, `TransferItem`, state machine transfer, serialization, mock device seeders | `docs/PRD.md` (Bagian 9: Konseptual ERD, Bagian 12: Business Rules) |
| **Phase 3** | **Kriptografi UKEY2, Framing & Discovery Engine** | Kriptografi CryptoKit (ECDH P-256, HKDF, AES-GCM), Protobuf schemas, mDNS `NWBrowser` (`_FC9F5ED42C8A._tcp.`), BLE scanner | `docs/PRD.md` (FR-001, FR-002, FR-003, FR-004, NFR-003) |
| **Phase 4** | **Sender Engine, Streaming & Receiver Server** | `NearbySenderSession`, 512KB chunked file streamer, refaktor receiver server NearDrop (`NWListener`), mitigasi duplicate file | `docs/PRD.md` (FR-005, FR-006, FR-008, BR-001, BR-002) |
| **Phase 5** | **Radar UI, Menu Bar & Diagnostics Advisor** | Jendela Radar konsentris SwiftUI, drag-and-drop file target, Menu Bar popover drop zone, `NetworkHealthMonitor` & panduan Hotspot/USB | `docs/PRD.md` (FR-009, FR-010, Section 8 Screen Flow & Wireframe) |
| **Phase 6** | **Finder Extension, Acceptance Criteria & DoD Signoff** | Integrasi Finder Share Sheet (`TossShareExtension`), validasi seluruh skenario AC (Given/When/Then), build Universal Binary & DoD | `docs/PRD.md` (FR-007, Section 17 AC, Section 11 NFR) |

---

## 📋 Ready-to-Copy Prompts per Fase

Salin satu per satu blok prompt di bawah ini ke AI coding agent Anda sesuai progres proyek. **Pastikan kriteria verifikasi pada fase saat ini terpenuhi 100% sebelum berpindah ke fase berikutnya.**

---

### 🟢 Phase 0: Project Setup, Tooling & Docs Context Loading

Salin blok teks ini saat memulai sesi implementasi pertama:

```text
Halo! Kita akan memulai implementasi teknis aplikasi native "TossShare for macOS" — aplikasi transfer file dua arah dengan Samsung Quick Share (tanpa aplikasi tambahan di Samsung dan tanpa QR Code).
Sebelum menulis kode fungsional apapun, kita wajib menyelesaikan PHASE 0: FOUNDATION, TOOLING SETUP & DOCS CONTEXT LOADING.

[DOKUMEN WAJIB DIBACA]:
1. docs/PRD.md (Pelajari: Ringkasan Eksekutif, Scope MoSCoW, Rabbit Holes & No-Gos, serta NFR Performa & Keamanan)
2. docs/decision-log.md (Pelajari: Keputusan arsitektur Swift 6 Concurrency, CryptoKit, dan Network.framework)
3. docs/research-notes.md (Pelajari: Analisis protokol Quick Share & batasan Core Bluetooth macOS)

[TUJUAN PHASE 0]:
Menyiapkan fondasi workspace macOS yang bersih, modular, dan mematuhi standar modern Swift 6 Concurrency tanpa boilerplate atau dependensi berlebih.

[TUGAS EKSEKUSI]:
1. Konfirmasi bahwa Anda telah membaca dan memahami seluruh batasan teknis dari docs/PRD.md dan docs/decision-log.md.
2. Siapkan proyek Swift/macOS (Package.swift atau Xcode project target macOS 13.0 Ventura ke atas).
3. Atur target modularitas bersih:
   - TossShareCore (protokol, kriptografi, jaringan mDNS/TCP)
   - TossShareUI (antarmuka SwiftUI, komponen radar, menu bar)
   - TossShareApp (app lifecycle, settings, menu bar item)
   - TossShareExtension (target Finder extension)
   - TossShareCoreTests (unit testing suite)
4. Aktifkan Strict Concurrency Checking (`SWIFT_STRICT_CONCURRENCY = complete` atau `-strict-concurrency=complete`).
5. Konfigurasikan SwiftLint / formatting rules dasar.
6. Buat file entry point App skeleton tanpa kode dummy atau package eksternal yang tidak diperlukan (YAGNI principle).

[BATASAN TEGAS (NO-GOS)]:
- JANGAN menulis logika kriptografi atau socket networking di fase ini!
- JANGAN membuat halaman UI atau animasi radar dulu!
- JANGAN meminta izin sudo/root, jangan membuat kext, dan jangan mengasumsikan SIP dinonaktifkan!

[KRITERIA LOLOS (VERIFICATION CHECKPOINT)]:
- Proyek berhasil dikompilasi dengan `swift build` (atau xcodebuild) dengan 0 warning dan 0 error di mode Swift 6 Concurrency.
- Struktur folder modular telah terbentuk rapi sesuai panduan docs/coding-handoff.md.
- Laporkan status inisialisasi dan tunggu konfirmasi saya sebelum lanjut ke Phase 1.
```

---

### 🎨 Phase 1: Design System, Tokens & Primitive Components

Salin blok teks ini setelah Phase 0 selesai dan disetujui:

```text
Fondasi proyek Phase 0 telah siap. Sekarang kita masuk ke PHASE 1: DESIGN SYSTEM, DESIGN TOKENS & PRIMITIVE COMPONENTS.

[DOKUMEN WAJIB DIBACA]:
1. docs/PRD.md (Bagian 8: Screen Flow & Low-Fi Layout, Bagian 13: Persyaratan UX & Aksesibilitas, Bagian 14: Fallback Cards)

[TUJUAN PHASE 1]:
Membangun design tokens visual native macOS (AirDrop aesthetic), tokens animasi radar, dan komponen primitif SwiftUI yang konsisten dan aksesibel sebelum merakit layar fitur.

[TUGAS EKSEKUSI]:
1. Buat Design Tokens terpusat di `TossShareUI/Theme/`:
   - Color Palette Tokens: Dynamic colors untuk macOS Dark/Light Mode (Accent AirDrop Blue, Samsung Cyan, Surface Card, Border Subtle, Status Semantic: Scanning, Transferring, Success, Danger/Error, Warning).
   - Typography Scale Tokens: Modern San Francisco font scale (Large Title, Headline, Device Title, Body, Caption, Monospace untuk transfer speed).
   - Radar Animation Tokens: Durasi pulsing (1.8s), easing curves, opacity steps (0.4 ke 0.05), ring expansion scale.
   - Spacing & Radius Tokens: Padding grid 4px/8px, corner radii (12px untuk card, 8px untuk button, pill untuk badges).
2. Terapkan Standar UX & Aksesibilitas macOS:
   - Target klik/drop minimum 44x44pt untuk semua elemen interaktif.
   - Kontras rasio teks minimum 4.5:1 (WCAG AA).
   - Dukungan haptic feedback (NSHapticFeedbackManager) untuk event sukses/gagal.
3. Buat Primitive Components Reusable:
   - `PulsingRing`: Lingkaran konsentris bernapas untuk efek radar.
   - `DeviceAvatarNode`: Komponen lingkaran icon perangkat (Phone, Tablet, Laptop) dengan label nama dan status badge.
   - `TransferProgressBar`: Progress bar elegan dengan tampilan persentase dan transfer speed (MB/s).
   - `StatusPillBadge`: Badge status (misal: "Siap Terima", "Mengirim...", "AP Isolation").
   - `FallbackCard`: Container kartu edukasi untuk instruksi Hotspot/USB Tethering.

[BATASAN TEGAS (NO-GOS)]:
- JANGAN menyambungkan ke socket mDNS atau pengiriman file riil di fase ini!
- JANGAN membuat interaksi transfer final, cukup komponen UI murni dan preview mockup.

[KRITERIA LOLOS (VERIFICATION CHECKPOINT)]:
- Seluruh token warna dan tipografi terdefinisi di satu sumber kebenaran (DesignTokens / Theme).
- Komponen primitif dapat di-render pada SwiftUI Previews tanpa visual glitch atau layout warning.
- Sajikan visual preview komponen primitif ini dan tunggu konfirmasi saya untuk lanjut ke Phase 2.
```

---

### 🗄️ Phase 2: Domain Entities, Data Models & Mock Seeders

Salin blok teks ini setelah Phase 1 selesai:

```text
Design System Phase 1 telah terverifikasi. Sekarang kita masuk ke PHASE 2: DOMAIN ENTITIES, DATA MODELS & MOCK SEEDERS.

[DOKUMEN WAJIB DIBACA]:
1. docs/PRD.md (Bagian 9: Konseptual Skema Data / Mermaid ERD, Bagian 12: Business Rules BR-001 s/d BR-003)
2. docs/decision-log.md (Model data sesi dan status transfer)

[TUJUAN PHASE 2]:
Menerjemahkan ERD konseptual pada PRD ke dalam model data Swift yang strongly typed, thread-safe (Sendable), dan dilengkapi mock seeders untuk pengujian.

[TUGAS EKSEKUSI]:
1. Implementasikan model entitas inti di `TossShareCore/Models/`:
   - `PeerDevice`: endpointId (String), friendlyName (String), deviceType (DeviceType: phone, tablet, laptop), ipAddress (String), port (Int), lastSeen (Date), rssi (Int?).
   - `TransferSession`: sessionId (UUID), direction (Direction: outgoing, incoming), state (TransferState: idle, connecting, authenticating, waitingAcceptance, transferring, completed, failed, cancelled), authPin (String), totalBytes (Int64), transferredBytes (Int64), speedBytesPerSecond (Double), items ([TransferItem]).
   - `TransferItem`: itemId (UUID), fileName (String), mimeType (String), fileSize (Int64), localURL (URL), sha256Checksum (String?).
2. Pastikan seluruh model mengadopsi protokol `Sendable`, `Identifiable`, dan `Codable` (atau `Equatable`/`Hashable` sesuai kebutuhan).
3. Implementasikan State Machine transitions untuk `TransferState` guna memastikan transisi status berjalan valid (misal: tidak bisa loncat dari `idle` ke `completed`).
4. Buat `MockDeviceSeeder.swift`:
   - Mock data realistis: "Galaxy S24 Ultra", "Galaxy Z Fold 6", "Galaxy Tab S9" lengkap dengan IP lokal dummy dan status bervariasi untuk testing UI.

[BATASAN TEGAS (NO-GOS)]:
- JANGAN menulis kode jaringan atau socket I/O dulu!
- JANGAN menambahkan field spekulatif yang tidak tercantum pada ERD PRD.

[KRITERIA LOLOS (VERIFICATION CHECKPOINT)]:
- Seluruh model lulus pengecekan Swift 6 Concurrency (`Sendable` conformance) tanpa error data race.
- Unit test verifikasi serialisasi JSON dan State Machine transition lulus 100%.
- Tampilkan ringkasan model entitas yang telah dibuat dan tunggu konfirmasi saya untuk lanjut ke Phase 3.
```

---

### 🔐 Phase 3: UKEY2 Cryptography, Protobuf Framing & Discovery Engine

Salin blok teks ini setelah Phase 2 selesai:

```text
Model data Phase 2 telah siap. Sekarang kita masuk ke PHASE 3: UKEY2 CRYPTOGRAPHY, PROTOBUF FRAMING & DISCOVERY ENGINE.

[DOKUMEN WAJIB DIBACA]:
1. docs/PRD.md (FR-001 mDNS, FR-002 Endpoint Decoding, FR-003 UKEY2 Handshake, NFR-003 Keamanan & Privasi)
2. docs/research-notes.md (Spesifikasi Google UKEY2: ECDH Curve P-256, HKDF-SHA256, AES-GCM, format TXT Record `n`)

[TUJUAN PHASE 3]:
Membangun engine kriptografi UKEY2 untuk otentikasi aman end-to-end, encoder/decoder frame biner/protobuf, serta scanner mDNS untuk mendeteksi perangkat Samsung secara nirkabel.

[TUGAS EKSEKUSI]:
1. Implementasikan `TossShareCore/Crypto/`:
   - `CryptoEngine.swift`: Operasi kriptografi menggunakan Apple `CryptoKit` (Curve P-256 ECDH, HKDF-SHA256 derivation, AES-GCM 128/256 cipher).
   - `UKEY2Handshake.swift`: Siklus jabat tangan UKEY2 (ClientInit, ServerInit, ClientFinish) serta derivasi 4-digit token PIN verifikasi visual.
2. Implementasikan `TossShareCore/Protocol/`:
   - `WireEncoding.swift`: Pembaca dan penulis frame biner Quick Share (length-prefixed framing).
   - `NearbyFrames.swift`: Frame parser/serializer untuk ConnectionRequestFrame, IntroductionFrame, dan AcceptanceFrame.
3. Implementasikan `TossShareCore/Discovery/`:
   - `MDNSDiscoveryService.swift`: Menggunakan `Network.framework` (`NWBrowser`) untuk memindai service mDNS `_FC9F5ED42C8A._tcp.`.
   - Parser TXT Record `n` untuk mengekstrak endpoint ID, friendly name, dan tipe perangkat target.
   - `BLEProximityMonitor.swift`: Menggunakan `CBCentralManager` untuk membaca RSSI kedekatan perangkat terdekat.
   - `DeviceRegistry.swift`: Aktor/Observable central registry yang menggabungkan perangkat terdeteksi secara non-duplikatif.
4. Tulis Unit Tests komprehensif di `Tests/TossShareCoreTests/`:
   - `UKEY2HandshakeTests.swift`: Menguji handshake client/server dan derivasi kunci terhadap vektor uji standar Android.
   - `EndpointInfoParsingTests.swift`: Memastikan parser record mDNS akurat.

[BATASAN TEGAS (NO-GOS)]:
- JANGAN menggunakan library C/C++ pihak ketiga untuk kriptografi (gunakan murni Apple CryptoKit).
- JANGAN meminta izin Bluetooth yang melanggar batasan macOS (gunakan CBCentralManager murni).

[KRITERIA LOLOS (VERIFICATION CHECKPOINT)]:
- Seluruh unit test kriptografi UKEY2 dan framing biner lulus 100% (Green tests).
- `NWBrowser` mampu memindai service mDNS tanpa crash atau memory leak.
- Laporkan hasil unit test dan tunggu konfirmasi saya untuk lanjut ke Phase 4.
```

---

### ⚡ Phase 4: Sender Engine, Chunked Streaming & Receiver Server

Salin blok teks ini setelah Phase 3 selesai:

```text
Kriptografi dan penemuan perangkat Phase 3 telah terverifikasi. Sekarang kita masuk ke PHASE 4: SENDER ENGINE, CHUNKED STREAMING & RECEIVER SERVER.

[DOKUMEN WAJIB DIBACA]:
1. docs/PRD.md (FR-004 Framing Metadata, FR-005 Acceptance, FR-006 Chunked Streaming, FR-008 Receiver Server, BR-001 Resolusi Duplikasi, BR-002 Pembersihan File Batal)
2. docs/decision-log.md (Strategi buffer 512KB dan refaktor NearDrop ke Swift Concurrency)

[TUJUAN PHASE 4]:
Membangun mesin pengirim file dua arah (Mac -> Samsung) dengan chunked streaming efisien serta server penerima (Samsung -> Mac) dengan penanganan file disk yang aman.

[TUGAS EKSEKUSI]:
1. Implementasikan `TossShareCore/Client/` (Sender Engine: Mac -> Samsung):
   - `NearbySenderSession.swift` berbasis `NWConnection`:
     - Membuka koneksi TCP ke target Samsung pada port hasil mDNS.
     - Melakukan handshake UKEY2 peran Klien.
     - Mengirimkan metadata file via `IntroductionFrame`.
     - Menunggu respon persetujuan (`AcceptanceFrame`).
   - `ChunkedFileStreamer.swift`:
     - Membaca file per blok buffer 512KB.
     - Mengenkripsi blok dengan cipher session UKEY2.
     - Mengalirkan chunk secara non-blocking via `NWConnection.send()`.
     - Melacak progress byte dan menghitung kecepatan transfer (MB/s).
2. Implementasikan `TossShareCore/Server/` (Receiver Engine: Samsung -> Mac):
   - `NearbyReceiverServer.swift` berbasis `NWListener`:
     - Membuka listener TCP lokal dan mempublikasikan layanan mDNS Quick Share.
     - Menangani jabat tangan UKEY2 peran Server saat Samsung menghubung.
     - Menerima `IntroductionFrame` dan memancarkan event prompt penerimaan.
     - Mengalirkan file masuk ke folder penyimpanan lokal.
3. Implementasikan `TossShareCore/Storage/TransferFileManager.swift`:
   - Simpan file ke `~/Downloads` (atau folder konfigurasi pengguna).
   - Terapkan Business Rule `BR-001`: Auto-rename jika file duplikat (misal: `foto (1).jpg`).
   - Terapkan Business Rule `BR-002`: Hapus file temporer jika transfer dibatalkan atau terputus.
4. Tulis Unit & Integration Tests di `Tests/TossShareCoreTests/ChunkedStreamerTests.swift`.

[BATASAN TEGAS (NO-GOS)]:
- JANGAN membaca seluruh file ke dalam memori RAM sekaligus (wajib streaming 512KB buffer, batasi RAM < 60 MB)!
- JANGAN menimpa file pengguna yang sudah ada di disk tanpa auto-rename.

[KRITERIA LOLOS (VERIFICATION CHECKPOINT)]:
- Pengujian transfer file lokal (simulasi sender ke receiver loopback) berhasil tanpa korupsi berkas (checksum SHA-256 cocok 100%).
- Penanganan auto-rename file duplikat teruji sukses.
- Konsumsi memori RAM tetap di bawah 60 MB selama streaming file uji berukuran besar (> 1 GB).
- Laporkan hasil pengujian dan tunggu konfirmasi saya untuk lanjut ke Phase 5.
```

---

### 🖥️ Phase 5: Radar UI, Menu Bar Drop Zone & Diagnostics Advisor

Salin blok teks ini setelah Phase 4 selesai:

```text
Logika pengiriman dan penerimaan Phase 4 telah teruji. Sekarang kita masuk ke PHASE 5: RADAR UI, MENU BAR DROP ZONE & DIAGNOSTICS ADVISOR.

[DOKUMEN WAJIB DIBACA]:
1. docs/PRD.md (FR-009 Network Health, FR-010 Fallback Advisor, Bagian 8: Screen Flow & Wireframe Radar, Bagian 14: Edge Cases)
2. docs/decision-log.md (Desain interaksi radar SwiftUI dan deteksi AP Isolation)

[TUJUAN PHASE 5]:
Merakit antarmuka pengguna SwiftUI yang memukau (AirDrop-like radar window & menu bar drop zone) dan menghubungkannya dengan mesin diagnosa jaringan AP Isolation.

[TUGAS EKSEKUSI]:
1. Bangun `TossShareUI/RadarView/` (Jendela Utama Aplikasi):
   - Susun layout konsentris bernapas (`PulsingRing`) dengan node perangkat `DeviceAvatarNode`.
   - Hubungkan node perangkat ke `DeviceRegistry` reaktif: perangkat yang aktif muncul di radar, yang hilang memudar secara halus.
   - Implementasikan Drag-and-Drop file langsung ke avatar perangkat (menggunakan `.onDrop(of:delegate:)`).
   - Tampilkan overlay transfer aktif (`TransferProgressBar`) saat proses pengiriman/penerimaan berjalan.
2. Bangun `TossShareUI/MenuBar/`:
   - `MenuBarDropZone.swift`: Status bar item yang menerima drag file dari Finder kapan saja.
   - `MenuBarPopoverView.swift`: Popover ringkas menampilkan perangkat terdekat dan riwayat transfer terakhir.
3. Implementasikan `TossShareCore/Diagnostics/`:
   - `NetworkHealthMonitor.swift` menggunakan `NWPathMonitor`:
     - Memantau antarmuka jaringan (Wi-Fi, Hotspot, USB Tethering).
     - Deteksi indikasi AP / Client Isolation (mDNS terdeteksi tapi soket TCP ditolak atau timeout).
   - `ConnectivityAdvisor.swift`:
     - Memunculkan `FallbackGuideCard` secara otomatis saat AP Isolation terdeteksi:
       - Panduan 2 langkah aktivasi Mobile Hotspot di Samsung.
       - Panduan opsi kabel USB-C Tethering untuk transfer ultra-cepat.
4. Pastikan transisi antarmuka halus, responsif, dan mendukung Dark Mode native macOS.

[BATASAN TEGAS (NO-GOS)]:
- JANGAN membuat UI kaku atau templated default (gunakan estetika Apple premium dengan animasi halus).
- JANGAN membiarkan UI freeze selama operasi jaringan atau file I/O (seluruh I/O wajib berjalan di background actor).

[KRITERIA LOLOS (VERIFICATION CHECKPOINT)]:
- Jendela Radar dapat dibuka, menampilkan animasi pulsing, mendeteksi mock/real devices, dan menerima drag file.
- Menu Bar icon dan drop zone berfungsi normal.
- Kartu panduan fallback muncul dengan tepat saat disimulasikan kondisi AP Isolation.
- Sajikan demo antarmuka dan tunggu konfirmasi saya untuk masuk ke fase integrasi sistem final (Phase 6).
```

---

### 🚀 Phase 6: System Integration, Acceptance Criteria & DoD Signoff

Salin blok teks ini untuk menyelesaikan integrasi sistem dan validasi kriteria penerimaan akhir:

```text
Antarmuka dan core engine telah terpasang. Sekarang kita masuk ke fase final: PHASE 6: SYSTEM INTEGRATION, ACCEPTANCE CRITERIA & DOD SIGNOFF.

[DOKUMEN WAJIB DIBACA]:
1. docs/PRD.md (FR-007 Finder Extension, Bagian 17: Acceptance Criteria Skenario 1-3, Bagian 11: NFR)
2. docs/coding-handoff.md (Bagian Definition of Done Checklist)

[TUJUAN PHASE 6]:
Mengintegrasikan Finder Share Extension, notifikasi sistem native, memvalidasi seluruh skenario Acceptance Criteria secara ketat, dan memfinalisasi Definition of Done.

[TUGAS EKSEKUSI]:
1. Implementasikan `TossShareExtension` (`com.apple.share-services`):
   - Tambahkan target ekstensi Finder Share Sheet macOS.
   - Saat pengguna klik kanan file di Finder > Share > TossShare, buka dialog mini pemilihan perangkat target.
2. Integrasikan Notifikasi Sistem macOS (`UserNotifications`):
   - Notifikasi permintaan transfer masuk dari Samsung: "Galaxy S24 Ultra ingin mengirim [X] file. [Decline] [Accept]".
   - Notifikasi sukses pengiriman dengan tombol "Show in Finder".
3. Validasi Acceptance Criteria (AC) pada docs/PRD.md:
   - Skenario 1 (Penemuan Otomatis): Samsung Quick Share mode "Everyone" terdeteksi < 2 detik di LAN.
   - Skenario 2 (Mengirim Berkas Sukses): Berkas terkirim penuh dengan verifikasi hash SHA-256 cocok.
   - Skenario 3 (Fallback AP Isolation): Panduan Hotspot muncul otomatis saat soket terisolasi.
4. Lakukan Audit Kode & Kebersihan Proyek:
   - Pastikan 0 linting error, 0 compiler warnings.
   - Pastikan tidak ada dependensi eksternal yang tidak diperlukan (YAGNI audit).
   - Pastikan tidak ada pelanggaran izin keamanan macOS (tanpa sudo, tanpa kext, lolos SIP).
   - Build target Universal Binary (Apple Silicon arm64 & Intel x86_64).

[BATASAN TEGAS (NO-GOS)]:
- JANGAN menambahkan fitur baru di luar PRD! Fokus hanya pada penyelesaian integrasi, stabilitas, dan pengujian.

[KRITERIA LOLOS (DEFINITION OF DONE)]:
- Seluruh skenario Acceptance Criteria (AC) terbukti PASS.
- Build production Universal Binary berhasil dikompilasi dengan status bersih.
- Seluruh checklist Definition of Done pada docs/coding-handoff.md tercentang 100%.
- Sajikan laporan verifikasi final lengkap untuk saya review.
```

---

## 🏛️ Rekomendasi Struktur Folder & Modul Proyek

```text
TossShare/
├── Package.swift (atau TossShare.xcodeproj)
├── Sources/
│   ├── TossShareApp/                # App Lifecycle, NSApplicationDelegate, Settings
│   │   ├── TossShareApp.swift
│   │   └── AppDelegate.swift
│   ├── TossShareCore/               # Lapisan Inti Logika Protokol & Jaringan
│   │   ├── Discovery/               # Mesin Deteksi Perangkat (mDNS NWBrowser & BLE Scan)
│   │   │   ├── MDNSDiscoveryService.swift
│   │   │   ├── BLEProximityMonitor.swift
│   │   │   └── DeviceRegistry.swift
│   │   ├── Diagnostics/             # Pemantau Kesehatan Jaringan & Detektor AP Isolation
│   │   │   ├── NetworkHealthMonitor.swift
│   │   │   └── ConnectivityAdvisor.swift
│   │   ├── Protocol/                # Protobuf Schemas & Frame Serializers
│   │   │   ├── NearbyFrames.swift
│   │   │   ├── WireEncoding.swift
│   │   │   └── ProtobufDefinitions.swift
│   │   ├── Crypto/                  # Implementasi Protokol Google UKEY2 (CryptoKit)
│   │   │   ├── CryptoEngine.swift
│   │   │   ├── UKEY2Handshake.swift
│   │   │   └── UKEY2SessionState.swift
│   │   ├── Client/                  # Sender Engine: Mac -> Samsung
│   │   │   ├── NearbySenderSession.swift
│   │   │   └── ChunkedFileStreamer.swift
│   │   ├── Server/                  # Receiver Engine: Samsung -> Mac (Adaptasi NearDrop)
│   │   │   ├── NearbyReceiverServer.swift
│   │   │   └── IncomingTransferHandler.swift
│   │   ├── Storage/                 # Manajemen Berkas Disk & Resolusi Duplikasi
│   │   │   └── TransferFileManager.swift
│   │   └── Models/                  # Entitas Data Utama (Sendable, Codable)
│   │       ├── PeerDevice.swift
│   │       ├── TransferSession.swift
│   │       ├── TransferItem.swift
│   │       └── MockDeviceSeeder.swift
│   ├── TossShareUI/                 # Antarmuka SwiftUI
│   │   ├── Theme/                   # Design Tokens, Colors (Dark/Light), Typography, Spacing
│   │   │   └── DesignTokens.swift
│   │   ├── Primitives/              # Komponen Primitif Reusable
│   │   │   ├── PulsingRing.swift
│   │   │   ├── DeviceAvatarNode.swift
│   │   │   ├── TransferProgressBar.swift
│   │   │   └── StatusPillBadge.swift
│   │   ├── RadarView/               # Visualisasi Radar Konsentris AirDrop-Style
│   │   │   ├── RadarView.swift
│   │   │   ├── RadarNodeView.swift
│   │   │   └── TransferProgressOverlay.swift
│   │   ├── MenuBar/                 # Menu Bar Status Item & Drop Zone
│   │   │   ├── MenuBarDropZone.swift
│   │   │   └── MenuBarPopoverView.swift
│   │   ├── Diagnostics/             # Kartu Panduan Fallback (Hotspot & USB-C)
│   │   │   └── FallbackGuideCard.swift
│   │   └── Notification/            # Integrasi Notifikasi Sistem macOS
│   │       └── TransferNotificationManager.swift
│   └── TossShareExtension/          # Target Ekstensi Finder Share Sheet
│       ├── ShareViewController.swift
│       └── Info.plist
└── Tests/
    ├── TossShareCoreTests/
    │   ├── UKEY2HandshakeTests.swift
    │   ├── FramingTests.swift
    │   ├── EndpointInfoParsingTests.swift
    │   ├── ChunkedStreamerTests.swift
    │   └── ModelSerializationTests.swift
    └── DiagnosticsTests/
        └── NetworkHealthTests.swift
```

---

## 🎯 Definition of Done (DoD) Checklist Global

Sebelum proyek **TossShare for macOS** dinyatakan rampung secara keseluruhan, pastikan seluruh kriteria berikut terpenuhi:
- [x] **Phase 0 Terpenuhi**: Proyek terkonfigurasi dengan Swift 6 Strict Concurrency, arsitektur modular bersih, dan tanpa boilerplate.
- [x] **Phase 1 Terpenuhi**: Design Tokens (warna Dark/Light mode, font San Francisco, animasi radar) dan komponen primitif SwiftUI terstandarisasi.
- [x] **Phase 2 Terpenuhi**: Model entitas `PeerDevice`, `TransferSession`, `TransferItem` mematuhi `Sendable` dan state machine teruji.
- [x] **Phase 3 Terpenuhi**: Handshake kriptografi UKEY2 (`CryptoKit`), framing biner, dan scanner mDNS `_FC9F5ED42C8A._tcp.` lulus unit test 100%.
- [x] **Phase 4 Terpenuhi**: Pengiriman file chunked 512KB dan penerimaan file NearDrop server berjalan dengan aman (RAM < 60 MB, auto-rename file duplikat aktif).
- [x] **Phase 5 Terpenuhi**: Jendela Radar animasi konsentris SwiftUI, Menu Bar Drop Zone, dan detektor AP Isolation berfungsi intuitif.
- [x] **Phase 6 Terpenuhi**: Finder Share Extension aktif, notifikasi sistem native terhubung, dan seluruh skenario Acceptance Criteria berstatus PASS.
- [x] **Integritas macOS**: Aplikasi berjalan tanpa hak akses `root`, tanpa kext, mematuhi SIP, dan berhasil di-build sebagai Universal Binary (Apple Silicon & Intel).
