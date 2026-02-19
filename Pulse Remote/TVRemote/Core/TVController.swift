import Foundation

enum TVControllerError: LocalizedError {
    case invalidAddress
    case invalidWakeMACAddress
    case localNetworkPermissionDenied
    case noDeviceSelected
    case notConnected
    case commandUnsupported
    case networkFailure(String)
    case pairingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Enter a valid TV IP address."
        case .invalidWakeMACAddress:
            return "Enter a valid TV MAC address (for example AA:BB:CC:DD:EE:FF)."
        case .localNetworkPermissionDenied:
            return "Local Network access is required to find your TV."
        case .noDeviceSelected:
            return "Select a TV to connect first."
        case .notConnected:
            return "TV is not connected."
        case .commandUnsupported:
            return "That command is not supported by this TV."
        case let .networkFailure(message):
            return message
        case let .pairingFailed(message):
            return message
        }
    }
}

@MainActor
protocol TVController: AnyObject {
    var onDevicesChanged: (([TVDevice]) -> Void)? { get set }
    var onKnownDevicesChanged: (([TVDevice]) -> Void)? { get set }
    var onStateChanged: ((TVConnectionState) -> Void)? { get set }

    var currentDevice: TVDevice? { get }
    var knownDevices: [TVDevice] { get }

    func startDiscovery()
    func stopDiscovery()

    func connect(to device: TVDevice, asReconnection: Bool) async throws
    func connectUsingManualIP(_ ip: String) async throws
    func pair() async throws

    func disconnect()
    func send(command: TVCommand) async throws
    func fetchLaunchApps() async -> [TVAppShortcut]
    func fetchInputSources() async -> [TVInputSource]
    func fetchVolumeState() async -> TVVolumeState?
    func fetchNowPlayingState() async -> TVNowPlayingState?
    func ping() async -> Bool
    func diagnosticsSnapshot() -> TVDiagnosticsSnapshot
    func reconnectToLastDeviceIfPossible() async
    func updateWakeMACAddress(_ macAddress: String?, for deviceID: String?) throws
    func plexMetadataConfiguration() -> TVPlexMetadataConfiguration
    func updatePlexMetadataConfiguration(serverURL: String, token: String) throws
}
