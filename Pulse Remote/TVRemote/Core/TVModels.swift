import Foundation

enum TVCapability: String, CaseIterable, Codable, Hashable {
    case power
    case volume
    case dpad
    case home
    case back
    case mute
    case launchApp
    case inputSwitch
    case nowPlaying
    case keyboard
}

struct TVDevice: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var ip: String
    var manufacturer: String
    var model: String?
    var capabilities: Set<TVCapability>
    var port: Int
    var lastConnectedAt: Date?
    var wakeMACAddress: String?

    init(
        id: String,
        name: String,
        ip: String,
        manufacturer: String,
        model: String? = nil,
        capabilities: Set<TVCapability>,
        port: Int = 3000,
        lastConnectedAt: Date? = nil,
        wakeMACAddress: String? = nil
    ) {
        self.id = id
        self.name = name
        self.ip = ip
        self.manufacturer = manufacturer
        self.model = model
        self.capabilities = capabilities
        self.port = port
        self.lastConnectedAt = lastConnectedAt
        self.wakeMACAddress = wakeMACAddress
    }
}

extension TVDevice {
    static func manualLG(ip: String, port: Int = 3000) -> TVDevice {
        TVDevice(
            id: "lg-\(ip.lowercased())",
            name: "LG webOS TV",
            ip: ip,
            manufacturer: "LG",
            model: nil,
            capabilities: Set(TVCapability.allCases),
            port: port
        )
    }
}

enum TVCommand: Equatable {
    case up
    case down
    case left
    case right
    case select
    case back
    case home
    case menu
    case volumeUp
    case volumeDown
    case setVolume(Int)
    case mute(Bool?)
    case powerOff
    case powerOn
    case launchApp(String)
    case inputSwitch(String)
    case keyboardText(String)
}

struct TVAppShortcut: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let iconSystemName: String
    let appID: String
    let iconURLString: String?
    let brandColorHex: String?

    init(
        id: String,
        title: String,
        iconSystemName: String,
        appID: String,
        iconURLString: String? = nil,
        brandColorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.appID = appID
        self.iconURLString = iconURLString
        self.brandColorHex = brandColorHex
    }
}

extension TVAppShortcut {
    static let lgDefaults: [TVAppShortcut] = [
        TVAppShortcut(id: "youtube-tv", title: "YouTube TV", iconSystemName: "tv.badge.wifi", appID: "youtube.leanback.ytv.v1", brandColorHex: "#EA4335"),
        TVAppShortcut(id: "youtube", title: "YouTube", iconSystemName: "play.tv.fill", appID: "youtube.leanback.v4", brandColorHex: "#FF0000"),
        TVAppShortcut(id: "netflix", title: "Netflix", iconSystemName: "film.stack.fill", appID: "netflix", brandColorHex: "#E50914"),
        TVAppShortcut(id: "prime-video", title: "Prime Video", iconSystemName: "sparkles.tv.fill", appID: "amazon", brandColorHex: "#00A8E1"),
        TVAppShortcut(id: "disney-plus", title: "Disney+", iconSystemName: "star.circle.fill", appID: "com.disney.disneyplus-prod", brandColorHex: "#113CCF"),
        TVAppShortcut(id: "browser", title: "Browser", iconSystemName: "safari.fill", appID: "com.webos.app.browser"),
        TVAppShortcut(id: "gallery", title: "Gallery", iconSystemName: "photo.on.rectangle.angled", appID: "com.webos.app.gallery")
    ]

    var iconURL: URL? {
        guard let iconURLString else { return nil }
        return URL(string: iconURLString)
    }

    var iconAssetName: String? {
        switch brandIdentity {
        case .youtubeTV:
            return "TVApp.youtubeTV"
        case .youtube:
            return "TVApp.youtube"
        case .netflix:
            return "TVApp.netflix"
        case .primeVideo:
            return "TVApp.primeVideo"
        case .disneyPlus:
            return "TVApp.disneyPlus"
        case .appleTV:
            return "TVApp.appleTV"
        case .plex:
            return "TVApp.plex"
        case .none:
            return nil
        }
    }

    var brandIdentity: TVAppBrandIdentity? {
        let value = "\(title) \(appID)".lowercased()
        if value.contains("youtube tv") {
            return .youtubeTV
        }
        if value.contains("youtube") {
            return .youtube
        }
        if value.contains("netflix") {
            return .netflix
        }
        if value.contains("prime") || value.contains("amazon") {
            return .primeVideo
        }
        if value.contains("disney") {
            return .disneyPlus
        }
        if value.contains("apple tv") {
            return .appleTV
        }
        if value.contains("plex") {
            return .plex
        }
        return nil
    }
}

enum TVAppBrandIdentity {
    case youtubeTV
    case youtube
    case netflix
    case primeVideo
    case disneyPlus
    case appleTV
    case plex
}

struct TVInputSource: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let iconSystemName: String
    let inputID: String
}

struct TVVolumeState: Equatable {
    let level: Int
    let isMuted: Bool
}

enum TVNowPlayingSource: String, Codable, Equatable {
    case app
    case media
    case liveTV

    var label: String {
        switch self {
        case .app:
            return "App"
        case .media:
            return "Media"
        case .liveTV:
            return "Live TV"
        }
    }
}

enum TVNowPlayingConfidence: String, Codable, Equatable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high:
            return "High Confidence"
        case .medium:
            return "Medium Confidence"
        case .low:
            return "Low Confidence"
        }
    }

    var shortLabel: String {
        switch self {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .low:
            return "Low"
        }
    }
}

struct TVNowPlayingState: Equatable {
    let appName: String
    let appID: String?
    let title: String?
    let subtitle: String?
    let source: TVNowPlayingSource
    let confidence: TVNowPlayingConfidence
    let metadataRestrictionReason: String?

    var isProviderMetadataRestricted: Bool {
        metadataRestrictionReason != nil
    }

    init(
        appName: String,
        appID: String?,
        title: String?,
        subtitle: String?,
        source: TVNowPlayingSource,
        confidence: TVNowPlayingConfidence,
        metadataRestrictionReason: String? = nil
    ) {
        self.appName = appName
        self.appID = appID
        self.title = title
        self.subtitle = subtitle
        self.source = source
        self.confidence = confidence
        self.metadataRestrictionReason = metadataRestrictionReason
    }
}

struct TVPlexMetadataConfiguration: Equatable {
    let serverURL: String
    let token: String

    var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct TVWatchHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let capturedAt: Date
    let appName: String
    let title: String?
    let subtitle: String?
    let source: TVNowPlayingSource
    let confidence: TVNowPlayingConfidence

    private enum CodingKeys: String, CodingKey {
        case id
        case capturedAt
        case appName
        case title
        case subtitle
        case source
        case confidence
    }

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        appName: String,
        title: String?,
        subtitle: String?,
        source: TVNowPlayingSource,
        confidence: TVNowPlayingConfidence = .low
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.source = source
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        appName = try container.decode(String.self, forKey: .appName)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        source = try container.decode(TVNowPlayingSource.self, forKey: .source)
        confidence = try container.decodeIfPresent(TVNowPlayingConfidence.self, forKey: .confidence) ?? .low
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(appName, forKey: .appName)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encode(source, forKey: .source)
        try container.encode(confidence, forKey: .confidence)
    }
}

struct TVDiagnosticsSnapshot: Equatable {
    let timestamp: Date
    let connectionStateLabel: String
    let deviceName: String
    let deviceIP: String
    let endpointPort: Int?
    let commandTransport: String
    let reconnectAttempts: Int
    let commandRetryCount: Int
    let pingFailureCount: Int
    let lastAutoRecoveryAt: Date?
    let lastErrorCode: Int?
    let lastErrorMessage: String?
    let lastFailedCommand: String?
    let lastErrorAt: Date?
    let serviceNames: [String]
    let supportedCapabilities: [TVCapability]
    let nowPlayingProbeSummary: String?
    let commandLatencyTelemetry: TVCommandLatencyTelemetry
}

struct TVCommandLatencyTelemetry: Equatable {
    let windowSampleCount: Int
    let successfulCount: Int
    let timeoutCount: Int
    let lastCommandKey: String?
    let lastLatencyMs: Int?
    let lastWasSuccess: Bool
    let lastWasTimeout: Bool
    let averageLatencyMs: Int?
    let p50LatencyMs: Int?
    let p95LatencyMs: Int?

    var successRatePercentText: String {
        guard windowSampleCount > 0 else { return "N/A" }
        let rate = (Double(successfulCount) / Double(windowSampleCount)) * 100
        return "\(Int(rate.rounded()))%"
    }
}

enum TVReliabilityMetric: String, Codable, CaseIterable {
    case discovery
    case connection
    case command
    case fixWorkflow
    case autoReconnect
}

struct TVReliabilityMetricSummary: Equatable, Codable {
    let attempts: Int
    let successes: Int

    var failures: Int {
        max(attempts - successes, 0)
    }

    var successRate: Double? {
        guard attempts > 0 else { return nil }
        return Double(successes) / Double(attempts)
    }

    var successRatePercentText: String {
        guard let successRate else { return "N/A" }
        return "\(Int((successRate * 100).rounded()))%"
    }
}

struct TVReliabilitySnapshot: Equatable, Codable {
    let generatedAt: Date
    let windowDays: Int
    let discovery: TVReliabilityMetricSummary
    let connection: TVReliabilityMetricSummary
    let command: TVReliabilityMetricSummary
    let fixWorkflow: TVReliabilityMetricSummary
    let autoReconnect: TVReliabilityMetricSummary

    var hasAnyData: Bool {
        discovery.attempts > 0
            || connection.attempts > 0
            || command.attempts > 0
            || fixWorkflow.attempts > 0
            || autoReconnect.attempts > 0
    }

    var overallScore: Int? {
        var weightedTotal = 0.0
        var weightUsed = 0.0

        let weightedMetrics: [(TVReliabilityMetricSummary, Double)] = [
            (command, 0.45),
            (connection, 0.25),
            (discovery, 0.15),
            (fixWorkflow, 0.10),
            (autoReconnect, 0.05)
        ]

        for (summary, weight) in weightedMetrics {
            guard let rate = summary.successRate else { continue }
            weightedTotal += rate * weight
            weightUsed += weight
        }

        guard weightUsed > 0 else { return nil }
        return Int(((weightedTotal / weightUsed) * 100).rounded())
    }

    var overallLabel: String {
        guard let score = overallScore else { return "Learning" }
        switch score {
        case 97...:
            return "Excellent"
        case 92...:
            return "Strong"
        case 85...:
            return "Good"
        case 75...:
            return "Needs Tuning"
        default:
            return "Unstable"
        }
    }
}

enum TVSceneActionKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case powerOn
    case powerOff
    case home
    case back
    case muteOn
    case muteOff
    case volumeUp
    case volumeDown
    case setVolume
    case launchApp
    case switchInput

    var id: String { rawValue }

    var title: String {
        switch self {
        case .powerOn:
            return "Power On"
        case .powerOff:
            return "Power Off"
        case .home:
            return "Home"
        case .back:
            return "Back"
        case .muteOn:
            return "Mute"
        case .muteOff:
            return "Unmute"
        case .volumeUp:
            return "Volume Up"
        case .volumeDown:
            return "Volume Down"
        case .setVolume:
            return "Set Volume"
        case .launchApp:
            return "Launch App"
        case .switchInput:
            return "Switch Input"
        }
    }

    var requiresPayload: Bool {
        switch self {
        case .setVolume, .launchApp, .switchInput:
            return true
        default:
            return false
        }
    }
}

struct TVSceneAction: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var kind: TVSceneActionKind
    var payload: String?

    init(
        id: UUID = UUID(),
        kind: TVSceneActionKind,
        payload: String? = nil
    ) {
        self.id = id
        self.kind = kind
        let normalizedPayload = payload?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.payload = normalizedPayload?.isEmpty == true ? nil : normalizedPayload
    }

    var summary: String {
        guard let payload else {
            return kind.title
        }
        return "\(kind.title): \(payload)"
    }
}

struct TVSmartScene: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var iconSystemName: String
    var actions: [TVSceneAction]
    var lastRunAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        iconSystemName: String = "sparkles.tv.fill",
        actions: [TVSceneAction],
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.iconSystemName = iconSystemName
        self.actions = actions
        self.lastRunAt = lastRunAt
    }

    var actionSummary: String {
        if actions.isEmpty {
            return "No actions"
        }
        if actions.count == 1 {
            return actions[0].summary
        }
        return "\(actions[0].summary) +\(actions.count - 1)"
    }
}

struct TVVoiceMacro: Identifiable, Codable, Equatable {
    var id: UUID
    var phrase: String
    var sceneID: UUID
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        phrase: String,
        sceneID: UUID,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sceneID = sceneID
        self.lastUsedAt = lastUsedAt
    }
}

enum TVAICopilotConfidence: String, Codable, Equatable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

enum TVAILearningMode: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
    case off
    case balanced
    case aggressive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .balanced:
            return "Balanced"
        case .aggressive:
            return "Aggressive"
        }
    }
}

struct TVAICopilotSuggestion: Identifiable, Equatable {
    var id: UUID
    var name: String
    var iconSystemName: String
    var actions: [TVSceneAction]
    var confidence: TVAICopilotConfidence
    var rationale: String

    init(
        id: UUID = UUID(),
        name: String,
        iconSystemName: String = "sparkles.tv.fill",
        actions: [TVSceneAction],
        confidence: TVAICopilotConfidence,
        rationale: String
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.iconSystemName = iconSystemName
        self.actions = actions
        self.confidence = confidence
        self.rationale = rationale
    }

    var actionSummary: String {
        if actions.isEmpty {
            return "No actions"
        }
        if actions.count == 1 {
            return actions[0].summary
        }
        return "\(actions[0].summary) +\(actions.count - 1)"
    }
}

struct TVAIMacroRecommendation: Identifiable, Equatable {
    var id: UUID
    var phrase: String
    var sceneName: String
    var iconSystemName: String
    var actions: [TVSceneAction]
    var confidence: TVAICopilotConfidence
    var rationale: String
    var useCount: Int

    init(
        id: UUID = UUID(),
        phrase: String,
        sceneName: String,
        iconSystemName: String = "waveform.and.mic",
        actions: [TVSceneAction],
        confidence: TVAICopilotConfidence,
        rationale: String,
        useCount: Int
    ) {
        self.id = id
        self.phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sceneName = sceneName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.iconSystemName = iconSystemName
        self.actions = actions
        self.confidence = confidence
        self.rationale = rationale
        self.useCount = useCount
    }
}

enum TVAutomationActionKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case powerOn
    case powerOff
    case muteOn
    case muteOff
    case setVolume
    case launchApp
    case switchInput

    var id: String { rawValue }

    var title: String {
        switch self {
        case .powerOn:
            return "Power On"
        case .powerOff:
            return "Power Off"
        case .muteOn:
            return "Mute"
        case .muteOff:
            return "Unmute"
        case .setVolume:
            return "Set Volume"
        case .launchApp:
            return "Launch App"
        case .switchInput:
            return "Switch Input"
        }
    }
}

struct TVAutomationRule: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var action: TVAutomationActionKind
    var payload: String?
    var hour: Int
    var minute: Int
    var weekdays: [Int]
    var isEnabled: Bool
    var lastExecutedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        action: TVAutomationActionKind,
        payload: String? = nil,
        hour: Int,
        minute: Int,
        weekdays: [Int],
        isEnabled: Bool = true,
        lastExecutedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.action = action
        self.payload = payload
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
        self.weekdays = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        self.isEnabled = isEnabled
        self.lastExecutedAt = lastExecutedAt
    }

    var timeLabel: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    var weekdayLabel: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        if weekdays.count == 7 {
            return "Every day"
        }
        if weekdays == [2, 3, 4, 5, 6] {
            return "Weekdays"
        }
        if weekdays == [1, 7] {
            return "Weekends"
        }
        return weekdays.compactMap { index in
            guard index >= 1, index <= symbols.count else { return nil }
            return symbols[index - 1]
        }.joined(separator: ", ")
    }

    func matches(date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday, let currentHour = components.hour, let currentMinute = components.minute else {
            return false
        }
        return weekdays.contains(weekday) && currentHour == hour && currentMinute == minute
    }

    func hasExecutedInSameMinute(as date: Date, calendar: Calendar) -> Bool {
        guard let lastExecutedAt else { return false }
        let current = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let previous = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: lastExecutedAt)
        return current.year == previous.year
            && current.month == previous.month
            && current.day == previous.day
            && current.hour == previous.hour
            && current.minute == previous.minute
    }
}

extension TVDiagnosticsSnapshot {
    static let empty = TVDiagnosticsSnapshot(
        timestamp: Date(),
        connectionStateLabel: "Idle",
        deviceName: "No TV",
        deviceIP: "N/A",
        endpointPort: nil,
        commandTransport: "SSAP sendButton",
        reconnectAttempts: 0,
        commandRetryCount: 0,
        pingFailureCount: 0,
        lastAutoRecoveryAt: nil,
        lastErrorCode: nil,
        lastErrorMessage: nil,
        lastFailedCommand: nil,
        lastErrorAt: nil,
        serviceNames: [],
        supportedCapabilities: [],
        nowPlayingProbeSummary: nil,
        commandLatencyTelemetry: .empty
    )
}

extension TVCommandLatencyTelemetry {
    static let empty = TVCommandLatencyTelemetry(
        windowSampleCount: 0,
        successfulCount: 0,
        timeoutCount: 0,
        lastCommandKey: nil,
        lastLatencyMs: nil,
        lastWasSuccess: false,
        lastWasTimeout: false,
        averageLatencyMs: nil,
        p50LatencyMs: nil,
        p95LatencyMs: nil
    )
}

extension TVReliabilitySnapshot {
    static let empty = TVReliabilitySnapshot(
        generatedAt: Date(),
        windowDays: 14,
        discovery: TVReliabilityMetricSummary(attempts: 0, successes: 0),
        connection: TVReliabilityMetricSummary(attempts: 0, successes: 0),
        command: TVReliabilityMetricSummary(attempts: 0, successes: 0),
        fixWorkflow: TVReliabilityMetricSummary(attempts: 0, successes: 0),
        autoReconnect: TVReliabilityMetricSummary(attempts: 0, successes: 0)
    )
}

extension TVInputSource {
    static let lgDefaults: [TVInputSource] = [
        TVInputSource(id: "hdmi1", title: "HDMI 1", iconSystemName: "cable.connector", inputID: "HDMI_1"),
        TVInputSource(id: "hdmi2", title: "HDMI 2", iconSystemName: "cable.connector", inputID: "HDMI_2"),
        TVInputSource(id: "hdmi3", title: "HDMI 3", iconSystemName: "cable.connector", inputID: "HDMI_3"),
        TVInputSource(id: "hdmi4", title: "HDMI 4", iconSystemName: "cable.connector", inputID: "HDMI_4"),
        TVInputSource(id: "live-tv", title: "Live TV", iconSystemName: "antenna.radiowaves.left.and.right", inputID: "LIVE_TV"),
        TVInputSource(id: "av", title: "AV", iconSystemName: "rectangle.connected.to.line.below", inputID: "AV_1")
    ]
}

extension TVCommand {
    nonisolated var rateLimitKey: String {
        switch self {
        case .volumeUp:
            return "volume_up"
        case .volumeDown:
            return "volume_down"
        case .setVolume:
            return "set_volume"
        case .up:
            return "dpad_up"
        case .down:
            return "dpad_down"
        case .left:
            return "dpad_left"
        case .right:
            return "dpad_right"
        case .select:
            return "select"
        case .back:
            return "back"
        case .home:
            return "home"
        case .menu:
            return "menu"
        case .mute:
            return "mute"
        case .powerOff:
            return "power_off"
        case .powerOn:
            return "power_on"
        case .launchApp:
            return "launch_app"
        case .inputSwitch:
            return "input_switch"
        case .keyboardText:
            return "keyboard_text"
        }
    }

    nonisolated var minimumInterval: TimeInterval {
        switch self {
        case .volumeUp, .volumeDown:
            return 0.11
        case .setVolume:
            return 0.05
        case .up, .down, .left, .right:
            return 0.075
        default:
            return 0.16
        }
    }
}
