//
//  QRPairingSheetView.swift
//  TossShareUI
//
//  Created for TossShare for macOS.
//

import SwiftUI
import CoreImage
import AppKit

/// Modal sheet interaktif untuk menampilkan kode QR pairing sebagai fallback jika Samsung dalam mode privasi "Hanya Kontak".
public struct QRPairingSheetView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var isCopied: Bool = false

    private let hostName: String
    private let ipAddress: String
    private let port: Int
    private let pairingURI: String

    public init(
        hostName: String = Host.current().localizedName ?? "Mac",
        ipAddress: String? = nil,
        port: Int = 44445
    ) {
        self.hostName = hostName
        let resolvedIP = ipAddress ?? QRPairingSheetView.getLocalIPAddress() ?? "127.0.0.1"
        self.ipAddress = resolvedIP
        self.port = port
        self.pairingURI = "quickshare://connect?name=\(hostName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? hostName)&ip=\(resolvedIP)&port=\(port)"
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("QR Pairing Cepat")
                        .font(Theme.Typography.headline)
                        .fontWeight(.bold)

                    Text("Fallback jika perangkat Samsung berada dalam mode privasi 'Hanya Kontak'")
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // QR Code Container
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radii.card)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

                if let qrImage = generateQRCode(from: pairingURI) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(Theme.Spacing.md)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Gagal membuat QR Code")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 220, height: 220)
            .padding(.vertical, Theme.Spacing.xs)

            // Info Box
            VStack(spacing: 6) {
                HStack {
                    Label(hostName, systemImage: "laptopcomputer")
                        .font(Theme.Typography.caption)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("\(ipAddress):\(port)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radii.small)
                        .fill(Theme.Colors.surfaceCard)
                )

                // Instruksi Pengguna
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.accentSamsung)

                    Text("Pindai QR ini menggunakan kamera ponsel Samsung Anda atau hubungkan ke jaringan Wi-Fi lokal yang sama.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 12) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pairingURI, forType: .string)
                    isCopied = true
                    TossShareHaptics.performDropSnapped()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied = false
                    }
                } label: {
                    HStack {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Tersalin!" : "Salin Tautan Pairing")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    dismiss()
                } label: {
                    Text("Tutup")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 360)
        .background(.ultraThinMaterial)
    }

    // MARK: - CoreImage QR Code Generator

    private func generateQRCode(from string: String) -> NSImage? {
        let data = Data(string.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputCIImage = filter.outputImage else { return nil }

        // Skalakan agar tajam tanpa blur piksel
        let transform = CGAffineTransform(scaleX: 8, y: 8)
        let scaledCIImage = outputCIImage.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaledCIImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    // MARK: - Local IPv4 Resolver Helper

    public static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // Utamakan Wi-Fi (en0)
                if name == "en0" || address == nil {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        let cleanLen = hostname.firstIndex(of: 0) ?? hostname.count
                        let bytes = hostname[0..<cleanLen].map { UInt8(bitPattern: $0) }
                        address = String(decoding: bytes, as: UTF8.self)
                        if name == "en0" { break }
                    }
                }
            }
        }
        return address
    }
}
