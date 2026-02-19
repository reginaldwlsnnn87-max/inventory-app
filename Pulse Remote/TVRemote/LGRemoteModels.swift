import Foundation

struct LGRemoteLaunchTarget: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let appID: String

    static let defaults: [LGRemoteLaunchTarget] = [
        LGRemoteLaunchTarget(id: "netflix", title: "Netflix", icon: "tv", appID: "netflix"),
        LGRemoteLaunchTarget(id: "youtube", title: "YouTube", icon: "play.rectangle.fill", appID: "youtube.leanback.v4"),
        LGRemoteLaunchTarget(id: "browser", title: "Browser", icon: "safari.fill", appID: "com.webos.app.browser"),
        LGRemoteLaunchTarget(id: "gallery", title: "Gallery", icon: "photo.on.rectangle", appID: "com.webos.app.gallery")
    ]
}

enum LGConnectionState: Equatable {
    case disconnected
    case connecting
    case waitingForPairing
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .waitingForPairing:
            return "Approve on TV"
        case .connected:
            return "Connected"
        case .failed:
            return "Connection Failed"
        }
    }

    var subtitle: String {
        switch self {
        case .disconnected:
            return "Enter your LG TV IP address to start."
        case .connecting:
            return "Opening encrypted session with your TV."
        case .waitingForPairing:
            return "Accept the pairing prompt on your LG TV."
        case .connected:
            return "Your remote is ready."
        case let .failed(message):
            return message
        }
    }
}

enum LGRemoteAction {
    case up
    case down
    case left
    case right
    case ok
    case back
    case home
    case settings
    case volumeUp
    case volumeDown
    case mute(Bool)
    case channelUp
    case channelDown
    case play
    case pause
    case stop
    case rewind
    case fastForward
    case powerOff
    case launchApp(String)
}

