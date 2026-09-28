# Decision Log: TossShare v2.0

Dokumen ini mencatat keputusan arsitektural utama, kompromi (*trade-offs*), hasil analisis Pre-Mortem, dan alternatif yang ditolak selama proses perancangan produk.

---

## 1. Keputusan Arsitektural Utama

### DEC-001: Penggunaan `NetService` Native untuk Publikasi mDNS
- **Tanggal**: 2026-09-28
- **Konteks**: Pada macOS, penggunaan `NWListener.service` dari Network.framework memiliki bug terbukti di mana TXT record `"n"` kerap kali tidak terkirim atau instance name terpotong, menyebabkan Android Nearby Connections scanner mengabaikan Mac.
- **Keputusan**: Mengadopsi arsitektur teruji dari **`leonboe1/QuickDrop`** dan **`grishka/NearDrop`**, yaitu menggunakan `NetService` langsung dari Foundation / Darwin mDNSResponder API.
- **Konsekuensi & Trade-off**:
  - *Positif*: TXT record `"n"` dan instance name 10-byte Base64 URL-safe dipublikasikan secara andal ke seluruh antarmuka lokal tanpa modifikasi tak terduga.
  - *Negatif*: Memerlukan pengelolaan delegate Objective-C (`NetServiceDelegate`), yang dibungkus rapi dalam kelas Swift terisolasi.

### DEC-002: Resolusi Alamat Target via `NearbyBonjourServiceResolver`
- **Tanggal**: 2026-09-28
- **Konteks**: Saat mengirim berkas ke Android, aplikasi membutuhkan alamat IPv4 riil dan port tujuan perangkat penerima. `NWBrowser.Result` sering kali hanya menyediakan representasi abstrak endpoint tanpa IP langsung.
- **Keputusan**: Mengimplementasikan `NearbyBonjourServiceResolver` (seperti pada `QuickDrop`) yang menyelesaikan alamat target via `NetService.resolve(withTimeout:)` dan mem-parsing struktur `sockaddr` IPv4 secara aman.

### DEC-003: Reverse DNS Hostname Lookup untuk Privacy Mode
- **Tanggal**: 2026-09-28
- **Konteks**: Saat Samsung Galaxy diatur ke "Contacts Only", metadata nama di mDNS disembunyikan.
- **Keputusan**: Menggunakan modul `NearbyHostLookup` (Reverse DNS PTR via `getnameinfo`) pada IP target untuk mengekstrak hostname riil (contoh: `Galaxy-A54.local`), menyajikan nama yang bermakna bagi pengguna sebelum transfer dimulai.

### DEC-004: Strategi Mode Privasi & QR Code Fallback
- **Tanggal**: 2026-09-28
- **Konteks**: Beberapa pengguna Samsung memilih tidak mengaktifkan "Everyone for 10 minutes".
- **Keputusan**: Mendukung jalur utama zero-config (mode "Siapa Saja") dan menyediakan tombol fallback **"Tampilkan QR Pairing"** (mengadopsi konsep `CrossDrop`) jika pengguna ingin melakukan pairing manual saat ponsel dalam mode kontak.

### DEC-005: Two's Complement Integer Encoding untuk Kunci Publik UKEY2 (P-256)
- **Tanggal**: 2026-09-28
- **Konteks**: Saat Samsung Galaxy One UI Quick Share menerima `Ukey2ServerInit` atau `Ukey2ClientFinish`, Android men-decode koordinat X dan Y pada `EcP256PublicKey` menggunakan `new BigInteger(byte[])` Java. Jika bit paling signifikan (MSB) bernilai 1 (byte[0] >= 0x80) dan tidak disisipkan byte `0x00`, Java menginterpretasikannya sebagai bilangan negatif (dua's complement negatif) sehingga titik kurva eliptis dianggap tidak valid (`point not on curve`) dan memicu penolakan seketika dengan `Ukey2Alert(badPublicKey)`.
- **Keputusan**: Mengimplementasikan `encodeBigEndianTwosComplement` (menyisipkan `0x00` jika `byte[0] >= 0x80`) pada pembentukan kunci publik keluar, serta `decodeBigEndianTwosComplementTo32Bytes` (menghapus `0x00` tanda dan melakukan padding jika < 32 bytes) saat memproses kunci publik masuk dari peer. Memperbaiki kebocoran continuation pada `NearbyBonjourServiceResolver` dengan retensi siklus hidup kuat hingga resolusi selesai.


---

## 2. Analisis Pre-Mortem (Skenario Kegagalan 3 Bulan ke Depan)

> **Uji Pre-Mortem**: *"Bayangkan 3 bulan dari sekarang aplikasi ini gagal memuaskan pengguna. Apa kemungkinan akar masalah terbesarnya?"*

- **Akar Masalah Teridentifikasi**:
  1. *AP Isolation pada Wi-Fi Publik*: Router memblokir koneksi TCP antar perangkat lokal, sehingga perangkat terdeteksi di radar tetapi transfer selalu timeout.
  2. *Timeout Handshake karena Layar HP Mati*: Pengguna Samsung tidak membuka kunci layar, menyebabkan handshake UKEY2 terhenti di tengah jalan.
- **Mitigasi Proaktif yang Diadopsi**:
  1. *Connectivity Advisor*: Mesin pemantau soket TCP mendeteksi kegagalan jabat tangan dan langsung memunculkan panduan interaktif 2-langkah untuk mengaktifkan Mobile Hotspot Samsung atau USB-C Tethering.
  2. *Interactive Guidance*: Dialog modal pengiriman menampilkan pengingat visual: *"Pastikan layar HP menyala dan kunci layar telah terbuka"*.

---

## 3. Alternatif yang Ditolak (Rejected Alternatives)

| Alternatif | Alasan Penolakan |
| :--- | :--- |
| **Kustom BLE Peripheral Advertiser (Fast Pair `0xFE2C`)** | Ditolak karena Core Bluetooth macOS secara eksplisit melarang aplikasi non-Apple mengiklankan `CBAdvertisementDataServiceDataKey` tanpa entitlement privat. Memaksa ini akan menuntut penonaktifan SIP (System Integrity Protection) yang melanggar standar keamanan. |
| **Instalasi Aplikasi Pendamping (Companion APK) di Android** | Ditolak karena bertentangan dengan visi produk: menghadirkan pengalaman AirDrop nirkabel murni tanpa membebani penerima dengan instalasi aplikasi tambahan. |
| **Layanan Relay Cloud / WebSocket Eksternal** | Ditolak karena mengorbankan privasi pengguna, membutuhkan infrastruktur server berbayar, dan membatasi throughput transfer pada koneksi internet pengguna. |
