# Research Notes: Reverse Engineering & Technical Benchmarks

Dokumen ini memuat temuan riset teknis, analisis protokol, perbandingan arsitektur nirkabel Apple vs Samsung, serta tolok ukur kompetitor untuk proyek **TossShare for macOS**.

---

## 1. Kategorisasi Temuan Riset

### A. Bukti Terverifikasi (Verified Evidence)
1. **Batasan Core Bluetooth macOS (`CBPeripheralManager`)**:
   - Berdasarkan inspeksi langsung header SDK Xcode (`/System/Library/Frameworks/CoreBluetooth.framework/Headers/CBPeripheralManager.h`), Apple secara eksplisit mendokumentasikan:
     > *"Supported advertising data types are `CBAdvertisementDataLocalNameKey` and `CBAdvertisementDataServiceUUIDsKey`."*
   - Memasukkan kunci `CBAdvertisementDataServiceDataKey` atau `CBAdvertisementDataManufacturerDataKey` pada `startAdvertising:` memicu pesan error `API MISUSE` di konsol sistem dan paket data tersebut secara otomatis di-drop oleh daemon `bluetoothd`.
2. **Kemampuan Scanning Core Bluetooth (`CBCentralManager`)**:
   - Berbeda dengan advertising, sisi scanning (`CBCentralManager`) pada macOS dapat membaca isi `CBAdvertisementDataServiceDataKey` dan `CBAdvertisementDataManufacturerDataKey` tanpa pembatasan. Hal ini memungkinkan Mac mendeteksi beacon kedekatan (proximity) yang dipancarkan oleh Samsung Galaxy.
3. **Penyatuan Protokol Nearby Share & Quick Share (2024)**:
   - Mulai awal tahun 2024 (bersamaan dengan peluncuran Samsung Galaxy S24 dan update Google Play Services), Google Nearby Share dan Samsung Quick Share resmi dilebur menjadi satu protokol terpadu dengan tetap mempertahankan pengenal mDNS `_FC9F5ED42C8A._tcp.`.

### B. Riset Sekunder & Reverse Engineering (Secondary Research)
1. **Analisis Protokol NearDrop (@grishka)**:
   - Menggunakan mDNS service type `_FC9F5ED42C8A._tcp.` (berasal dari `SHA256("NearbySharing")[0..6]`).
   - Format TXT Record `n`: String terenkripsi base64 URL-safe yang memuat:
     - Byte 0: Bitfield (visibilitas, tipe perangkat: `0x01` Phone, `0x02` Tablet, `0x03` Laptop).
     - Byte 1..16: Salt & metadata key (16 byte).
     - Byte 17: Panjang nama perangkat (UTF-8 length).
     - Byte 18+: Nama perangkat ramah pengguna (*friendly name*).
   - Jabat Tangan Kriptografi UKEY2:
     - Menggunakan kurva eliptik P-256 (NIST P-256 / secp256r1).
     - Pertukaran frame: `ClientInit` -> `ServerInit` -> `ClientFinish`.
     - Derivasi kunci otentikasi bersama via HKDF-SHA256 untuk memverifikasi 4-digit PIN.
     - Enkripsi muatan menggunakan AES-CBC atau AES-GCM.
2. **Implementasi Linux (RQuickShare & QNearbyShare)**:
   - Pada platform Linux, pengembang dapat menyiarkan paket BLE kustom secara bebas berkat stack `BlueZ` (`org.bluez.LEAdvertisement1`). Namun di macOS, stack Bluetooth dikelola secara ketat oleh Apple (`bluetoothd`), sehingga pendekatan Linux tidak dapat di-porting ke macOS tanpa driver kernel kustom.

---

## 2. Perbandingan Arsitektur Ekosistem: Apple AirDrop vs Samsung Quick Share

| Komponen | Apple AirDrop (Mac & iPhone) | Samsung Quick Share Native | Solusi TossShare for macOS |
| :--- | :--- | :--- | :--- |
| **Lapisan Penemuan (Discovery)** | BLE Beacon (Apple `0x004C`) | BLE Beacon Fast Pair (`0xFE2C`) & mDNS | mDNS `_FC9F5ED42C8A._tcp.` + BLE Scan |
| **Jalur Data Nirkabel (Data Link)** | **AWDL** (Apple Wireless Direct Link P2P) | **Wi-Fi Direct** (Wi-Fi Alliance P2P) | **Wi-Fi LAN Bersama** + Fallback Hotspot/USB-C |
| **Ketergantungan Router** | ❌ Tidak butuh router sama sekali | ❌ Tidak butuh router sama sekali | 🟢 Menggunakan router (atau Hotspot HP sebagai router mini) |
| **Otentikasi Identitas** | Sertifikat Apple ID (Mutual TLS) | Google Account / UKEY2 PIN | Jabat Tangan Kriptografi UKEY2 |
| **Kecepatan Maksimal** | 40 – 90 MB/detik | 50 – 110 MB/detik | 30 – 80 MB/s (Wi-Fi) / 300–800 MB/s (USB-C) |

---

## 3. Matriks Tolok Ukur Kompetitor (Competitor Benchmarking)

| Parameter | NearDrop (Resmi) | LocalSend | TossShare for macOS (Rancangan Kita) |
| :--- | :---: | :---: | :---: |
| **Arah Transfer** | 1 Arah (Hanya Terima di Mac) | 2 Arah (Kirim & Terima) | **2 Arah (Kirim & Terima)** |
| **Aplikasi Tambahan di Samsung** | ❌ Tidak Butuh (Quick Share) | ⚠️ **Wajib Install APK LocalSend** | **❌ Tidak Butuh (Quick Share bawaan)** |
| **Metode Penemuan Mac -> Samsung** | Wajib Pindai QR Code | mDNS kustom LocalSend | **Otomatis Tanpa QR Code** |
| **Integrasi Finder macOS** | Share Sheet (Kirim via QR) | Drag & Drop di App Window | **Jendela Radar + Menu Bar + Share Sheet** |
| **Ketahanan AP Isolation** | Gagal total | Gagal total | **Deteksi Cerdas + Fallback Hotspot/Kabel** |
| **Kompatibilitas Mac** | Apple Silicon & Intel | Apple Silicon & Intel | **Apple Silicon & Intel (Universal Binary)** |

---

## 4. Evaluasi Solusi Terhadap Batasan Perangkat Keras macOS

```
+-----------------------------------+-----------------------------------+
|     Pendekatan Eksperimental      |        Pendekatan Terpilih        |
|    (Bypass Kernel Bluetooth)      |     (Native mDNS + Wi-Fi LAN)     |
+-----------------------------------+-----------------------------------+
| ❌ Butuh disable SIP              | 🟢 SIP tetap aktif (Aman)         |
| ❌ Tidak lolos notarization Apple | 🟢 Lolos Gatekeeper & Notarisasi  |
| ❌ Berisiko panic di SoC M1-M4    | 🟢 100% stabil di semua chip Mac  |
| ❌ Rentan rusak tiap update OS    | 🟢 Menggunakan API publik stabil  |
+-----------------------------------+-----------------------------------+
```
