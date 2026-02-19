import Foundation
import Combine

@MainActor
final class LGRemoteViewModel: ObservableObject {
    @Published var tvAddress: String
    @Published private(set) var connectionState: LGConnectionState = .disconnected
    @Published private(set) var isMuted = false
    @Published private(set) var isBusy = false
    @Published private(set) var commandFeedback: String?

    let launchTargets: [LGRemoteLaunchTarget] = LGRemoteLaunchTarget.defaults

    private let credentialStore = LGClientKeyStore()
    private let client = LGWebOSClient()

    init() {
        tvAddress = credentialStore.lastAddress ?? ""
        bindClientCallbacks()
    }

    var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    var connectButtonTitle: String {
        isConnected ? "Disconnect" : "Connect TV"
    }

    func connectOrDisconnect() {
        if isConnected {
            client.disconnect(reason: "TV disconnected.")
            connectionState = .disconnected
            return
        }

        Task {
            await connect()
        }
    }

    func send(_ action: LGRemoteAction) {
        guard isConnected else { return }

        commandFeedback = nil
        Haptics.tap()

        Task {
            do {
                try await client.perform(action: action)
                if case let .mute(muteState) = action {
                    isMuted = muteState
                }
            } catch {
                commandFeedback = error.userFacingMessage
            }
        }
    }

    func toggleMute() {
        send(.mute(!isMuted))
    }

    func launch(_ target: LGRemoteLaunchTarget) {
        send(.launchApp(target.appID))
    }

    private func connect() async {
        let trimmed = tvAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            connectionState = .failed("Enter your LG TV IP address.")
            return
        }

        connectionState = .connecting
        isBusy = true
        commandFeedback = nil

        do {
            let existingClientKey = credentialStore.clientKey(for: trimmed)
            let newClientKey = try await client.connect(host: trimmed, savedClientKey: existingClientKey)
            credentialStore.save(address: trimmed, clientKey: newClientKey)
            connectionState = .connected
            Haptics.success()
        } catch {
            connectionState = .failed(error.userFacingMessage)
        }

        isBusy = false
    }

    private func bindClientCallbacks() {
        client.onPairingPrompt = { [weak self] in
            self?.connectionState = .waitingForPairing
        }

        client.onDisconnected = { [weak self] reason in
            guard let self else { return }
            if case .connecting = self.connectionState {
                self.connectionState = .failed(reason ?? "Could not reach your LG TV.")
                return
            }
            if case .waitingForPairing = self.connectionState {
                self.connectionState = .failed(reason ?? "Pairing was interrupted.")
                return
            }
            self.connectionState = .disconnected
        }
    }
}

private struct LGClientKeyStore {
    private let keyMappingStorageKey = "lg.remote.clientKey.mapping"
    private let lastAddressStorageKey = "lg.remote.lastAddress"
    private let defaults: UserDefaults = .standard

    var lastAddress: String? {
        defaults.string(forKey: lastAddressStorageKey)
    }

    func clientKey(for address: String) -> String? {
        let key = normalizedAddress(address)
        guard
            let mapping = defaults.dictionary(forKey: keyMappingStorageKey) as? [String: String]
        else {
            return nil
        }
        return mapping[key]
    }

    func save(address: String, clientKey: String) {
        let key = normalizedAddress(address)
        guard !key.isEmpty else { return }

        var mapping = defaults.dictionary(forKey: keyMappingStorageKey) as? [String: String] ?? [:]
        mapping[key] = clientKey
        defaults.set(mapping, forKey: keyMappingStorageKey)
        defaults.set(address, forKey: lastAddressStorageKey)
    }

    private func normalizedAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return ""
        }

        let withoutScheme: String
        if let range = trimmed.range(of: "://") {
            withoutScheme = String(trimmed[range.upperBound...])
        } else {
            withoutScheme = trimmed
        }

        let withoutPath = withoutScheme.split(separator: "/").first.map(String.init) ?? withoutScheme
        if
            let colon = withoutPath.lastIndex(of: ":"),
            !withoutPath.contains("]")
        {
            return String(withoutPath[..<colon])
        }
        return withoutPath
    }
}

private extension Error {
    var userFacingMessage: String {
        if let localized = self as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return localizedDescription
    }
}
