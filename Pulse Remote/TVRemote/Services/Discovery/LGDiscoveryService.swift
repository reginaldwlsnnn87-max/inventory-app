import Foundation
import Network
import Darwin

@MainActor
final class LGDiscoveryService {
    var onDevicesChanged: (([TVDevice]) -> Void)?
    var onFailure: ((TVControllerError) -> Void)?

    private let browserQueue = DispatchQueue(label: "com.reggieboi.tvremote.discovery")
    private var browser: NWBrowser?
    private var multicastGroup: NWConnectionGroup?
    private var devicesByID: [String: TVDevice] = [:]
    private var metadataResolutionTasks: [String: Task<Void, Never>] = [:]
    private var scanRefreshTask: Task<Void, Never>?
    private var emptyResultsHintTask: Task<Void, Never>?
    private var subnetFallbackTask: Task<Void, Never>?

    func start() {
        stop()
        devicesByID.removeAll()
        onDevicesChanged?([])
        startBonjourFallback()
        startSSDPDiscovery()
        scheduleSubnetFallback()
        scheduleEmptyResultsHint()
    }

    func stop() {
        scanRefreshTask?.cancel()
        scanRefreshTask = nil

        emptyResultsHintTask?.cancel()
        emptyResultsHintTask = nil
        subnetFallbackTask?.cancel()
        subnetFallbackTask = nil

        metadataResolutionTasks.values.forEach { $0.cancel() }
        metadataResolutionTasks.removeAll()

        multicastGroup?.cancel()
        multicastGroup = nil

        browser?.cancel()
        browser = nil
    }

    private func startBonjourFallback() {
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: "_webos-second-screen._tcp",
            domain: nil
        )
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: descriptor, using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleBrowserState(state)
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.consumeBonjour(results: results)
            }
        }

        self.browser = browser
        browser.start(queue: browserQueue)
    }

    private func startSSDPDiscovery() {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("239.255.255.250"),
            port: NWEndpoint.Port(rawValue: 1900) ?? .http
        )

        do {
            let group = try NWMulticastGroup(for: [endpoint])
            let parameters = NWParameters.udp
            parameters.includePeerToPeer = false
            parameters.allowLocalEndpointReuse = true

            let connectionGroup = NWConnectionGroup(with: group, using: parameters)
            connectionGroup.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.handleGroupState(state)
                }
            }
            connectionGroup.setReceiveHandler(
                maximumMessageSize: 65_535,
                rejectOversizedMessages: true
            ) { [weak self] message, content, _ in
                guard let self, let content else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.consumeSSDPResponse(data: content, endpoint: message.remoteEndpoint)
                }
            }
            multicastGroup = connectionGroup
            connectionGroup.start(queue: browserQueue)
        } catch {
            onFailure?(
                .networkFailure(
                    "Could not start SSDP discovery. Check Local Network and multicast access."
                )
            )
        }
    }

    private func handleGroupState(_ state: NWConnectionGroup.State) {
        switch state {
        case .ready:
            sendDiscoveryProbe()
            schedulePeriodicProbe()
        case let .failed(error), let .waiting(error):
            if isPermissionDeniedMessage(error.localizedDescription) {
                onFailure?(.localNetworkPermissionDenied)
            } else {
                onFailure?(
                    .networkFailure(
                        "Discovery is blocked. Enable Local Network, then check router multicast settings."
                    )
                )
            }
        case .cancelled:
            break
        case .setup:
            break
        @unknown default:
            break
        }
    }

    private func schedulePeriodicProbe() {
        scanRefreshTask?.cancel()
        scanRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                self.sendDiscoveryProbe()
            }
        }
    }

    private func sendDiscoveryProbe() {
        let searchTargets = [
            "ssdp:all",
            "upnp:rootdevice",
            "urn:lge-com:device:LGSmartTV:1",
            "urn:lge-com:service:webos-second-screen:1",
            "urn:schemas-upnp-org:device:Basic:1",
            "urn:schemas-upnp-org:service:dial:1",
            "urn:schemas-upnp-org:device:MediaRenderer:1"
        ]

        for target in searchTargets {
            let payload = """
            M-SEARCH * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            MAN: "ssdp:discover"\r
            MX: 2\r
            ST: \(target)\r
            USER-AGENT: iOS/\(AppBranding.displayName)\r
            \r
            """
            multicastGroup?.send(
                content: Data(payload.utf8),
                completion: { _ in }
            )
        }
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            break
        case let .failed(error), let .waiting(error):
            if isPermissionDenied(error) {
                onFailure?(.localNetworkPermissionDenied)
            } else {
                onFailure?(.networkFailure(error.localizedDescription))
            }
        case .cancelled:
            break
        case .setup:
            break
        @unknown default:
            break
        }
    }

    private func consumeBonjour(results: Set<NWBrowser.Result>) {
        emptyResultsHintTask?.cancel()
        emptyResultsHintTask = nil

        for result in results {
            guard let device = buildDevice(from: result) else { continue }
            devicesByID[device.id] = device
        }
        publishDevices()
    }

    private func buildDevice(from result: NWBrowser.Result) -> TVDevice? {
        guard let endpointInfo = endpointInfo(from: result.endpoint) else {
            return nil
        }

        let manufacturer = "LG"
        let model: String? = nil

        if !looksLikeLG(name: endpointInfo.name, model: model, manufacturer: manufacturer) {
            return nil
        }

        return TVDevice(
            id: "lg-\(endpointInfo.host.lowercased())",
            name: endpointInfo.name,
            ip: endpointInfo.host,
            manufacturer: manufacturer,
            model: model,
            capabilities: Set(TVCapability.allCases),
            port: endpointInfo.port
        )
    }

    private func consumeSSDPResponse(data: Data, endpoint: NWEndpoint?) {
        guard let response = String(data: data, encoding: .utf8) else { return }
        guard response.localizedCaseInsensitiveContains("HTTP/1.1 200") else { return }

        let headers = parseHeaders(from: response)
        let st = headers["st"]?.lowercased() ?? ""
        let usn = headers["usn"]?.lowercased() ?? ""
        let server = headers["server"]?.lowercased() ?? ""
        let location = headers["location"]?.lowercased() ?? ""

        let looksLikeLG = st.contains("webos-second-screen")
            || usn.contains("lge")
            || server.contains("webos")
            || server.contains("lge")
            || location.contains("lge")

        guard looksLikeLG else { return }

        let locationURL = URL(string: headers["location"] ?? "")
        let host = hostString(from: endpoint) ?? locationURL?.host
        guard let host else { return }
        let descriptorPort = locationURL?.port ?? 3000
        let deviceID = headers["usn"] ?? "lg-\(host)"

        var device = TVDevice(
            id: deviceID,
            name: "LG webOS TV",
            ip: host,
            manufacturer: "LG",
            model: nil,
            capabilities: Set(TVCapability.allCases),
            port: descriptorPort
        )

        if let existing = devicesByID[deviceID] {
            device.lastConnectedAt = existing.lastConnectedAt
            if existing.name != "LG webOS TV" {
                device.name = existing.name
            }
            if let existingModel = existing.model, !existingModel.isEmpty {
                device.model = existingModel
            }
        }

        devicesByID[deviceID] = device
        publishDevices()

        if let locationURL {
            resolveDeviceMetadata(from: locationURL, forDeviceID: deviceID)
        }
    }

    private func parseHeaders(from response: String) -> [String: String] {
        var headers: [String: String] = [:]
        let normalized = response.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        for line in lines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        return headers
    }

    private func scheduleSubnetFallback() {
        subnetFallbackTask?.cancel()
        subnetFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self else { return }
            guard self.devicesByID.isEmpty else { return }
            await self.runSubnetFallbackScan()
        }
    }

    private func runSubnetFallbackScan() async {
        guard let localIP = Self.wifiIPv4Address(),
              let prefix = Self.ipv4Prefix(from: localIP) else {
            return
        }

        let candidates = (1...254)
            .map { "\(prefix).\($0)" }
            .filter { $0 != localIP }

        let batchSize = 24
        var index = 0

        while index < candidates.count, !Task.isCancelled, devicesByID.isEmpty {
            let upperBound = min(index + batchSize, candidates.count)
            let batch = Array(candidates[index..<upperBound])

            await withTaskGroup(of: (host: String, port: Int)?.self) { group in
                for host in batch {
                    group.addTask {
                        if await Self.probeTCP(host: host, port: 3000) {
                            return (host, 3000)
                        }
                        if await Self.probeTCP(host: host, port: 3001) {
                            return (host, 3001)
                        }
                        return nil
                    }
                }

                for await result in group {
                    guard let result else { continue }
                    self.addSubnetCandidate(host: result.host, port: result.port)
                }
            }

            index = upperBound
        }
    }

    private func addSubnetCandidate(host: String, port: Int) {
        let deviceID = "lg-\(host)"
        guard devicesByID[deviceID] == nil else { return }

        let device = TVDevice(
            id: deviceID,
            name: "LG TV (\(host))",
            ip: host,
            manufacturer: "LG",
            model: nil,
            capabilities: Set(TVCapability.allCases),
            port: port
        )
        devicesByID[deviceID] = device
        publishDevices()
    }

    private func resolveDeviceMetadata(from locationURL: URL, forDeviceID deviceID: String) {
        if metadataResolutionTasks[deviceID] != nil {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { metadataResolutionTasks[deviceID] = nil }

            var request = URLRequest(url: locationURL)
            request.timeoutInterval = 2.5
            request.cachePolicy = .reloadIgnoringLocalCacheData

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let xml = String(data: data, encoding: .utf8) else { return }
                let friendlyName = xmlTag("friendlyName", in: xml) ?? "LG webOS TV"
                let manufacturer = xmlTag("manufacturer", in: xml) ?? "LG"
                let model = xmlTag("modelName", in: xml)

                guard manufacturer.localizedCaseInsensitiveContains("lg") else { return }
                guard var current = devicesByID[deviceID] else { return }

                current.name = friendlyName.isEmpty ? current.name : friendlyName
                if let model, !model.isEmpty {
                    current.model = model
                }
                current.manufacturer = manufacturer
                devicesByID[deviceID] = current
                publishDevices()
            } catch {
                // Keep lightweight: metadata lookup is optional.
            }
        }

        metadataResolutionTasks[deviceID] = task
    }

    private func xmlTag(_ tag: String, in xml: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let openRange = xml.range(of: open), let closeRange = xml.range(of: close) else {
            return nil
        }
        let value = xml[openRange.upperBound..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }

    private func hostString(from endpoint: NWEndpoint?) -> String? {
        guard let endpoint else { return nil }

        switch endpoint {
        case let .hostPort(host, _):
            return host.rawHostString
        default:
            return nil
        }
    }

    private func endpointInfo(from endpoint: NWEndpoint) -> (name: String, host: String, port: Int)? {
        switch endpoint {
        case let .service(name, _, _, _):
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { return nil }
            return (
                name: cleanName,
                host: "\(cleanName).local",
                port: 3000
            )

        case let .hostPort(host, port):
            let hostString = host.rawHostString
            let portValue = Int(port.rawValue)
            let displayName = hostString
            return (name: displayName, host: hostString, port: portValue)

        default:
            return nil
        }
    }

    private func publishDevices() {
        let devices = devicesByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        onDevicesChanged?(devices)

        if devices.isEmpty {
            scheduleEmptyResultsHint()
        } else {
            emptyResultsHintTask?.cancel()
            emptyResultsHintTask = nil
        }
    }

    private func looksLikeLG(name: String, model: String?, manufacturer: String) -> Bool {
        let nameToken = name.lowercased()
        let modelToken = model?.lowercased() ?? ""
        let manufacturerToken = manufacturer.lowercased()
        return manufacturerToken.contains("lg")
            || modelToken.contains("webos")
            || modelToken.contains("lg")
            || nameToken.contains("webos")
            || nameToken.contains("lg")
    }

    private func isPermissionDenied(_ error: NWError) -> Bool {
        let message = error.localizedDescription.lowercased()
        if message.contains("policy denied") || message.contains("operation not permitted") {
            return true
        }

        if case let .posix(code) = error, code == .EPERM {
            return true
        }

        return false
    }

    private func isPermissionDeniedMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("policy denied")
            || normalized.contains("operation not permitted")
            || normalized.contains("permission denied")
    }

    private func scheduleEmptyResultsHint() {
        emptyResultsHintTask?.cancel()
        emptyResultsHintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            guard let self else { return }
            if devicesByID.isEmpty {
                onFailure?(
                    .networkFailure(
                        "No LG TVs were discovered. Check Wi-Fi subnet, router multicast/client isolation, and LG Connect Apps on the TV."
                    )
                )
            }
        }
    }
}

private extension LGDiscoveryService {
    static func ipv4Prefix(from address: String) -> String? {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2])"
    }

    static func wifiIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp, isRunning, !isLoopback else { continue }

            guard let address = current.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let interfaceName = String(cString: current.pointee.ifa_name)
            guard interfaceName.hasPrefix("en") else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            let result = getnameinfo(
                address,
                length,
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let host = String(cString: hostBuffer)
            if host.contains(".") {
                return host
            }
        }
        return nil
    }

    static func probeTCP(host: String, port: UInt16, timeout: TimeInterval = 0.45) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: false)
                return
            }

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )
            let queue = DispatchQueue(label: "com.reggieboi.tvremote.discovery.probe.\(host).\(port)")
            let completionGate = ProbeCompletionGate()
            let finish: @Sendable (Bool) -> Void = { success in
                guard completionGate.tryComplete() else { return }
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: success)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed:
                    finish(false)
                case .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
        }
    }
}

private final class ProbeCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var hasCompleted = false

    nonisolated func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasCompleted else { return false }
        hasCompleted = true
        return true
    }
}

private extension NWEndpoint.Host {
    var rawHostString: String {
        switch self {
        case let .name(value, _):
            return value
        case let .ipv4(address):
            return address.debugDescription
        case let .ipv6(address):
            return address.debugDescription
        @unknown default:
            return debugDescription
        }
    }
}
