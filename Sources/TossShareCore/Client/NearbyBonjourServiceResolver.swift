//
//  NearbyBonjourServiceResolver.swift
//  TossShareCore
//
//  Created for TossShare for macOS.
//

import Darwin
import Foundation
import Network

/// Endpoint hasil resolusi NetService Bonjour yang berisi alamat host dan port target.
public struct NearbyResolvedBonjourEndpoint: Equatable, Sendable {
    public let host: String
    public let port: UInt16
    public let isIPv4: Bool
    public let isLinkLocal: Bool
    public let description: String

    public init(
        host: String,
        port: UInt16,
        isIPv4: Bool,
        isLinkLocal: Bool,
        description: String? = nil
    ) {
        self.host = host
        self.port = port
        self.isIPv4 = isIPv4
        self.isLinkLocal = isLinkLocal
        self.description = description ?? (isIPv4 ? "\(host):\(port)" : "[\(host)]:\(port)")
    }
}

/// Resolver asinkron untuk mengekstrak alamat IPv4/port riil dari nama instance mDNS Bonjour.
public final class NearbyBonjourServiceResolver: NSObject, NetServiceDelegate, @unchecked Sendable {

    private let service: NetService
    private let resolveTimeout: TimeInterval
    private var completion: (([NearbyResolvedBonjourEndpoint]) -> Void)?
    private var isFinished = false
    private let lock = NSLock()
    private var timeoutWorkItem: DispatchWorkItem?

    public init(
        name: String,
        type: String = TossShareCore.quickShareMDNSServiceType,
        domain: String = "local.",
        resolveTimeout: TimeInterval = 2.0,
        completion: @escaping ([NearbyResolvedBonjourEndpoint]) -> Void
    ) {
        let normalizedDomain = domain.hasSuffix(".") ? domain : "\(domain)."
        let normalizedType = type.hasSuffix(".") ? type : "\(type)."
        self.service = NetService(domain: normalizedDomain, type: normalizedType, name: name)
        self.resolveTimeout = resolveTimeout
        self.completion = completion
        super.init()
    }

    /// Memulai proses resolusi mDNS.
    public func start() {
        service.delegate = self
        service.schedule(in: .main, forMode: .common)
        service.resolve(withTimeout: resolveTimeout)

        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(endpoints: [])
        }
        self.timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + resolveTimeout + 0.2, execute: workItem)
    }

    deinit {
        finish(endpoints: [], notify: true)
    }

    /// Membatalkan resolusi.
    public func cancel() {
        finish(endpoints: [], notify: true)
    }

    // MARK: - NetServiceDelegate

    public func netServiceDidResolveAddress(_ sender: NetService) {
        let endpoints = Self.parseResolvedAddresses(from: sender)
        finish(endpoints: endpoints)
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        finish(endpoints: [])
    }

    // MARK: - Private Helpers

    private func finish(endpoints: [NearbyResolvedBonjourEndpoint], notify: Bool = true) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        service.stop()
        service.remove(from: .main, forMode: .common)
        service.delegate = nil

        let callback = completion
        completion = nil
        lock.unlock()

        if notify {
            DispatchQueue.main.async {
                callback?(endpoints)
            }
        }
    }

    public static func parseResolvedAddresses(from service: NetService) -> [NearbyResolvedBonjourEndpoint] {
        guard let addresses = service.addresses else { return [] }
        var list: [NearbyResolvedBonjourEndpoint] = []
        var seen = Set<String>()

        for addrData in addresses {
            if let parsed = parseSockaddr(data: addrData) {
                let ep = NearbyResolvedBonjourEndpoint(
                    host: parsed.host,
                    port: parsed.port,
                    isIPv4: parsed.isIPv4,
                    isLinkLocal: parsed.isLinkLocal
                )
                if seen.insert(ep.description).inserted {
                    list.append(ep)
                }
            }
        }

        // Urutkan: IPv4 terlebih dahulu, lalu non-link-local, lalu link-local
        return list.sorted { lhs, rhs in
            if lhs.isIPv4 != rhs.isIPv4 {
                return lhs.isIPv4
            }
            if lhs.isLinkLocal != rhs.isLinkLocal {
                return !lhs.isLinkLocal
            }
            return lhs.description < rhs.description
        }
    }

    public static func parseSockaddr(data: Data) -> (host: String, port: UInt16, isIPv4: Bool, isLinkLocal: Bool)? {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            let sockaddrPointer = baseAddress.assumingMemoryBound(to: sockaddr.self)
            let family = Int32(sockaddrPointer.pointee.sa_family)

            guard family == AF_INET || family == AF_INET6 else { return nil }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var portBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))
            let res = getnameinfo(
                sockaddrPointer,
                socklen_t(data.count),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                &portBuffer,
                socklen_t(portBuffer.count),
                NI_NUMERICHOST | NI_NUMERICSERV
            )
            guard res == 0 else { return nil }
            let host = String(cString: hostBuffer)
            guard let portValue = UInt16(String(cString: portBuffer)) else { return nil }

            let isIPv4 = (family == AF_INET)
            let isLinkLocal = !isIPv4 && host.lowercased().hasPrefix("fe80:")
            return (host, portValue, isIPv4, isLinkLocal)
        }
    }

    /// API Asynchronous Swift Concurrency untuk menyelesaikan nama instans mDNS.
    public static func resolve(
        name: String,
        type: String = TossShareCore.quickShareMDNSServiceType,
        domain: String = "local.",
        timeout: TimeInterval = 2.0
    ) async -> [NearbyResolvedBonjourEndpoint] {
        await withCheckedContinuation { continuation in
            let resumed = AtomicFlag()
            var strongResolver: NearbyBonjourServiceResolver?
            strongResolver = NearbyBonjourServiceResolver(
                name: name,
                type: type,
                domain: domain,
                resolveTimeout: timeout
            ) { endpoints in
                if resumed.fireOnce() {
                    continuation.resume(returning: endpoints)
                }
                strongResolver = nil
            }
            strongResolver?.start()
        }
    }
}
