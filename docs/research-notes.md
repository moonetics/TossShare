# Research Notes: Deep Dive 5 Repositori Quick Share

Dokumen ini mendokumentasikan hasil audit teknis, analisis kode sumber (*source code review*), dan perbandingan arsitektural dari 5 repositori reverse-engineering Quick Share / Nearby Share terbuka.

---

## 1. Referensi Utama: leonboe1/QuickDrop
- **URL**: [https://github.com/leonboe1/QuickDrop](https://github.com/leonboe1/QuickDrop)
- **Bahasa & Platform**: Swift (macOS & iOS)
- **Status**: Fork yang disempurnakan dari NearDrop dengan kapabilitas pengiriman aktif (*Outbound Transfer*).

### Temuan Arsitektural Kunci:
1. **Publikasi mDNS dengan `NetService`**:
   - QuickDrop tidak mengandalkan `NWListener.service`. QuickDrop membuat instans `NetService(domain: "", type: "_FC9F5ED42C8A._tcp.", name: name, port: port)` secara eksplisit.
   - Nama instans mDNS adalah 10-byte Base64 URL-safe:
     ```swift
     let nameBytes: [UInt8] = [
         0x23, // PCP
         endpointID[0], endpointID[1], endpointID[2], endpointID[3],
         0xFC, 0x9F, 0x5E, // Hash service ID
         0, 0
     ]
     let name = Data(nameBytes).urlSafeBase64EncodedString()
     ```
   - Atribut TXT record diset menggunakan dictionary `[txtKeyEndpointInfo: deviceInfo.serialize().urlSafeBase64EncodedString().data(using: .utf8)!]` via `NetService.data(fromTXTRecord:)`.
2. **Resolusi Endpoint Target (`NearbyBonjourServiceResolver.swift`)**:
   - Menggunakan delegate `NetServiceDelegate` (`netServiceDidResolveAddress`) untuk mengekstrak alamat `sockaddr_in` (IPv4) dan port tujuan.
   - Mendukung penanganan antarmuka IPv6 link-local bila diperlukan.
3. **Resolusi Nama Asli (`NearbyDeviceNameResolver.swift`)**:
   - Jika metadata mDNS kosong (karena mode privasi Android), QuickDrop menjalankan reverse lookup `getnameinfo(..., NI_NUMERICHOST)` untuk mendapatkan hostname perangkat dari router.
4. **Mesin Pengirim (`OutboundNearbyConnection.swift`)**:
   - Mengimplementasikan state machine pengirim:
     `initial` $\rightarrow$ `sentUkeyClientInit` $\rightarrow$ `sentUkeyClientFinish` $\rightarrow$ `sentPairedKeyEncryption` $\rightarrow$ `sentPairedKeyResult` $\rightarrow$ `sentIntroduction` $\rightarrow$ `sendingFiles`.
   - Streaming berkas dengan potongan buffer 512 KB (`FileHandle.read(upToCount: 512 * 1024)`).
   - Pengiriman frame EOF dengan `flags = 1` setelah offset mencapai ukuran penuh.

---

## 2. ignotusbucius/open-quickshare
- **URL**: [https://github.com/ignotusbucius/open-quickshare](https://github.com/ignotusbucius/open-quickshare)
- **Bahasa & Platform**: Rust / C (Linux)
- **Status**: Implementasi Quick Share paling lengkap di ekosistem Linux (Bluetooth LE + Wi-Fi LAN + Wi-Fi Direct).

### Temuan Arsitektural Kunci:
1. **Hierarki Transport Multi-Tier**:
   - Tingkat 1 (Penemuan Awal): BLE Advertising & Scanning.
   - Tingkat 2 (High-Speed Transfer): Upgrade otomatis ke Wi-Fi LAN jika berada pada SSID yang sama.
   - Tingkat 3 (Offline / No Router): Host Wi-Fi Direct hotspot di salah satu perangkat.
2. **Transisi Saluran Tanpa Kehilangan Data (*Lossless Mid-Transfer Channel Swap*)**:
   - Pengurasan socket lama (*drain*) menggunakan frame kendali `LAST_WRITE` dan `SAFE_TO_CLOSE` sebelum berpindah ke soket baru.
   - Penundaan disinkronisasi sebelum penutupan koneksi (`asyncAfter: 0.5s`) agar frame EOF diproses tuntas oleh pihak penerima.

---

## 3. Medformatik/CrossDrop
- **URL**: [https://github.com/Medformatik/CrossDrop](https://github.com/Medformatik/CrossDrop)
- **Bahasa & Platform**: Flutter / Dart & Swift (macOS, iOS, Linux)
- **Status**: Implementasi portabel berbasis fondasi protokol NearDrop.

### Temuan Arsitektural Kunci:
1. **Fallback Pemindaian QR Code**:
   - Mengatasi limitasi mode "Contacts Only" pada Quick Share dengan membangkitkan QR Code lokal yang membawa `EndpointInfo` dan token pairing privat, memungkinkan ponsel memindai layar Mac saat mDNS tidak ditemukan.
2. **Transfer Teks & URL Fleksibel**:
   - Menggunakan payload bertipe `TEXT` dan `URL` dengan dialog persetujuan terpisah di popover menu bar.

---

## 4. Martichou/rquickshare
- **URL**: [https://github.com/Martichou/rquickshare](https://github.com/Martichou/rquickshare)
- **Bahasa & Platform**: Rust (Linux & macOS)
- **Status**: Implementasi performa tinggi untuk pengiriman dan penerimaan berkas over Wi-Fi LAN.

### Temuan Arsitektural Kunci:
1. **Heartbeat Keep-Alive Terjadwal**:
   - Google Quick Share mengharuskan pengiriman `OfflineFrame(type: KEEP_ALIVE)` secara periodik (setiap 10 detik). Tanpa ini, socket TCP akan diputus sepihak oleh Android saat transfer berkas berukuran besar.
2. **Toleransi Segmentasi TCP**:
   - Pembacaan header 4-byte big-endian wajib mengantisipasi paket chunk TCP yang terfragmentasi.

---

## 5. grishka/NearDrop
- **URL**: [https://github.com/grishka/NearDrop](https://github.com/grishka/NearDrop)
- **Bahasa & Platform**: Swift (macOS)
- **Status**: Pelopor implementasi reverse engineering Quick Share di macOS (dokumen acuan: `PROTOCOL.md`).

### Temuan Arsitektural Kunci:
1. **Kriptografi UKEY2**:
   - Kurva eliptik P-256 (NIST P-256 / secp256r1).
   - Derivasi kunci menggunakan HKDF-SHA256:
     - Salt: `SHA256("D2D")` $\rightarrow$ D2D client/server keys.
     - Salt: `SHA256("SecureMessage")` $\rightarrow$ Decrypt/Encrypt (`ENC:2`) dan HMAC (`SIG:1`).
2. **Struktur Frame Wire Protobuf**:
   - Header 4-byte panjang pesan Big-Endian.
   - Pembungkus terluar: `SecureMessage` (AES-256-CBC + HMAC-SHA256).
   - Isi terenkripsi: `DeviceToDeviceMessage` yang membawa serialized `OfflineFrame`.
   - Payload data: `PayloadTransferFrame` bertipe `.file` atau `.bytes`.
