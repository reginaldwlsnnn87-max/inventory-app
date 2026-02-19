import Foundation

enum LGWebOSSocketError: LocalizedError {
    case invalidAddress
    case notConnected
    case requestTimedOut
    case invalidResponse
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Could not build a valid webOS socket URL."
        case .notConnected:
            return "Socket is not connected to a TV."
        case .requestTimedOut:
            return "TV did not respond in time."
        case .invalidResponse:
            return "TV returned an unexpected response."
        case let .registrationFailed(message):
            return message
        }
    }
}

@MainActor
final class LGWebOSSocketClient {
    typealias JSON = [String: Any]

    private struct PendingResponse {
        let continuation: CheckedContinuation<JSON, Error>
        var timeoutTask: Task<Void, Never>?
    }

    var onPairingPrompt: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?

    private let session: URLSession
    private var socketTask: URLSessionWebSocketTask?
    private var pointerSocketTask: URLSessionWebSocketTask?
    private var pointerSocketPath: String?
    private var receiveTask: Task<Void, Never>?
    private var nextRequestNumber = 0

    private var registerRequestID: String?
    private var registerContinuation: CheckedContinuation<String, Error>?
    private var registerTimeoutTask: Task<Void, Never>?
    private var hasAnnouncedPairingPrompt = false
    private var pendingResponses: [String: PendingResponse] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(host: String, port: Int = 3000, secure: Bool = false) throws {
        disconnect(emitEvent: false)

        var components = URLComponents()
        components.scheme = secure ? "wss" : "ws"
        components.host = normalizedHost(host)
        components.port = port
        guard let url = components.url else {
            throw LGWebOSSocketError.invalidAddress
        }

        let task = session.webSocketTask(with: url)
        socketTask = task
        task.resume()
        startReceiveLoop(for: task)
    }

    func register(existingClientKey: String?, timeout: TimeInterval = 30) async throws -> String {
        guard socketTask != nil else {
            throw LGWebOSSocketError.notConnected
        }

        let requestID = nextRequestID(prefix: "register")
        registerRequestID = requestID
        registerTimeoutTask?.cancel()
        hasAnnouncedPairingPrompt = false

        let envelope = registerPayload(requestID: requestID, existingClientKey: existingClientKey)
        let clampedTimeout = min(max(timeout, 1.2), 45)
        return try await withCheckedThrowingContinuation { continuation in
            registerContinuation = continuation
            registerTimeoutTask = Task { @MainActor [weak self] in
                let timeoutNanoseconds = UInt64(clampedTimeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard let self, let pending = self.registerContinuation else { return }
                self.registerContinuation = nil
                self.registerTimeoutTask = nil
                pending.resume(throwing: LGWebOSSocketError.requestTimedOut)
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.resume(throwing: LGWebOSSocketError.notConnected)
                    return
                }
                do {
                    try await self.send(dictionary: envelope)
                } catch {
                    self.completeRegistration(with: .failure(error))
                }
            }
        }
    }

    func prewarmPointerSocket() async throws {
        try await ensurePointerSocketConnected()
    }

    func sendPing(timeout: TimeInterval = 1.0) async -> Bool {
        guard let socketTask else { return false }
        let clampedTimeout = min(max(timeout, 0.35), 4.0)

        return await withCheckedContinuation { continuation in
            let completionGate = LGPingCompletionGate()
            let finish: (Bool) -> Void = { success in
                guard completionGate.tryComplete() else { return }
                continuation.resume(returning: success)
            }

            socketTask.sendPing { error in
                Task { @MainActor in
                    finish(error == nil)
                }
            }

            Task { @MainActor in
                let timeoutNanoseconds = UInt64(clampedTimeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                finish(false)
            }
        }
    }

    func request(
        uri: String,
        payload: JSON? = nil,
        timeout: TimeInterval = 12
    ) async throws -> JSON {
        guard socketTask != nil else {
            throw LGWebOSSocketError.notConnected
        }

        let requestID = nextRequestID(prefix: "req")
        var body: JSON = [
            "id": requestID,
            "type": "request",
            "uri": uri
        ]
        if let payload {
            body["payload"] = payload
        }
        let envelope = body

        let clampedTimeout = min(max(timeout, 0.8), 20)

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { @MainActor [weak self] in
                let timeoutNanoseconds = UInt64(clampedTimeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard let self else { return }
                self.completePendingResponse(
                    for: requestID,
                    with: .failure(LGWebOSSocketError.requestTimedOut)
                )
            }

            pendingResponses[requestID] = PendingResponse(
                continuation: continuation,
                timeoutTask: timeoutTask
            )

            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.resume(throwing: LGWebOSSocketError.notConnected)
                    return
                }
                do {
                    try await self.send(dictionary: envelope)
                } catch {
                    self.completePendingResponse(for: requestID, with: .failure(error))
                }
            }
        }
    }

    func sendPointerButton(_ name: String) async throws {
        let payload = "type:button\nname:\(name)\n\n"

        do {
            try await ensurePointerSocketConnected()
            try await sendPointerMessage(payload)
        } catch {
            // Pointer socket endpoints can expire. Recreate once and retry.
            pointerSocketTask?.cancel(with: .goingAway, reason: nil)
            pointerSocketTask = nil
            pointerSocketPath = nil
            try await ensurePointerSocketConnected()
            try await sendPointerMessage(payload)
        }
    }

    func disconnect(emitEvent: Bool = true, reason: String? = nil) {
        receiveTask?.cancel()
        receiveTask = nil

        pointerSocketTask?.cancel(with: .goingAway, reason: nil)
        pointerSocketTask = nil
        pointerSocketPath = nil

        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil

        if let pendingRegister = registerContinuation {
            registerContinuation = nil
            registerTimeoutTask?.cancel()
            registerTimeoutTask = nil
            pendingRegister.resume(
                throwing: LGWebOSSocketError.registrationFailed(
                    reason ?? "Pairing ended before completion."
                )
            )
        }
        registerRequestID = nil
        hasAnnouncedPairingPrompt = false

        let pending = pendingResponses.values
        pendingResponses.removeAll()
        for var pendingResponse in pending {
            pendingResponse.timeoutTask?.cancel()
            pendingResponse.timeoutTask = nil
            pendingResponse.continuation.resume(throwing: LGWebOSSocketError.notConnected)
        }

        if emitEvent {
            onDisconnected?(reason)
        }
    }

    private func send(dictionary: JSON) async throws {
        guard let socketTask else {
            throw LGWebOSSocketError.notConnected
        }

        let data = try JSONSerialization.data(withJSONObject: dictionary)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LGWebOSSocketError.invalidResponse
        }

        try await socketTask.send(.string(text))
    }

    private func ensurePointerSocketConnected() async throws {
        guard socketTask != nil else {
            throw LGWebOSSocketError.notConnected
        }

        if pointerSocketTask == nil {
            let response = try await request(uri: "ssap://com.webos.service.networkinput/getPointerInputSocket")
            guard
                let payload = response["payload"] as? JSON,
                let socketPath = payload["socketPath"] as? String,
                !socketPath.isEmpty,
                let pointerURL = URL(string: socketPath)
            else {
                throw LGWebOSSocketError.invalidResponse
            }

            let task = session.webSocketTask(with: pointerURL)
            pointerSocketTask = task
            pointerSocketPath = socketPath
            task.resume()
        }
    }

    private func sendPointerMessage(_ message: String) async throws {
        guard let pointerSocketTask else {
            throw LGWebOSSocketError.notConnected
        }
        try await pointerSocketTask.send(.string(message))
    }

    private func startReceiveLoop(for task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    try self.processIncoming(message)
                } catch {
                    // Ignore stale receive loops from previously cancelled sockets.
                    guard self.socketTask === task else { return }

                    if Self.isCancellation(error) || Task.isCancelled {
                        self.disconnect(emitEvent: false)
                    } else {
                        self.disconnect(emitEvent: true, reason: error.localizedDescription)
                    }
                    return
                }
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        let text = error.localizedDescription.lowercased()
        return text.contains("cancelled") || text.contains("canceled")
    }

    private func processIncoming(_ message: URLSessionWebSocketTask.Message) throws {
        let data: Data
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(binary):
            data = binary
        @unknown default:
            return
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? JSON else {
            throw LGWebOSSocketError.invalidResponse
        }

        let id = json["id"] as? String
        let type = json["type"] as? String ?? ""

        if id == registerRequestID, type == "response" {
            if let payload = json["payload"] as? JSON,
               let pairingType = payload["pairingType"] as? String,
               pairingType.uppercased() == "PROMPT",
               !hasAnnouncedPairingPrompt {
                hasAnnouncedPairingPrompt = true
                onPairingPrompt?()
            }
        }

        if type == "registered" {
            let payload = json["payload"] as? JSON
            let clientKey = payload?["client-key"] as? String ?? ""
            completeRegistration(with: .success(clientKey))
            return
        }

        if type == "error" {
            let message = errorMessage(from: json)
            if id == registerRequestID {
                completeRegistration(with: .failure(LGWebOSSocketError.registrationFailed(message)))
                return
            }

            if let id {
                completePendingResponse(
                    for: id,
                    with: .failure(LGWebOSSocketError.registrationFailed(message))
                )
            }
            return
        }

        if let id {
            if type == "response", responseIndicatesFailure(json) {
                completePendingResponse(
                    for: id,
                    with: .failure(LGWebOSSocketError.registrationFailed(errorMessage(from: json)))
                )
                return
            }
            completePendingResponse(for: id, with: .success(json))
        }
    }

    private func completePendingResponse(for requestID: String, with result: Result<JSON, Error>) {
        guard var pending = pendingResponses.removeValue(forKey: requestID) else { return }
        pending.timeoutTask?.cancel()
        pending.timeoutTask = nil
        pending.continuation.resume(with: result)
    }

    private func completeRegistration(with result: Result<String, Error>) {
        guard let continuation = registerContinuation else { return }
        registerContinuation = nil
        registerTimeoutTask?.cancel()
        registerTimeoutTask = nil
        continuation.resume(with: result)
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

    private func nextRequestID(prefix: String) -> String {
        defer { nextRequestNumber += 1 }
        return "\(prefix)_\(nextRequestNumber)"
    }

    private func normalizedHost(_ rawHost: String) -> String {
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

    private func registerPayload(requestID: String, existingClientKey: String?) -> JSON {
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

        var payload: JSON = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "1.0",
                "permissions": permissions,
                // NOTE: webOS accepts an unsigned manifest for local development use.
                // Verify manifest signing requirements for production App Store release.
                "signed": [
                    "appId": "com.reggieboi.pulseremote",
                    "created": "2026-02-14",
                    "localizedAppNames": ["": AppBranding.displayName],
                    "localizedVendorNames": ["": "Pulse Remote"],
                    "permissions": permissions,
                    "serial": "2c2b0baf2cf24dc7916efbf72ecf1775",
                    "vendorId": "com.reggieboi"
                ]
            ]
        ]

        if let existingClientKey, !existingClientKey.isEmpty {
            payload["client-key"] = existingClientKey
        }

        return [
            "id": requestID,
            "type": "register",
            "payload": payload
        ]
    }
}

private final class LGPingCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasCompleted = false

    func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasCompleted else { return false }
        hasCompleted = true
        return true
    }
}
