import Foundation
import Network

enum WakeOnLANService {
    static func normalizedMACAddress(_ value: String) -> String? {
        let hex = value
            .uppercased()
            .filter { $0.isHexDigit }

        guard hex.count == 12 else { return nil }

        var grouped: [String] = []
        grouped.reserveCapacity(6)
        var index = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(index, offsetBy: 2)
            grouped.append(String(hex[index..<next]))
            index = next
        }
        return grouped.joined(separator: ":")
    }

    static func sendMagicPacket(macAddress: String, preferredHost: String?) async throws {
        guard let macBytes = macBytes(from: macAddress) else {
            throw TVControllerError.invalidWakeMACAddress
        }

        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }

        let targets = wakeTargets(preferredHost: preferredHost)
        var successfulSends = 0
        var lastError: Error?

        // Send short bursts to improve wake reliability across consumer routers.
        for burstIndex in 0..<3 {
            for host in targets {
                for port: UInt16 in [9, 7] {
                    do {
                        try await send(packet: packet, host: host, port: port)
                        successfulSends += 1
                    } catch {
                        lastError = error
                    }
                }
            }

            if burstIndex < 2 {
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
        }

        guard successfulSends > 0 else {
            let reason = (lastError as NSError?)?.localizedDescription ?? "Wake packet failed to send."
            throw TVControllerError.networkFailure(reason)
        }
    }

    private static func wakeTargets(preferredHost: String?) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func append(_ host: String?) {
            guard let raw = host?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
            guard seen.insert(raw).inserted else { return }
            ordered.append(raw)
        }

        append(preferredHost)
        append(directedBroadcastAddress(for: preferredHost))
        append("255.255.255.255")
        return ordered
    }

    private static func directedBroadcastAddress(for host: String?) -> String? {
        guard let host = host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            return nil
        }

        let components = host.split(separator: ".")
        guard components.count == 4 else { return nil }

        var octets: [Int] = []
        octets.reserveCapacity(4)
        for part in components {
            guard let value = Int(part), (0...255).contains(value) else { return nil }
            octets.append(value)
        }

        octets[3] = 255
        return "\(octets[0]).\(octets[1]).\(octets[2]).\(octets[3])"
    }

    private static func macBytes(from normalizedMAC: String) -> [UInt8]? {
        let components = normalizedMAC.split(separator: ":")
        guard components.count == 6 else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(6)
        for part in components {
            guard let byte = UInt8(part, radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes
    }

    private static func send(packet: Data, host: String, port: UInt16) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw TVControllerError.networkFailure("Invalid Wake-on-LAN port.")
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .udp
        )
        let queue = DispatchQueue(label: "com.reggieboi.tvremote.wol.\(host).\(port)")
        connection.start(queue: queue)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: packet, completion: .contentProcessed { error in
                connection.cancel()
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
