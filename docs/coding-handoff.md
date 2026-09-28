# AI Coding Agent Handoff: TossShare v2.0 Implementation Guide

Dokumen ini adalah panduan teknis operasional dan kumpulan prompt bertahap (*Phased Execution Prompts*) bagi AI Coding Agent / developer untuk mengimplementasikan TossShare v2.0 sesuai standar **QuickDrop** dan spesifikasi di [PRD.md](file:///Users/percayajanji/Documents/Drop/docs/PRD.md).

---

## 1. Roadmap Implementasi Bertahap

| Fase | Nama Fase | Fokus Eksekusi | Kriteria Lolos (Verification Checkpoint) |
| :--- | :--- | :--- | :--- |
| **Phase 0** | Foundation & Docs Reader | Verifikasi package, arsitektur dependensi, dan sinkronisasi Protobuf | `swift test` lolos 100%, Protobuf models terintegrasi |
| **Phase 1** | NetService mDNS Publication | Migrasi dari NWListener.Service ke `NetService` native untuk iklan mDNS | `dns-sd -B _FC9F5ED42C8A._tcp.` memunculkan instance 10-byte dan TXT record `n` valid |
| **Phase 2** | Bonjour Service Resolver & Reverse DNS | Pembuatan `NearbyBonjourServiceResolver` & `NearbyHostLookup` untuk target IPv4 & port | NetService delegate berhasil me-resolve alamat target tanpa blocking |
| **Phase 3** | QuickShare Client Engine Refactor | Refaktor `NearbySenderSession` dan `QuickShareProtocolEngine` sesuai `OutboundNearbyConnection` QuickDrop | Pengiriman handshake UKEY2 dan streaming chunk 512KB tervalidasi via unit test |
| **Phase 4** | Bidirectional Clipboard & Error Localization | Sinkronisasi clipboard dua arah dan lokalisasi pesan error Indonesia | Clipboard copy ke `NSPasteboard` otomatis & error enum mengadopsi LocalizedError |
| **Phase 5** | UI Polish & Radar/MenuBar Integration | Integrasi status engine ke Radar SwiftUI dan Popover Menu Bar | Radar menampilkan avatar dinamis dan modal konfirmasi interaktif |
| **Phase 6** | System Integration & AC Signoff | Pengujian AC-1, AC-2, AC-3 dan pengemasan biner release TossShare.app | Seluruh acceptance criteria lolos dan bundle .app terinstal di `/Applications/` |

---

## 2. Struktur Modul & Direktori yang Direkomendasikan

```text
Sources/
├── TossShareCore/
│   ├── Client/
│   │   ├── NearbyBonjourServiceResolver.swift   # [Baru] Resolusi asinkron NetService IPv4/Port
│   │   ├── NearbyHostLookup.swift               # [Baru] Reverse DNS PTR lookup untuk hostname asli
│   │   └── NearbySenderSession.swift            # Refaktor mesin pengirim sesuai OutboundNearbyConnection
│   ├── Discovery/
│   │   ├── DeviceRegistry.swift                 # Registry cache & deduplikasi perangkat
│   │   ├── EndpointInfoParser.swift             # Serialisasi/deserialisasi 10-byte instance name & TXT
│   │   └── MDNSDiscoveryService.swift           # Pencarian perangkat via NWBrowser
│   ├── Models/
│   │   ├── PeerDevice.swift                     # Model perangkat terdekat
│   │   └── TransferSession.swift                # State machine & model sesi transfer
│   ├── Protocol/
│   │   └── QuickShareProtocolEngine.swift       # Engine kriptografi UKEY2, D2D, dan framing
│   ├── Protobuf/
│   │   ├── wire_format.pb.swift                 # SwiftProtobuf messages Google Nearby
│   │   └── ukey.pb.swift
│   └── Server/
│       └── NearbyReceiverServer.swift           # NetService Bonjour publisher & TCP receiver
├── TossShareUI/
│   ├── RadarView/                               # Antarmuka Radar gelombang konsentris
│   ├── MenuBar/                                 # Antarmuka Popover Menu Bar status
│   └── Notification/                            # Integrasi UNUserNotificationCenter native
├── TossShareExtension/                          # Finder Share Extension
└── TossShareApp/                                # Entry point aplikasi macOS
```

---

## 3. Ready-to-Copy Prompts per Fase

### 🔹 PROMPT PHASE 0: Foundation & Docs Reader
```markdown
Anda adalah AI Coding Agent untuk proyek TossShare. 
Tugas Anda: Memulai implementasi TossShare v2.0 dengan membaca dokumen acuan dan memverifikasi integritas fondasi kode.

1. BACA DOKUMEN:
   - docs/PRD.md (terutama Bagian 5, 6, dan 10)
   - docs/decision-log.md (keputusan DEC-001 hingga DEC-004)
   - docs/research-notes.md (arsitektur leonboe1/QuickDrop)

2. TUGAS EKSEKUSI:
   - Verifikasi build project dengan `swift build`.
   - Jalankan `swift test` dan pastikan seluruh test suite dasar lolos tanpa error.
   - Periksa bahwa dependensi SwiftProtobuf, SwiftECC, dan BigInt terhubung dengan benar.

3. BATASAN TEGAS (NO-GOS):
   - Jangan menambahkan dependency baru di luar Package.swift yang ada.
   - Jangan mengubah logika bisnis di tahap ini.

4. KRITERIA LOLOS:
   - `swift test` menghasilkan 0 failure.
```

---

### 🔹 PROMPT PHASE 1: NetService mDNS Publication
```markdown
Tugas Anda: Mengganti publikasi mDNS berbasis NWListener.service dengan `NetService` native Darwin/Foundation di NearbyReceiverServer.swift sesuai arsitektur leonboe1/QuickDrop (DEC-001).

1. BACA DOKUMEN:
   - docs/PRD.md (FR-001)
   - docs/research-notes.md (Bagian 1: Publikasi mDNS dengan NetService)

2. TUGAS EKSEKUSI:
   - Ubah `NearbyReceiverServer.swift`:
     - Ganti penugasan `newListener.service = bonjourDesc` dengan instans `NetService(domain: "", type: "_FC9F5ED42C8A._tcp.", name: mdnsInstanceName, port: port)`.
     - Susun TXT record dictionary dengan key "n" berisi data Base64 URL-safe dari EndpointInfo.
     - Panggil `service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))` dan `service.publish()`.
     - Implementasikan delegate `NetServiceDelegate` untuk menangani callback `netServiceDidPublish` dan `netService:didNotPublish:`.

3. BATASAN TEGAS (NO-GOS):
   - Dilarang menggunakan nama Bonjour sembarang; instance name wajib tepat 10-byte Base64 URL-safe (`0x23` + 4B ID + 3B hash + `0x00, 0x00`).
   - Jangan mematikan soket listener TCP.

4. KRITERIA LOLOS:
   - Kompilasi sukses.
   - Perintah `dns-sd -B _FC9F5ED42C8A._tcp. local.` menampilkan instance name Base64 dan `dns-sd -L` dapat membaca record TXT "n".
```

---

### 🔹 PROMPT PHASE 2: Bonjour Service Resolver & Reverse DNS
```markdown
Tugas Anda: Membangun modul resolusi target `NearbyBonjourServiceResolver.swift` dan `NearbyHostLookup.swift` untuk mengekstrak alamat IPv4 riil dan hostname Android target.

1. BACA DOKUMEN:
   - docs/PRD.md (FR-002, FR-003)
   - docs/research-notes.md (Bagian 1: Resolusi Endpoint Target & Nama Asli)

2. TUGAS EKSEKUSI:
   - Buat `Sources/TossShareCore/Client/NearbyBonjourServiceResolver.swift`:
     - Mengimplementasikan `NetServiceDelegate`.
     - Membaca `sender.addresses`, mem-parsing data sockaddr ke struct `sockaddr_in` untuk mendapatkan string IPv4 dan port UInt16.
   - Buat `Sources/TossShareCore/Client/NearbyHostLookup.swift`:
     - Fungsi `hostname(forIPv4:)` menggunakan `getnameinfo` untuk reverse DNS PTR lookup.
   - Integrasikan resolver ke `DeviceRegistry` untuk memperbarui alamat target sebelum transfer dimulai.

3. BATASAN TEGAS (NO-GOS):
   - Dilarang memblokir main thread saat melakukan lookup DNS (wajib asinkron pada background queue).

4. KRITERIA LOLOS:
   - Unit test untuk resolver dan reverse DNS parser lolos 100%.
```

---

### 🔹 PROMPT PHASE 3: QuickShare Client Engine Refactor
```markdown
Tugas Anda: Menyempurnakan mesin pengirim `NearbySenderSession.swift` mengadopsi alur lengkap `OutboundNearbyConnection` dari QuickDrop.

1. BACA DOKUMEN:
   - docs/PRD.md (FR-004, FR-005)
   - docs/research-notes.md (Bagian 1: Mesin Pengirim OutboundNearbyConnection)

2. TUGAS EKSEKUSI:
   - Perbarui state machine `NearbySenderSession.swift`:
     - Kirim `ConnectionRequestFrame` dengan `mediums = [.wifiLan]`.
     - Kirim `Ukey2ClientInit` dengan cipher commitment SHA-512 dari `Ukey2ClientFinish`.
     - Terima `Ukey2ServerInit`, verifikasi cipher `.p256Sha512`, kirim `Ukey2ClientFinish`.
     - Kirim `PairedKeyEncryption` dan `PairedKeyResult`.
     - Kirim `IntroductionFrame` dan tunggu `response` consent dari ponsel.
     - Streaming berkas dalam chunk 512 KB, kirim frame EOF (`flags = 1`), dan kirim Keep-Alive setiap 10 detik.

3. BATASAN TEGAS (NO-GOS):
   - Dilarang menutup koneksi seketika setelah chunk terakhir; beri jeda drain 0.5 detik agar penerima memproses EOF secara tuntas.

4. KRITERIA LOLOS:
   - `swift test --filter UKEY2HandshakeTests` dan `WireEncodingTests` lolos 100%.
```

---

### 🔹 PROMPT PHASE 4: Bidirectional Clipboard & Error Localization
```markdown
Tugas Anda: Mengintegrasikan sinkronisasi teks/URL clipboard dua arah dan lokalisasi pesan error Bahasa Indonesia.

1. BACA DOKUMEN:
   - docs/PRD.md (FR-006, Bagian 14)

2. TUGAS EKSEKUSI:
   - Pada `NearbyReceiverServer.swift`: Saat payload bertipe teks diterima (`textMetadata`), salin isi UTF-8 ke `NSPasteboard.general` dan picu notifikasi sistem.
   - Pada `NearbySenderSession.swift`: Tambahkan metode `sendClipboardText(text:)`.
   - Perbarui `SenderSessionError` dan `ReceiverServerError` untuk mengadopsi `LocalizedError` dengan deskripsi jelas berbahasa Indonesia.

3. KRITERIA LOLOS:
   - Unit test penanganan teks clipboard dan error description lolos tanpa peringatan compiler.
```

---

### 🔹 PROMPT PHASE 5: UI Polish & Radar/MenuBar Integration
```markdown
Tugas Anda: Menghubungkan engine baru ke antarmuka Radar SwiftUI dan Menu Bar Popover.

1. BACA DOKUMEN:
   - docs/PRD.md (Bagian 8: Screen Flow & Wireframe)

2. TUGAS EKSEKUSI:
   - Perbarui `RadarMainView.swift`:
     - Tampilkan nama perangkat riil yang telah di-resolve.
     - Tambahkan context menu klik kanan: "Kirim Teks Clipboard".
     - Sediakan dialog modal interaktif saat transfer menunggu persetujuan Samsung.
     - Sediakan tombol fallback "Tampilkan QR Pairing".
   - Perbarui `MenuBarPopoverView.swift` dengan drop zone cepat.

3. KRITERIA LOLOS:
   - UI responsif, tidak ada hang pada main thread, dan status transfer ter-update realtime.
```

---

### 🔹 PROMPT PHASE 6: System Integration & AC Signoff
```markdown
Tugas Anda: Melakukan validasi Acceptance Criteria AC-1, AC-2, AC-3, dan mengompilasi release bundle `TossShare.app`.

1. BACA DOKUMEN:
   - docs/PRD.md (Bagian 17: Kriteria Penerimaan)

2. TUGAS EKSEKUSI:
   - Jalankan seluruh unit & integration test: `swift test`.
   - Jalankan script packaging: `./scripts/package-app.sh`.
   - Salin bundle baru ke `/Applications/TossShare.app`.
   - Lakukan verifikasi live dengan `dns-sd` dan pengujian transfer langsung dengan Samsung Galaxy A54.

3. KRITERIA LOLOS:
   - AC-1, AC-2, AC-3 lulus verifikasi.
   - Aplikasi siap digunakan dan terpasang di sistem.
```

---

## 4. Definition of Done (DoD) Checklist

- [x] **Kepatuhan Protokol**: Format mDNS, UKEY2 handshake, dan framing chunk kompatibel 100% dengan Samsung One UI Quick Share.
- [x] **Zero Warning Swift Concurrency**: Bebas dari data-race dan peringatan `Sendable` pada Swift 6 mode.
- [x] **Pengujian Otomatis**: Seluruh suite pengujian `swift test` lulus dengan 0 failure (67/67 test pass).
- [x] **Pengemasan Native**: Bundle `TossShare.app` terpasang di `/Applications/` dengan `Info.plist`, `AppIcon.icns`, dan binary Universal (arm64 & x86_64).
- [x] **Dokumentasi Lengkap**: `docs/PRD.md`, `docs/decision-log.md`, `docs/research-notes.md`, dan `docs/coding-handoff.md` sinkron dan mutakhir.

