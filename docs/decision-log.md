# Decision Log & Pre-Mortem Analysis: TossShare for macOS

Dokumen ini mencatat keputusan arsitektural, analisis komparatif, evaluasi trade-off, alternatif yang ditolak, serta hasil analisis Pre-Mortem untuk proyek **TossShare for macOS**.

---

## 1. Log Keputusan Arsitektur Kunci

### Keputusan 1: Pola Penemuan Perangkat Samsung
- **Tanggal**: 2026-09-28
- **Status**: Disetujui
- **Keputusan**: Menggunakan mode penemuan native Quick Share *"Everyone for 10 minutes"* pada Samsung, dikombinasikan dengan mDNS Browser (`_FC9F5ED42C8A._tcp.`) dan BLE Central Scanner (`CBCentralManager`) di macOS.
- **Alternatif yang Ditolak**:
  - *Memaksa injeksi Service Data Fast Pair kustom (`0xFE2C`) dari Mac via `CBPeripheralManager`*: Ditolak karena Apple secara keras melarang kunci `CBAdvertisementDataServiceDataKey` dalam API publik.
  - *Menggunakan IOBluetoothHCIUserClient / Driver Kext*: Ditolak karena memerlukan penonaktifan SIP (System Integrity Protection), memicu kernel panic pada chip SoC Apple Silicon (M1/M2/M3/M4), dan merusak portabilitas lintas Mac.
- **Trade-off**: Pengguna Samsung perlu memastikan toggle Quick Share aktif ke "Everyone for 10 min" saat ingin menerima file dari Mac. Sebagai gantinya, aplikasi 100% aman, stabil, tidak memerlukan hak akses root, dan kompatibel di semua Mac modern.

---

### Keputusan 2: Strategi Jaringan Bertingkat & Sistem Fallback
- **Tanggal**: 2026-09-28
- **Status**: Disetujui
- **Keputusan**: Mengadopsi arsitektur jaringan 3 tingkat:
  - **Tingkat 1**: Wi-Fi LAN Lokal (Kondisi normal di rumah/kantor).
  - **Tingkat 2 (Fallback Nirkabel)**: Mobile Hotspot Samsung saat terjadi AP Isolation di router publik atau saat di luar ruangan tanpa router.
  - **Tingkat 3 (Fallback Fisik)**: USB-C Tethering untuk pengiriman file raksasa (> 20 GB) atau kondisi darurat.
- **Rasional**: macOS tidak mendukung protokol Wi-Fi Direct bawaan Samsung (hanya mendukung AWDL Apple). Personal Hotspot Samsung otomatis menciptakan subnet lokal pribadi (`192.168.43.x`) tanpa menggunakan kuota data seluler.
- **Trade-off**: Di jaringan publik dengan AP Isolation, pengguna perlu menyalakan Mobile Hotspot di ponselnya. Aplikasi menyediakan kartu panduan visual untuk menyederhanakan proses ini menjadi 2 langkah mudah.

---

### Keputusan 3: Desain Pengalaman Pengguna (UI/UX Parity dengan AirDrop)
- **Tanggal**: 2026-09-28
- **Status**: Disetujui
- **Keputusan**: Mengimplementasikan antarmuka terpadu:
  1. Jendela Radar animasi konsentris SwiftUI (seperti AirDrop di Finder).
  2. Menu Bar status item dengan area Drop Zone (seret-lepas file).
  3. Finder Share Extension (`com.apple.share-services`) untuk klik kanan langsung di Finder.
- **Alternatif yang Ditolak**:
  - *Hanya Share Extension tanpa aplikasi utama*: Ditolak karena pengguna membutuhkan jendela visual untuk memantau status perangkat dan riwayat transfer.
  - *Aplikasi Menu Bar murni tanpa Radar*: Ditolak karena pengalaman pengguna terasa kurang imersif dibanding standar AirDrop.

---

### Keputusan 4: Kriptografi & Manajemen Aliran Data
- **Tanggal**: 2026-09-28
- **Status**: Disetujui
- **Keputusan**: Menggunakan `CryptoKit` bawaan macOS untuk Curve P-256 ECDH, HKDF-SHA256, dan cipher AES-GCM (protokol Google UKEY2). Data biner dialirkan secara *chunked streaming* dengan buffer 512KB per blok.
- **Rasional**: `CryptoKit` teroptimasi secara perangkat keras (hardware-accelerated) pada chip Apple Silicon dan Intel AES-NI. Model *chunked streaming* memastikan konsumsi memori RAM tetap sangat rendah (< 60 MB) bahkan ketika mentransfer file berukuran hingga 100 GB.

---

### Keputusan 5: Penamaan & Branding Produk (TossShare)
- **Tanggal**: 2026-09-28
- **Status**: Disetujui
- **Keputusan**: Mengadopsi nama merek resmi **TossShare** (Bundle ID: `com.tossshare.macos` / target `TossShareApp`).
- **Rasional**: Menggabungkan metafora fisik *"Toss"* (melempar berkas dengan santai ke perangkat di sebelah pada Radar UI) dengan *"Share"* (selaras dengan ekosistem Quick Share / Nearby Share Android). Nama ini tegas, modern, mudah diingat, dan memiliki identitas jelas di macOS.
- **Alternatif yang Dievaluasi**: *Drop* (terlalu generik), *StarDrop* (filosofis Samsung "Three Stars"), *Fling*, *CrossDrop*. Diputuskan: **TossShare**.

---

## 2. Hasil Analisis Pre-Mortem (Uji Kegagalan Produk)

> **Skenario Pengujian**:  
> *"Bayangkan 6 bulan setelah rilis, produk ini ditinggalkan oleh pengguna karena sering mengeluh 'Mac tidak bisa mendeteksi Samsung'. Apa akar penyebab yang paling mungkin, dan bagaimana kita memitigasinya sejak hari pertama?"*

| Potensi Akar Masalah | Dampak Pengguna | Strategi Mitigasi Terintegrasi |
| :--- | :--- | :--- |
| **Batas Waktu 10 Menit Quick Share Samsung** | Pengguna lupa bahwa toggle "Everyone" otomatis mati setelah 10 menit. Akibatnya, Mac tidak bisa menemukan Samsung dan pengguna mengira aplikasi rusak. | **Mitigasi 1**: Menampilkan teks bantuan persisten di bagian bawah Radar UI: *"Pastikan Quick Share di Samsung aktif ke 'Everyone for 10 min'"*.<br>**Mitigasi 2**: Menggunakan `CBCentralManager` untuk mendeteksi sinyal BLE Samsung dan memberi petunjuk visual spesifik jika sinyal Bluetooth terdeteksi tetapi mDNS belum aktif. |
| **AP / Client Isolation pada Router Publik** | Di hotel, kafe, atau kampus, router memblokir transmisi paket lokal antar perangkat. | **Mitigasi**: Menambahkan mesin diagnosa `NetworkHealthMonitor.swift` yang secara proaktif mendeteksi kegagalan soket TCP dan menampilkan kartu `FallbackGuideCard` yang memandu pengguna menyalakan Mobile Hotspot. |
| **Pembaruan Protokol oleh Google/Samsung** | Google memperbarui spesifikasi protobuf atau TLS cipher pada Google Play Services. | **Mitigasi**: Memisahkan lapisan protokol (`DropCore/Protocol`) secara modular (*decoupled*) sehingga pembaruan schema framing dapat dirilis secara independen tanpa mengubah UI atau networking layer. |
