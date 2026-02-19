import Foundation
import AppIntents
import Security

struct PulseRemoteWidgetCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Pulse Remote Command"
    static var description = IntentDescription("Send a quick command to your LG TV directly from the widget.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Command")
    var command: PulseWidgetCommand

    init() {}

    init(command: PulseWidgetCommand) {
        self.command = command
    }

    func perform() async throws -> some IntentResult {
        try await PulseRemoteWidgetCommandRunner().execute(command: command)
        return .result()
    }
}

private enum PulseWidgetIntentError: LocalizedError {
    case missingContext
    case invalidAddress
    case notConnected
    case requestTimedOut
    case requestRejected(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingContext:
            return "Open Pulse Remote once to finish setup, then try again."
        case .invalidAddress:
            return "TV address is invalid. Reconnect in Pulse Remote."
        case .notConnected:
            return "TV session is unavailable right now."
        case .requestTimedOut:
            return "TV did not respond in time."
        case let .requestRejected(message):
            return message
        case .invalidResponse:
            return "TV returned an unexpected response."
        }
    }
}

private struct PulseWidgetTVContext: Codable {
    let deviceID: String
    let ip: String
    let port: Int
    let secure: Bool
    let clientKey: String
    let updatedAt: Date
}

private enum PulseWidgetContextConstants {
    static let keychainService = "com.reggieboi.inventory-app.tvremote.widget-context"
    static let keychainAccount = "tvremote.widget.context.v1"
}

private struct PulseWidgetKeychainStore {
    private let service: String

    init(service: String = PulseWidgetContextConstants.keychainService) {
        self.service = service
    }

    func string(for account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw PulseWidgetIntentError.requestRejected("Secure storage access failed (\(status)).")
        }

        guard
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw PulseWidgetIntentError.invalidResponse
        }

        return value
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct PulseWidgetContextStore {
    private let keychain = PulseWidgetKeychainStore()
    private let decoder = JSONDecoder()

    func loadRequiredContext() throws -> PulseWidgetTVContext {
        guard
            let raw = try keychain.string(for: PulseWidgetContextConstants.keychainAccount),
            let data = raw.data(using: .utf8)
        else {
            throw PulseWidgetIntentError.missingContext
        }

        do {
            return try decoder.decode(PulseWidgetTVContext.self, from: data)
        } catch {
            throw PulseWidgetIntentError.missingContext
        }
    }
}

private struct PulseRemoteWidgetCommandRunner {
    func execute(command: PulseWidgetCommand) async throws {
        let context = try PulseWidgetContextStore().loadRequiredContext()
        let endpoints = connectionEndpoints(for: context)
        var lastError: Error = PulseWidgetIntentError.notConnected

        for endpoint in endpoints {
            var client = PulseWidgetLGSocketClient()
            do {
                try client.connect(
                    host: context.ip,
                    port: endpoint.port,
                    secure: endpoint.secure
                )
                defer { client.disconnect() }

                try await client.register(clientKey: context.clientKey)
                try await dispatch(command: command, through: &client)
                return
            } catch {
                lastError = error
                client.disconnect()
            }
        }

        throw lastError
    }

    private func dispatch(command: PulseWidgetCommand, through client: inout PulseWidgetLGSocketClient) async throws {
        switch command {
        case .home:
            try await client.sendButton("HOME")
        case .volumeDown:
            _ = try await client.request(uri: "ssap://audio/volumeDown", timeout: 2.2)
        case .playPause:
            do {
                try await client.sendButton("PLAYPAUSE")
            } catch {
                let isPlaying = (try? await client.currentPlaybackIsPlaying()) ?? false
                try await client.sendButton(isPlaying ? "PAUSE" : "PLAY")
            }
        case .volumeUp:
            _ = try await client.request(uri: "ssap://audio/volumeUp", timeout: 2.2)
        case .mute:
            let currentlyMuted = (try? await client.currentMuteState()) ?? false
            _ = try await client.request(
                uri: "ssap://audio/setMute",
                payload: ["mute": !currentlyMuted],
                timeout: 2.2
            )
        case .powerOff:
            _ = try await client.request(uri: "ssap://system/turnOff", timeout: 2.6)
        }
    }

    private func connectionEndpoints(for context: PulseWidgetTVContext) -> [LGWidgetEndpoint] {
        var endpoints: [LGWidgetEndpoint] = []
        var seen = Set<LGWidgetEndpoint>()

        func append(_ endpoint: LGWidgetEndpoint) {
            guard seen.insert(endpoint).inserted else { return }
            endpoints.append(endpoint)
        }

        append(LGWidgetEndpoint(port: context.port, secure: context.secure))
        append(LGWidgetEndpoint(port: 3000, secure: false))
        append(LGWidgetEndpoint(port: 3001, secure: true))
        return endpoints
    }
}

private struct LGWidgetEndpoint: Hashable {
    let port: Int
    let secure: Bool
}

private struct PulseWidgetLGSocketClient {
    typealias JSON = [String: Any]

    private let session: URLSession
    private var socketTask: URLSessionWebSocketTask?

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    mutating func connect(host rawHost: String, port: Int, secure: Bool) throws {
        disconnect()

        let host = normalizeHost(rawHost)
        guard !host.isEmpty else {
            throw PulseWidgetIntentError.invalidAddress
        }

        var components = URLComponents()
        components.scheme = secure ? "wss" : "ws"
        components.host = host
        components.port = port

        guard let url = components.url else {
            throw PulseWidgetIntentError.invalidAddress
        }

        let task = session.webSocketTask(with: url)
        socketTask = task
        task.resume()
    }

    mutating func disconnect() {
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
    }

    mutating func register(clientKey: String) async throws {
        guard !clientKey.isEmpty else {
            throw PulseWidgetIntentError.missingContext
        }

        let requestID = "register_\(UUID().uuidString)"
        try await send(dictionary: registerPayload(requestID: requestID, clientKey: clientKey))

        let deadline = Date().addingTimeInterval(9.5)
        while Date() < deadline {
            let remaining = max(deadline.timeIntervalSinceNow, 0.25)
            let response = try await receiveJSONObject(timeout: remaining)
            let type = (response["type"] as? String ?? "").lowercased()
            let id = response["id"] as? String

            if type == "registered" {
                return
            }

            if id == requestID, type == "error" {
                throw PulseWidgetIntentError.requestRejected(errorMessage(from: response))
            }

            if id == requestID, type == "response", responseIndicatesFailure(response) {
                throw PulseWidgetIntentError.requestRejected(errorMessage(from: response))
            }
        }

        throw PulseWidgetIntentError.requestTimedOut
    }

    mutating func request(
        uri: String,
        payload: JSON? = nil,
        timeout: TimeInterval
    ) async throws -> JSON {
        guard socketTask != nil else {
            throw PulseWidgetIntentError.notConnected
        }

        let requestID = "req_\(UUID().uuidString)"
        var body: JSON = [
            "id": requestID,
            "type": "request",
            "uri": uri
        ]
        if let payload {
            body["payload"] = payload
        }

        try await send(dictionary: body)

        let deadline = Date().addingTimeInterval(max(timeout, 0.8))
        while Date() < deadline {
            let remaining = max(deadline.timeIntervalSinceNow, 0.2)
            let response = try await receiveJSONObject(timeout: remaining)
            guard response["id"] as? String == requestID else { continue }

            let type = (response["type"] as? String ?? "").lowercased()
            if type == "error" || responseIndicatesFailure(response) {
                throw PulseWidgetIntentError.requestRejected(errorMessage(from: response))
            }

            return response
        }

        throw PulseWidgetIntentError.requestTimedOut
    }

    mutating func sendButton(_ name: String) async throws {
        do {
            _ = try await request(
                uri: "ssap://com.webos.service.networkinput/sendButton",
                payload: ["name": name],
                timeout: 2.2
            )
        } catch {
            guard shouldFallbackToPointerButton(after: error) else { throw error }
            try await sendPointerButton(name)
        }
    }

    mutating func currentMuteState() async throws -> Bool {
        let response = try await request(uri: "ssap://audio/getVolume", timeout: 2.2)
        let payload = response["payload"] as? JSON
        return (payload?["mute"] as? Bool) ?? (payload?["muted"] as? Bool) ?? false
    }

    mutating func currentPlaybackIsPlaying() async throws -> Bool {
        let response = try await request(uri: "ssap://media.controls/getMediaInfo", timeout: 2.2)
        let payload = response["payload"] as? JSON
        let status = ((payload?["playStatus"] as? String) ?? (payload?["status"] as? String) ?? "").lowercased()

        if status.contains("pause") || status.contains("stop") || status.contains("idle") {
            return false
        }

        if status.contains("play") || status.contains("buffer") {
            return true
        }

        return false
    }

    private mutating func sendPointerButton(_ name: String) async throws {
        let socketResponse = try await request(
            uri: "ssap://com.webos.service.networkinput/getPointerInputSocket",
            timeout: 2.6
        )

        guard
            let payload = socketResponse["payload"] as? JSON,
            let socketPath = payload["socketPath"] as? String,
            let url = URL(string: socketPath)
        else {
            throw PulseWidgetIntentError.invalidResponse
        }

        let pointerTask = session.webSocketTask(with: url)
        pointerTask.resume()
        defer { pointerTask.cancel(with: .goingAway, reason: nil) }
        try await pointerTask.send(.string("type:button\nname:\(name)\n\n"))
    }

    private mutating func send(dictionary: JSON) async throws {
        guard let socketTask else {
            throw PulseWidgetIntentError.notConnected
        }

        let data = try JSONSerialization.data(withJSONObject: dictionary)
        guard let text = String(data: data, encoding: .utf8) else {
            throw PulseWidgetIntentError.invalidResponse
        }

        try await socketTask.send(.string(text))
    }

    private mutating func receiveJSONObject(timeout: TimeInterval) async throws -> JSON {
        guard let socketTask else {
            throw PulseWidgetIntentError.notConnected
        }

        let message = try await Self.withTimeout(seconds: timeout) {
            try await socketTask.receive()
        }

        let data: Data
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(raw):
            data = raw
        @unknown default:
            throw PulseWidgetIntentError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? JSON else {
            throw PulseWidgetIntentError.invalidResponse
        }

        return json
    }

    private func registerPayload(requestID: String, clientKey: String) -> JSON {
        let permissions = [
            "LAUNCH",
            "LAUNCH_WEBAPP",
            "APP_TO_APP",
            "CONTROL_AUDIO",
            "CONTROL_POWER",
            "READ_RUNNING_APPS",
            "READ_INPUT_DEVICE_LIST",
            "READ_CURRENT_CHANNEL",
            "READ_INSTALLED_APPS",
            "CONTROL_INPUT_JOYSTICK",
            "CONTROL_INPUT_MEDIA_PLAYBACK",
            "CONTROL_INPUT_MEDIA_RECORDING",
            "CONTROL_INPUT_TEXT",
            "CONTROL_MOUSE_AND_KEYBOARD"
        ]

        return [
            "id": requestID,
            "type": "register",
            "payload": [
                "forcePairing": false,
                "pairingType": "PROMPT",
                "client-key": clientKey,
                "manifest": [
                    "manifestVersion": 1,
                    "appVersion": "1.0",
                    "permissions": permissions,
                    "signed": [
                        "appId": "com.reggieboi.pulseremote",
                        "created": "2026-02-16",
                        "localizedAppNames": ["": "Pulse Remote"],
                        "localizedVendorNames": ["": "Pulse Remote"],
                        "permissions": permissions,
                        "serial": "f0f2568394e34c18a6af7d0a9d0db8d4",
                        "vendorId": "com.reggieboi"
                    ]
                ]
            ]
        ]
    }

    private func responseIndicatesFailure(_ json: JSON) -> Bool {
        let payload = json["payload"] as? JSON

        if let topLevelReturn = json["returnValue"] as? Bool, !topLevelReturn {
            return true
        }
        if let payloadReturn = payload?["returnValue"] as? Bool, !payloadReturn {
            return true
        }
        if let payloadError = payload?["errorText"] as? String, !payloadError.isEmpty {
            return true
        }
        if let payloadCode = (payload?["errorCode"] as? Int) ?? (payload?["errorCode"] as? NSNumber)?.intValue,
           payloadCode != 0 {
            return true
        }
        return false
    }

    private func errorMessage(from json: JSON) -> String {
        if let direct = json["error"] as? String, !direct.isEmpty {
            return direct
        }

        if let payload = json["payload"] as? JSON {
            let payloadErrorText =
                (payload["errorText"] as? String) ??
                (payload["message"] as? String) ??
                (payload["errorDescription"] as? String) ??
                (payload["reason"] as? String)

            let payloadErrorCode =
                (payload["errorCode"] as? Int) ??
                (payload["errorCode"] as? NSNumber)?.intValue

            if let payloadErrorText, !payloadErrorText.isEmpty, let payloadErrorCode {
                return "\(payloadErrorCode) \(payloadErrorText)"
            }

            if let payloadErrorText, !payloadErrorText.isEmpty {
                return payloadErrorText
            }

            if let payloadErrorCode {
                return "\(payloadErrorCode) unsupported request"
            }
        }

        if let topLevelCode = (json["errorCode"] as? Int) ?? (json["errorCode"] as? NSNumber)?.intValue {
            return "\(topLevelCode) unsupported request"
        }

        return "TV rejected the request."
    }

    private func shouldFallbackToPointerButton(after error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("404")
            || message.contains("not found")
            || message.contains("no such service")
            || message.contains("no such method")
            || message.contains("networkinput")
            || message.contains("unsupported")
            || message.contains("unknown uri")
    }

    private func normalizeHost(_ rawHost: String) -> String {
        let trimmed = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host
        }

        if let slash = trimmed.firstIndex(of: "/") {
            return String(trimmed[..<slash])
        }

        if let colon = trimmed.lastIndex(of: ":"), !trimmed.contains("]") {
            let maybeHost = String(trimmed[..<colon])
            if !maybeHost.isEmpty {
                return maybeHost
            }
        }

        return trimmed
    }

    private static func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let clamped = max(seconds, 0.2)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
                throw PulseWidgetIntentError.requestTimedOut
            }

            guard let first = try await group.next() else {
                throw PulseWidgetIntentError.requestTimedOut
            }
            group.cancelAll()
            return first
        }
    }
}
