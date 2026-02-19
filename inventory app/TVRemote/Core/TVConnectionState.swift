import Foundation

enum TVConnectionState: Equatable {
    case idle
    case scanning
    case discovered(count: Int)
    case pairing(device: TVDevice)
    case connected(device: TVDevice)
    case reconnecting(device: TVDevice)
    case failed(message: String)

    var shortLabel: String {
        switch self {
        case .idle:
            return "Idle"
        case .scanning:
            return "Scanning"
        case let .discovered(count):
            return count == 1 ? "1 TV Found" : "\(count) TVs Found"
        case .pairing:
            return "Pairing"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .failed:
            return "Failed"
        }
    }

    var detailCopy: String {
        switch self {
        case .idle:
            return "Ready to scan for nearby TVs."
        case .scanning:
            return "Searching your local network."
        case let .discovered(count):
            return count == 0 ? "No TVs found yet." : "Select a TV to connect."
        case .pairing:
            return "Approve pairing on your LG TV."
        case .connected:
            return "Remote commands are live."
        case .reconnecting:
            return "Trying to restore your TV connection."
        case let .failed(message):
            return message
        }
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

enum TVConnectionEvent {
    case beginScan
    case foundDevices(Int)
    case beginPairing(TVDevice)
    case didConnect(TVDevice)
    case beginReconnect(TVDevice)
    case fail(String)
    case disconnect
}

struct TVConnectionStateMachine {
    private(set) var state: TVConnectionState = .idle

    mutating func transition(_ event: TVConnectionEvent) -> TVConnectionState {
        switch event {
        case .beginScan:
            state = .scanning
        case let .foundDevices(count):
            state = .discovered(count: count)
        case let .beginPairing(device):
            state = .pairing(device: device)
        case let .didConnect(device):
            state = .connected(device: device)
        case let .beginReconnect(device):
            state = .reconnecting(device: device)
        case let .fail(message):
            state = .failed(message: message)
        case .disconnect:
            state = .idle
        }

        return state
    }
}

