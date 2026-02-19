import Foundation

enum LGWebOSClientError: LocalizedError {
    case invalidHost
    case notConnected
    case handshakeFailed(String)
    case requestTimedOut
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "The TV address is invalid. Try an IP like 192.168.1.47."
        case .notConnected:
            return "Connect to your LG TV first."
        case let .handshakeFailed(reason):
            return reason
        case .requestTimedOut:
            return "The TV took too long to respond."
        case .invalidResponse:
            return "Received an invalid response from the TV."
        }
    }
}

@MainActor
final class LGWebOSClient {
    typealias JSON = [String: Any]

    var onPairingPrompt: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?

    private let session: URLSession
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var nextRequestNumber = 1
    private var pendingResponses: [String: CheckedContinuation<JSON, Error>] = [:]
    private var registerRequestID: String?
    private var registerContinuation: CheckedContinuation<String, Error>?
    private var hasAnnouncedPairingPrompt = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(host rawHost: String, savedClientKey: String?) async throws -> String {
        disconnect(reason: nil)

        guard let url = websocketURL(from: rawHost) else {
            throw LGWebOSClientError.invalidHost
        }

        let task = session.webSocketTask(with: url)
        socketTask = task
        task.resume()
        beginReceiveLoop()

        let requestID = nextID(prefix: "register")
        registerRequestID = requestID
        hasAnnouncedPairingPrompt = false

        try send(
            dictionary: registerEnvelope(requestID: requestID, clientKey: savedClientKey)
        )

        return try await waitForRegistration(timeout: 35)
    }

    func disconnect(reason: String? = nil) {
        receiveTask?.cancel()
        receiveTask = nil

        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil

        if let continuation = registerContinuation {
            registerContinuation = nil
            continuation.resume(
                throwing: LGWebOSClientError.handshakeFailed(
                    reason ?? "Connection was interrupted during pairing."
                )
            )
        }

        failPendingRequests(with: LGWebOSClientError.notConnected)

        if let reason {
            onDisconnected?(reason)
        }
    }

    func perform(action: LGRemoteAction) async throws {
        switch action {
        case .up:
            _ = try await sendButton("UP")
        case .down:
            _ = try await sendButton("DOWN")
        case .left:
            _ = try await sendButton("LEFT")
        case .right:
            _ = try await sendButton("RIGHT")
        case .ok:
            _ = try await sendButton("ENTER")
        case .back:
            _ = try await sendButton("BACK")
        case .home:
            _ = try await sendButton("HOME")
        case .settings:
            _ = try await sendButton("MENU")
        case .volumeUp:
            _ = try await request(uri: "ssap://audio/volumeUp")
        case .volumeDown:
            _ = try await request(uri: "ssap://audio/volumeDown")
        case let .mute(muted):
            _ = try await request(
                uri: "ssap://audio/setMute",
                payload: ["mute": muted]
            )
        case .channelUp:
            _ = try await request(uri: "ssap://tv/channelUp")
        case .channelDown:
            _ = try await request(uri: "ssap://tv/channelDown")
        case .play:
            _ = try await sendButton("PLAY")
        case .pause:
            _ = try await sendButton("PAUSE")
        case .stop:
            _ = try await sendButton("STOP")
        case .rewind:
            _ = try await sendButton("REWIND")
        case .fastForward:
            _ = try await sendButton("FASTFORWARD")
        case .powerOff:
            _ = try await request(uri: "ssap://system/turnOff")
        case let .launchApp(appID):
            _ = try await request(
                uri: "ssap://system.launcher/launch",
                payload: ["id": appID]
            )
        }
    }

    private func sendButton(_ name: String) async throws -> JSON {
        try await request(
            uri: "ssap://com.webos.service.networkinput/sendButton",
            payload: ["name": name]
        )
    }

    private func request(uri: String, payload: JSON? = nil) async throws -> JSON {
        guard socketTask != nil else {
            throw LGWebOSClientError.notConnected
        }

        let requestID = nextID(prefix: "req")
        var message: JSON = [
            "id": requestID,
            "type": "request",
            "uri": uri
        ]
        if let payload {
            message["payload"] = payload
        }

        try send(dictionary: message)
        return try await waitForResponse(withID: requestID, timeout: 12)
    }

    private func beginReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let socketTask = self.socketTask {
                do {
                    let message = try await socketTask.receive()
                    try self.handleIncoming(message: message)
                } catch {
                    self.failPendingRequests(with: LGWebOSClientError.notConnected)
                    self.finishRegistration(
                        with: .failure(
                            LGWebOSClientError.handshakeFailed(
                                "Could not complete LG TV pairing."
                            )
                        )
                    )
                    self.socketTask = nil
                    self.onDisconnected?(error.localizedDescription)
                    return
                }
            }
        }
    }

    private func handleIncoming(message: URLSessionWebSocketTask.Message) throws {
        let data: Data
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(binaryData):
            data = binaryData
        @unknown default:
            return
        }

        guard
            let object = try JSONSerialization.jsonObject(with: data) as? JSON
        else {
            throw LGWebOSClientError.invalidResponse
        }

        let type = object["type"] as? String ?? ""
        let id = object["id"] as? String

        if type == "registered" {
            let payload = object["payload"] as? JSON
            let clientKey = payload?["client-key"] as? String ?? ""
            finishRegistration(with: .success(clientKey))
        }

        if id == registerRequestID, type == "response" {
            let payload = object["payload"] as? JSON
            let pairingType = payload?["pairingType"] as? String
            if pairingType?.uppercased() == "PROMPT", !hasAnnouncedPairingPrompt {
                hasAnnouncedPairingPrompt = true
                onPairingPrompt?()
            }
        }

        if type == "error" {
            let message = responseErrorMessage(from: object)
            if id == registerRequestID {
                finishRegistration(with: .failure(LGWebOSClientError.handshakeFailed(message)))
            } else if let id, let continuation = pendingResponses.removeValue(forKey: id) {
                continuation.resume(throwing: LGWebOSClientError.handshakeFailed(message))
            }
            return
        }

        if let id, let continuation = pendingResponses.removeValue(forKey: id) {
            continuation.resume(returning: object)
        }
    }

    private func responseErrorMessage(from object: JSON) -> String {
        if let errorString = object["error"] as? String, !errorString.isEmpty {
            return errorString
        }

        if
            let payload = object["payload"] as? JSON,
            let message = payload["errorText"] as? String,
            !message.isEmpty
        {
            return message
        }

        return "LG TV rejected the request."
    }

    private func waitForRegistration(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            registerContinuation = continuation
            scheduleTimeout(after: timeout) { [weak self] in
                guard let self, let pending = self.registerContinuation else { return }
                self.registerContinuation = nil
                pending.resume(throwing: LGWebOSClientError.requestTimedOut)
            }
        }
    }

    private func waitForResponse(withID id: String, timeout: TimeInterval) async throws -> JSON {
        try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
            scheduleTimeout(after: timeout) { [weak self] in
                guard let self, let pending = self.pendingResponses.removeValue(forKey: id) else { return }
                pending.resume(throwing: LGWebOSClientError.requestTimedOut)
            }
        }
    }

    private func finishRegistration(with result: Result<String, Error>) {
        guard let continuation = registerContinuation else { return }
        registerContinuation = nil
        continuation.resume(with: result)
    }

    private func failPendingRequests(with error: Error) {
        let continuations = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func send(dictionary: JSON) throws {
        guard let socketTask else {
            throw LGWebOSClientError.notConnected
        }

        let data = try JSONSerialization.data(withJSONObject: dictionary)
        guard let message = String(data: data, encoding: .utf8) else {
            throw LGWebOSClientError.invalidResponse
        }

        socketTask.send(.string(message)) { [weak self] error in
            guard let self, let error else { return }
            Task { @MainActor in
                self.failPendingRequests(with: error)
                self.finishRegistration(with: .failure(error))
                self.onDisconnected?(error.localizedDescription)
            }
        }
    }

    private func scheduleTimeout(after timeout: TimeInterval, _ closure: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            closure()
        }
    }

    private func nextID(prefix: String) -> String {
        defer { nextRequestNumber += 1 }
        return "\(prefix)_\(nextRequestNumber)"
    }

    private func websocketURL(from rawHost: String) -> URL? {
        let trimmed = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("ws://") || trimmed.hasPrefix("wss://") {
            return URL(string: trimmed)
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard var components = URLComponents(string: trimmed), let host = components.host else {
                return nil
            }
            components.scheme = components.scheme == "https" ? "wss" : "ws"
            components.host = host
            components.path = ""
            components.query = nil
            if components.port == nil {
                components.port = components.scheme == "wss" ? 3001 : 3000
            }
            return components.url
        }

        var host = trimmed
        var port = 3000
        if
            let colon = trimmed.lastIndex(of: ":"),
            let parsedPort = Int(trimmed[trimmed.index(after: colon)...]),
            !trimmed.contains("]")
        {
            host = String(trimmed[..<colon])
            port = parsedPort
        }

        var components = URLComponents()
        components.scheme = "ws"
        components.host = host
        components.port = port
        return components.url
    }

    private func registerEnvelope(requestID: String, clientKey: String?) -> JSON {
        let permissions = [
            "LAUNCH",
            "LAUNCH_WEBAPP",
            "APP_TO_APP",
            "CONTROL_AUDIO",
            "CONTROL_POWER",
            "READ_RUNNING_APPS",
            "READ_INPUT_DEVICE_LIST",
            "READ_CURRENT_CHANNEL",
            "CONTROL_INPUT_JOYSTICK",
            "CONTROL_INPUT_MEDIA_PLAYBACK",
            "CONTROL_INPUT_MEDIA_RECORDING",
            "CONTROL_INPUT_TEXT",
            "CONTROL_MOUSE_AND_KEYBOARD",
            "READ_INSTALLED_APPS",
            "WRITE_NOTIFICATION_TOAST"
        ]

        var payload: JSON = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "1.0",
                "permissions": permissions,
                "signed": [
                    "appId": "com.reggieboi.pulseremote",
                    "created": "2026-02-14",
                    "localizedAppNames": ["": AppBranding.displayName],
                    "localizedVendorNames": ["": "Pulse Remote"],
                    "permissions": permissions,
                    "serial": "3f6adf2cb8f77f0c0f67be72f6e8f0bd",
                    "vendorId": "com.reggieboi"
                ]
            ]
        ]

        if let clientKey, !clientKey.isEmpty {
            payload["client-key"] = clientKey
        }

        return [
            "id": requestID,
            "type": "register",
            "payload": payload
        ]
    }
}
