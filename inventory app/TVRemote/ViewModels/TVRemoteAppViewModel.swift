import SwiftUI
import Combine
import Network
import Darwin
import Speech
import AVFoundation
import UIKit

@MainActor
final class TVRemoteAppViewModel: ObservableObject {
    @Published private(set) var discoveredDevices: [TVDevice] = []
    @Published private(set) var knownDevices: [TVDevice] = []
    @Published private(set) var connectionState: TVConnectionState = .idle
    @Published var isDevicePickerPresented = false
    @Published var isQuickLaunchSheetPresented = false
    @Published var isInputPickerPresented = false
    @Published var manualIPAddress = ""
    @Published var wakeMACAddress = ""
    @Published var plexMetadataServerURL = ""
    @Published var plexMetadataToken = ""
    @Published var transientErrorMessage: String?
    @Published var isMuted = false
    @Published private(set) var volumeLevel: Double = 50
    @Published private(set) var nowPlayingState: TVNowPlayingState?
    @Published private(set) var nowWatchingHistory: [TVWatchHistoryEntry] = []
    @Published private(set) var voiceTranscript = ""
    @Published private(set) var voiceStatusMessage = "Tap Talk, speak, then send text to TV."
    @Published private(set) var isVoiceListening = false
    @Published private(set) var isSendingVoiceTranscript = false
    @Published var usesSwipePad = false
    @Published private(set) var networkStatusText = "Checking Wi-Fi..."
    @Published private(set) var isWiFiReadyForTVControl = false
    @Published private(set) var isWakeReconnectInProgress = false
    @Published private(set) var manualIPProbeStatus: String?
    @Published private(set) var wakeMACStatusMessage: String?
    @Published private(set) var plexMetadataStatusMessage: String?
    @Published private(set) var diagnosticsStatusMessage: String?
    @Published private(set) var fixMyTVStatusMessage: String?
    @Published private(set) var isProbingManualIP = false
    @Published private(set) var quickLaunchApps: [TVAppShortcut] = TVAppShortcut.lgDefaults
    @Published private(set) var inputSources: [TVInputSource] = TVInputSource.lgDefaults
    @Published private(set) var favoriteQuickLaunchIDs: [String] = []
    @Published private(set) var smartScenes: [TVSmartScene] = []
    @Published private(set) var sceneStatusMessage: String?
    @Published private(set) var sceneDraftMessage: String?
    @Published var isSceneComposerPresented = false
    @Published var sceneDraftName = "TV Night"
    @Published var sceneDraftIconSystemName = "sparkles.tv.fill"
    @Published private(set) var sceneDraftActions: [TVSceneAction] = []
    @Published private(set) var voiceMacros: [TVVoiceMacro] = []
    @Published var voiceMacroDraftPhrase = ""
    @Published var voiceMacroDraftSceneID: UUID?
    @Published private(set) var voiceMacroStatusMessage: String?
    @Published var sceneCopilotPrompt = ""
    @Published private(set) var sceneCopilotStatusMessage: String?
    @Published private(set) var sceneCopilotSuggestions: [TVAICopilotSuggestion] = []
    @Published private(set) var sceneCopilotContextSuggestions: [TVAICopilotSuggestion] = []
    @Published private(set) var aiMacroRecommendations: [TVAIMacroRecommendation] = []
    @Published private(set) var aiLearningMode: TVAILearningMode = .balanced
    @Published private(set) var automationRules: [TVAutomationRule] = []
    @Published private(set) var automationStatusMessage: String?
    @Published var isAutomationComposerPresented = false
    @Published var automationDraftName = "Weekday Power On"
    @Published var automationDraftAction: TVAutomationActionKind = .powerOn
    @Published var automationDraftTime = Date()
    @Published var automationDraftSelectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @Published var automationDraftPayload = ""
    @Published private(set) var automationDraftMessage: String?
    @Published private(set) var lockedAppIDs: Set<String> = []
    @Published private(set) var lockedInputIDs: Set<String> = []
    @Published var plainCommandText = ""
    @Published private(set) var plainCommandStatusMessage = "Type a command like \"open YouTube\" or \"volume up\"."
    @Published var isAppInputLockEnabled = false
    @Published var isCaregiverModeEnabled = false
    @Published private(set) var diagnosticsSnapshot: TVDiagnosticsSnapshot = .empty
    @Published private(set) var reliabilitySnapshot: TVReliabilitySnapshot = .empty
    @Published private(set) var growthSnapshot: TVAnalyticsSnapshot = .empty
    @Published private(set) var premiumSnapshot: TVPremiumSnapshot = .empty
    @Published private(set) var premiumStatusMessage: String?
    @Published private(set) var premiumProducts: [TVPremiumProduct] = []
    @Published private(set) var isPremiumCatalogLoading = false
    @Published private(set) var isPremiumPurchaseInFlight = false
    @Published private(set) var purchasingPremiumProductID: String?
    @Published private(set) var isPremiumRestoreInFlight = false
    @Published var isPremiumPaywallPresented = false
    @Published private(set) var premiumPaywallSource = "manual"
    @Published private(set) var isAdvancedSettingsVisible = false
    @Published var powerSetupLGConnectAppsEnabled = false
    @Published var powerSetupMobileTVOnEnabled = false
    @Published var powerSetupQuickStartEnabled = false

    private let controller: TVController
    private let defaults: UserDefaults
    private let reliabilityTracker: TVReliabilityTracker
    private let analyticsTracker: TVAnalyticsTracker
    private let premiumAccessStore: TVPremiumAccessStore
    private let premiumBillingService: TVPremiumBillingService
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.reggieboi.tvremote.ui.path")
    private var hasStarted = false
    private let quickLaunchFavoritesKey = "tvremote.quick_launch_favorites.v1"
    private let watchingHistoryKey = "tvremote.now_watching_history.v1"
    private let manualNowPlayingTitlesKey = "tvremote.now_playing_manual_titles.v1"
    private let smartScenesKey = "tvremote.smart_scenes.v1"
    private let voiceMacrosKey = "tvremote.voice_macros.v1"
    private let aiPatternStatsKey = "tvremote.ai.pattern_stats.v1"
    private let aiLearningModeKey = "tvremote.ai.learning_mode.v1"
    private let automationRulesKey = "tvremote.automation_rules.v1"
    private let appInputLockEnabledKey = "tvremote.app_input_lock.enabled.v1"
    private let lockedAppIDsKey = "tvremote.app_input_lock.apps.v1"
    private let lockedInputIDsKey = "tvremote.app_input_lock.inputs.v1"
    private let caregiverModeKey = "tvremote.caregiver_mode.v1"
    private let advancedSettingsVisibleKey = "tvremote.ui.advanced_settings.visible.v1"
    private let powerSetupLGConnectKey = "tvremote.power_setup.lg_connect_apps.v1"
    private let powerSetupMobileTVOnKey = "tvremote.power_setup.mobile_tv_on.v1"
    private let powerSetupQuickStartKey = "tvremote.power_setup.quick_start.v1"
    private var volumeSetTask: Task<Void, Never>?
    private var volumeRefreshTask: Task<Void, Never>?
    private var nowPlayingPollTask: Task<Void, Never>?
    private var wakeReconnectTask: Task<Void, Never>?
    private var automationTimer: Timer?
    private var reliabilityWatchdogTask: Task<Void, Never>?
    private var pendingVolumeLevel: Int?
    private var isVolumeSliderEditing = false
    private var consecutiveHealthCheckFailures = 0
    private var discoveryOutcomeTask: Task<Void, Never>?
    private var isDiscoveryAttemptInFlight = false
    private var isFixWorkflowRunning = false
    private var isAutoReconnectTrackingActive = false
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var speechRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechRecognitionTask: SFSpeechRecognitionTask?
    private var inFlightContinuousCommandKeys: Set<String> = []
    private var lastCommandDispatchAt: Date = .distantPast
    private var isHealthCheckInFlight = false
    private var hasActivePaywallPresentation = false
    private let freeSmartSceneLimit = 1
    private let freeSmartSceneActionLimit = 2
    private var aiPatternStats: [String: AIPatternStat] = [:]
    private var dismissedAIPatternSignatures: Set<String> = []
    private var manualNowPlayingTitlesByKey: [String: String] = [:]

    static let smartSceneIconChoices: [String] = [
        "sparkles.tv.fill",
        "moon.stars.fill",
        "bolt.fill",
        "play.rectangle.fill",
        "sportscourt.fill",
        "house.fill",
        "film.stack.fill",
        "gamecontroller.fill"
    ]

    private enum WidgetDeepLinkAction: String {
        case home
        case back
        case mute
        case powerOff
        case powerOn
        case open
    }

    init(controller: TVController, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.defaults = defaults
        analyticsTracker = TVAnalyticsTracker(
            defaults: defaults,
            storageKey: "tvremote.analytics.events.v1"
        )
        premiumAccessStore = TVPremiumAccessStore(defaults: defaults)
        premiumBillingService = TVPremiumBillingService(bundle: .main)
        reliabilityTracker = TVReliabilityTracker(
            defaults: defaults,
            storageKey: "tvremote.reliability.events.v1"
        )
        knownDevices = controller.knownDevices
        reliabilitySnapshot = reliabilityTracker.snapshot()
        growthSnapshot = analyticsTracker.snapshot()
        premiumSnapshot = premiumAccessStore.snapshot()
        favoriteQuickLaunchIDs = Self.loadFavorites(from: defaults)
        var seenFavoriteIDs = Set<String>()
        favoriteQuickLaunchIDs = favoriteQuickLaunchIDs.filter { seenFavoriteIDs.insert($0).inserted }
        syncFavoriteQuickLaunchSelection()
        loadWatchingHistory()
        loadManualNowPlayingTitles()
        loadSmartScenes()
        loadVoiceMacros()
        loadAILearningMode()
        loadAIPatternStats()
        loadAutomationRules()
        loadLockAndCaregiverState()
        rebuildAIMacroRecommendations()
        refreshSceneCopilotContextSuggestions()
        startPathMonitor()
        bindController()
        loadAdvancedSettingsState()
        loadPowerSetupChecklistState()
        syncWakeMACDraft()
        syncPlexMetadataDraft()
        refreshDiagnostics()
        premiumBillingService.onEntitlementsChanged = { [weak self] productIDs in
            guard let self else { return }
            _ = self.premiumAccessStore.syncEntitlements(productIDs: productIDs)
            self.premiumSnapshot = self.premiumAccessStore.snapshot()
            self.refreshDiagnostics()
        }
    }

    deinit {
        volumeSetTask?.cancel()
        volumeRefreshTask?.cancel()
        nowPlayingPollTask?.cancel()
        wakeReconnectTask?.cancel()
        automationTimer?.invalidate()
        reliabilityWatchdogTask?.cancel()
        discoveryOutcomeTask?.cancel()
        pathMonitor.cancel()
    }

    convenience init() {
        self.init(controller: LGWebOSController())
    }

    var activeDevice: TVDevice? {
        switch connectionState {
        case let .connected(device):
            return device
        case let .pairing(device):
            return device
        case let .reconnecting(device):
            return device
        default:
            return controller.currentDevice
        }
    }

    var activeDeviceName: String {
        activeDevice?.name ?? "No TV Connected"
    }

    var statusText: String {
        if isWakeReconnectInProgress {
            return "Waking TV..."
        }
        return connectionState.shortLabel
    }

    var supportsControls: Bool {
        connectionState.isConnected
    }

    var supportsDirectionalPad: Bool {
        guard supportsControls else { return false }
        return activeCapabilities.contains(.dpad)
    }

    var supportsPowerControls: Bool {
        guard supportsControls else { return false }
        return activeCapabilities.contains(.power)
    }

    var supportsVolumeControls: Bool {
        guard supportsControls else { return false }
        return activeCapabilities.contains(.volume)
    }

    var supportsBackCommand: Bool {
        guard supportsControls else { return false }
        return activeCapabilities.contains(.back) || activeCapabilities.contains(.dpad)
    }

    var supportsHomeCommand: Bool {
        guard supportsControls else { return false }
        return activeCapabilities.contains(.home) || activeCapabilities.contains(.dpad)
    }

    var supportsMenuCommand: Bool {
        guard supportsControls else { return false }
        return activeCapabilities.contains(.dpad)
    }

    var canAttemptPowerOn: Bool {
        if activeDevice != nil {
            return true
        }
        return !knownDevices.isEmpty
    }

    var supportsLaunchApps: Bool {
        guard supportsControls else { return false }
        return activeCapabilities.contains(.launchApp)
    }

    var isPlexMetadataConfigured: Bool {
        controller.plexMetadataConfiguration().isConfigured
    }

    var supportsInputSwitching: Bool {
        guard supportsControls else { return false }
        return activeCapabilities.contains(.inputSwitch)
    }

    var nowPlayingHeadline: String {
        guard supportsControls else { return "Not connected" }
        if let title = effectiveNowPlayingState?.title, !title.isEmpty {
            return title
        }
        return effectiveNowPlayingState?.appName ?? "Detecting what's on screen..."
    }

    var nowPlayingDetail: String {
        guard supportsControls else {
            return "Connect to a TV to see live playback info."
        }
        guard let state = effectiveNowPlayingState else {
            return "Shows app and title when LG webOS exposes playback metadata."
        }

        var parts = [state.appName]
        if let subtitle = state.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        if state.title == nil, state.subtitle == nil {
            if state.isProviderMetadataRestricted {
                parts.append("Provider-limited metadata")
            } else {
                parts.append("Metadata unavailable")
            }
        } else if hasManualNowPlayingTitleOverride {
            parts.append("Manual title")
        }
        return parts.joined(separator: " • ")
    }

    var nowPlayingSourceLabel: String {
        effectiveNowPlayingState?.source.label ?? "Live"
    }

    var nowPlayingConfidence: TVNowPlayingConfidence {
        effectiveNowPlayingState?.confidence ?? .low
    }

    var nowPlayingConfidenceLabel: String {
        nowPlayingConfidence.shortLabel
    }

    var nowPlayingConfidenceAccessibilityLabel: String {
        nowPlayingConfidence.label
    }

    var shouldShowNowPlayingManualCapture: Bool {
        guard supportsControls, nowPlayingState != nil else { return false }
        if hasManualNowPlayingTitleOverride {
            return true
        }
        guard let state = nowPlayingState else { return false }
        return state.title == nil || state.isProviderMetadataRestricted
    }

    var nowPlayingManualCaptureButtonTitle: String {
        hasManualNowPlayingTitleOverride ? "Edit Title" : "Set Title"
    }

    var nowPlayingManualCaptureHint: String {
        if let state = nowPlayingState, state.isProviderMetadataRestricted {
            return "This app hides title metadata. Add it manually."
        }
        return "If title detection misses, add it manually."
    }

    var hasManualNowPlayingTitleOverride: Bool {
        guard let state = nowPlayingState else { return false }
        return manualNowPlayingTitleOverride(for: state) != nil
    }

    private var effectiveNowPlayingState: TVNowPlayingState? {
        guard let nowPlayingState else { return nil }
        return resolvedNowPlayingState(nowPlayingState)
    }

    var recentWatchingHistory: [TVWatchHistoryEntry] {
        Array(nowWatchingHistory.prefix(6))
    }

    var hasWatchingHistory: Bool {
        !nowWatchingHistory.isEmpty
    }

    var favoriteQuickLaunchApps: [TVAppShortcut] {
        let byID = Dictionary(uniqueKeysWithValues: quickLaunchApps.map { ($0.id, $0) })
        return favoriteQuickLaunchIDs.compactMap { byID[$0] }
    }

    var dockQuickLaunchApps: [TVAppShortcut] {
        if favoriteQuickLaunchApps.isEmpty {
            return Array(quickLaunchApps.prefix(4))
        }
        return favoriteQuickLaunchApps
    }

    var nonFavoriteQuickLaunchApps: [TVAppShortcut] {
        let favoriteIDs = Set(favoriteQuickLaunchIDs)
        return quickLaunchApps.filter { !favoriteIDs.contains($0.id) }
    }

    var quickLaunchCountLocked: Int {
        quickLaunchApps.filter { isAppLocked($0) }.count
    }

    var inputCountLocked: Int {
        inputSources.filter { isInputLocked($0) }.count
    }

    var sceneIconChoices: [String] {
        Self.smartSceneIconChoices
    }

    var smartScenesPlanSummary: String {
        if hasSmartScenesProAccess {
            return "Pro scenes active: unlimited scenes and actions."
        }
        return "Free plan: 1 scene, up to 2 actions per scene."
    }

    var smartScenesUsageSummary: String {
        if hasSmartScenesProAccess {
            return "\(smartScenes.count) scenes"
        }
        return "\(smartScenes.count)/\(freeSmartSceneLimit) scene used"
    }

    var smartSceneComposerActionLimitLabel: String {
        if hasSmartScenesProAccess {
            return "Unlimited actions"
        }
        return "\(sceneDraftActions.count)/\(freeSmartSceneActionLimit) actions (Free)"
    }

    var canCreateAdditionalSmartScene: Bool {
        hasSmartScenesProAccess || smartScenes.count < freeSmartSceneLimit
    }

    var canAddSceneDraftAction: Bool {
        hasSmartScenesProAccess || sceneDraftActions.count < freeSmartSceneActionLimit
    }

    var voiceMacroPlanSummary: String {
        if hasSmartScenesProAccess {
            return "Voice Macros Pro: trigger scenes with custom phrases."
        }
        return "Voice Macros are part of Pro."
    }

    var sceneCopilotPlanSummary: String {
        if hasSmartScenesProAccess {
            return "AI Scene Copilot is active."
        }
        return "AI Scene Copilot is part of Pro."
    }

    var hasVoiceMacros: Bool {
        !voiceMacros.isEmpty
    }

    var hasSceneCopilotSuggestions: Bool {
        !sceneCopilotSuggestions.isEmpty
    }

    var hasSceneCopilotContextSuggestions: Bool {
        !sceneCopilotContextSuggestions.isEmpty
    }

    var hasAIMacroRecommendations: Bool {
        !aiMacroRecommendations.isEmpty
    }

    var aiLearningModes: [TVAILearningMode] {
        TVAILearningMode.allCases
    }

    var aiLearningModeSummary: String {
        switch aiLearningMode {
        case .off:
            return "AI learning is off. The app will not generate new macro suggestions."
        case .balanced:
            return "Balanced mode suggests stable macros after repeated usage."
        case .aggressive:
            return "Aggressive mode learns faster and surfaces more macro suggestions."
        }
    }

    var sceneCopilotPromptSuggestions: [String] {
        var prompts: [String] = [
            "movie night on HDMI 1 volume 18",
            "sports mode launch YouTube TV volume 30",
            "quiet mode open Netflix volume 12"
        ]

        if let appName = nowPlayingState?.appName, !appName.isEmpty {
            prompts.insert("open \(appName) and set volume 20", at: 0)
        }

        var seen = Set<String>()
        return prompts.filter { seen.insert($0.lowercased()).inserted }
    }

    var sortedVoiceMacros: [TVVoiceMacro] {
        voiceMacros.sorted { lhs, rhs in
            lhs.phrase.localizedCaseInsensitiveCompare(rhs.phrase) == .orderedAscending
        }
    }

    var canSaveVoiceMacroDraft: Bool {
        guard hasSmartScenesProAccess else { return false }
        guard !voiceMacroDraftPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let sceneID = voiceMacroDraftSceneID else { return false }
        return smartScenes.contains { $0.id == sceneID }
    }

    var hasMacroShortcutsAccess: Bool {
        hasSmartScenesProAccess
    }

    var automationRulesSummary: String {
        if automationRules.isEmpty {
            return "No automations configured."
        }
        let enabledCount = automationRules.filter(\.isEnabled).count
        return "\(enabledCount) enabled of \(automationRules.count)."
    }

    var automationWeekdayChoices: [Int] {
        Array(1...7)
    }

    var availableAutomationLaunchApps: [TVAppShortcut] {
        quickLaunchApps.isEmpty ? TVAppShortcut.lgDefaults : quickLaunchApps
    }

    var availableAutomationInputs: [TVInputSource] {
        inputSources.isEmpty ? TVInputSource.lgDefaults : inputSources
    }

    var localNetworkGuidanceVisible: Bool {
        if case let .failed(message) = connectionState {
            let normalized = message.lowercased()
            return normalized.contains("local network")
                || normalized.contains("multicast")
                || normalized.contains("discovery is blocked")
                || normalized.contains("same wi-fi")
        }
        return false
    }

    var networkCheckNeedsAttention: Bool {
        let normalized = networkStatusText.lowercased()
        return normalized.contains("not connected")
            || normalized.contains("no local ipv4")
    }

    var powerSetupWakeMACConfigured: Bool {
        configuredWakeMACAddress() != nil
    }

    var powerSetupChecklistCompletedCount: Int {
        var checks = 0
        if powerSetupLGConnectAppsEnabled { checks += 1 }
        if powerSetupMobileTVOnEnabled { checks += 1 }
        if powerSetupQuickStartEnabled { checks += 1 }
        if powerSetupWakeMACConfigured { checks += 1 }
        if isWiFiReadyForTVControl { checks += 1 }
        return checks
    }

    var powerSetupChecklistTotalCount: Int {
        5
    }

    var powerSetupChecklistSummary: String {
        let completed = powerSetupChecklistCompletedCount
        let total = powerSetupChecklistTotalCount
        if completed == total {
            return "Power-on setup looks complete."
        }
        return "\(completed)/\(total) checks complete."
    }

    var canRunPowerOnSetupTest: Bool {
        canAttemptPowerOn && powerSetupWakeMACConfigured && isWiFiReadyForTVControl
    }

    var reliabilityHeadline: String {
        guard reliabilitySnapshot.hasAnyData else {
            return "Reliability baseline is building."
        }
        guard let score = reliabilitySnapshot.overallScore else {
            return "Reliability baseline is building."
        }
        return "Reliability \(score)% • \(reliabilitySnapshot.overallLabel)"
    }

    var reliabilityDetail: String {
        guard reliabilitySnapshot.hasAnyData else {
            return "Run commands and reconnect checks to measure real-world stability."
        }

        return "Cmd \(reliabilitySnapshot.command.successRatePercentText) • Connect \(reliabilitySnapshot.connection.successRatePercentText) • Discover \(reliabilitySnapshot.discovery.successRatePercentText)"
    }

    var premiumStatusLabel: String {
        premiumSnapshot.statusLabel
    }

    var premiumCTAButtonTitle: String {
        premiumSnapshot.tier == .pro ? "Manage Pro" : "Upgrade to Pro"
    }

    var premiumPaywallHeadline: String {
        switch premiumPaywallSource {
        case "smart_scene_count_limit", "smart_scene_action_limit":
            return "Unlock Unlimited Smart Scenes"
        case "custom_automation":
            return "Unlock Custom Automations"
        case "talk_to_tv":
            return "Unlock Talk to TV Pro"
        case "voice_macro":
            return "Unlock Voice Macros Pro"
        case "scene_copilot":
            return "Unlock AI Scene Copilot"
        default:
            return "Upgrade to Pro"
        }
    }

    var premiumPaywallBodyText: String {
        switch premiumPaywallSource {
        case "smart_scene_count_limit":
            return "Free includes 1 smart scene. Pro unlocks unlimited scene presets."
        case "smart_scene_action_limit":
            return "Free includes up to 2 actions per scene. Pro unlocks unlimited actions."
        case "custom_automation":
            return "Create and schedule unlimited custom automations with Pro."
        case "talk_to_tv":
            return "Voice dictation and advanced Talk to TV controls are included in Pro."
        case "voice_macro":
            return "Create custom voice phrases that instantly run your Smart Scenes."
        case "scene_copilot":
            return "Describe a setup in plain English and AI Scene Copilot builds it for you."
        default:
            return "Upgrade to Pro for premium workflows while keeping core remote controls fast and reliable."
        }
    }

    var premiumPaywallContextBadge: String {
        switch premiumPaywallSource {
        case "smart_scene_count_limit", "smart_scene_action_limit":
            return "Smart Scenes"
        case "custom_automation":
            return "Automations"
        case "talk_to_tv":
            return "Talk to TV"
        case "voice_macro":
            return "Voice Macros"
        case "scene_copilot":
            return "AI Copilot"
        case "devices_sheet":
            return "Pro"
        default:
            return "Upgrade"
        }
    }

    var featuredPremiumProduct: TVPremiumProduct? {
        premiumProducts.first(where: \.isFeatured) ?? premiumProducts.first
    }

    var growthFunnelSummary: String {
        growthSnapshot.funnelSummary
    }

    var diagnosticsClipboardText: String {
        let snapshot = diagnosticsSnapshot
        let timestamp = Self.diagnosticsFormatter.string(from: snapshot.timestamp)
        let errorTimestamp = snapshot.lastErrorAt.map { Self.diagnosticsFormatter.string(from: $0) } ?? "N/A"
        let autoRecoveryTimestamp = snapshot.lastAutoRecoveryAt.map { Self.diagnosticsFormatter.string(from: $0) } ?? "N/A"
        let endpoint = snapshot.endpointPort.map { "\(snapshot.deviceIP):\($0)" } ?? snapshot.deviceIP
        let services = snapshot.serviceNames.isEmpty ? "None" : snapshot.serviceNames.joined(separator: ", ")
        let capabilities = snapshot.supportedCapabilities.isEmpty
            ? "None"
            : snapshot.supportedCapabilities.map(\.rawValue).joined(separator: ", ")
        let latencyTelemetry = snapshot.commandLatencyTelemetry
        let latencySummary: String
        if let average = latencyTelemetry.averageLatencyMs,
           let p50 = latencyTelemetry.p50LatencyMs,
           let p95 = latencyTelemetry.p95LatencyMs {
            latencySummary = "avg \(average)ms • p50 \(p50)ms • p95 \(p95)ms"
        } else {
            latencySummary = "N/A"
        }
        let lastLatencyStatus: String
        if latencyTelemetry.lastWasTimeout {
            lastLatencyStatus = "timeout"
        } else if latencyTelemetry.lastWasSuccess {
            lastLatencyStatus = "ok"
        } else {
            lastLatencyStatus = "failed"
        }
        let lastLatencyLabel = latencyTelemetry.lastLatencyMs.map { "\($0)ms" } ?? "N/A"
        let lastLatencyCommand = latencyTelemetry.lastCommandKey ?? "N/A"

        return """
        Diagnostics Captured: \(timestamp)
        State: \(snapshot.connectionStateLabel)
        Device: \(snapshot.deviceName)
        Endpoint: \(endpoint)
        Transport: \(snapshot.commandTransport)
        Reconnect Attempts: \(snapshot.reconnectAttempts)
        Command Retries: \(snapshot.commandRetryCount)
        Ping Failures: \(snapshot.pingFailureCount)
        Last Auto-Recovery At: \(autoRecoveryTimestamp)
        Services: \(services)
        Capabilities: \(capabilities)
        Last Error Code: \(snapshot.lastErrorCode.map(String.init) ?? "N/A")
        Last Error: \(snapshot.lastErrorMessage ?? "N/A")
        Last Failed Command: \(snapshot.lastFailedCommand ?? "N/A")
        Last Error At: \(errorTimestamp)
        Command Latency: \(latencySummary)
        Command Window: \(latencyTelemetry.windowSampleCount) samples • Success \(latencyTelemetry.successRatePercentText) • Timeout \(latencyTelemetry.timeoutCount)
        Last Command RTT: \(lastLatencyCommand) • \(lastLatencyLabel) • \(lastLatencyStatus)
        Now Playing Probe: \(snapshot.nowPlayingProbeSummary ?? "N/A")
        Reliability (14d): \(reliabilitySnapshot.overallScore.map { "\($0)%" } ?? "N/A") • \(reliabilitySnapshot.overallLabel)
        Reliability Discovery: \(reliabilitySnapshot.discovery.successRatePercentText) (\(reliabilitySnapshot.discovery.successes)/\(reliabilitySnapshot.discovery.attempts))
        Reliability Connect: \(reliabilitySnapshot.connection.successRatePercentText) (\(reliabilitySnapshot.connection.successes)/\(reliabilitySnapshot.connection.attempts))
        Reliability Commands: \(reliabilitySnapshot.command.successRatePercentText) (\(reliabilitySnapshot.command.successes)/\(reliabilitySnapshot.command.attempts))
        Reliability Fix My TV: \(reliabilitySnapshot.fixWorkflow.successRatePercentText) (\(reliabilitySnapshot.fixWorkflow.successes)/\(reliabilitySnapshot.fixWorkflow.attempts))
        Reliability Auto-Reconnect: \(reliabilitySnapshot.autoReconnect.successRatePercentText) (\(reliabilitySnapshot.autoReconnect.successes)/\(reliabilitySnapshot.autoReconnect.attempts))
        Growth (30d): \(growthSnapshot.funnelSummary)
        Paywall: \(growthSnapshot.paywallImpressions) impressions • \(growthSnapshot.paywallUpgradeTaps) upgrade taps • \(growthSnapshot.premiumUnlocks) unlocks
        Premium Plan: \(premiumSnapshot.statusLabel)
        Wi-Fi Status: \(networkStatusText)
        """
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        premiumBillingService.start()
        recordGrowthEvent(
            .appLaunch,
            metadata: [
                "known_devices": knownDevices.isEmpty ? "0" : "1"
            ]
        )
        refreshDiagnostics()
        startAutomationTimerIfNeeded()
        startReliabilityWatchdogIfNeeded()
        controller.startDiscovery()
        beginDiscoveryReliabilityAttempt(source: "launch")

        Task { [weak self] in
            await self?.syncPremiumEntitlements()
            await self?.loadPremiumCatalog(forceRefresh: false)
        }

        Task {
            await controller.reconnectToLastDeviceIfPossible()
            refreshDiagnostics()
            evaluateAutomationsIfNeeded()
        }
    }

    func refreshDiscovery() {
        controller.startDiscovery()
        beginDiscoveryReliabilityAttempt(source: "manual_refresh")
        refreshDiagnostics()
    }

    func refreshNetworkDiagnostics() {
        updateNetworkStatusText(path: pathMonitor.currentPath)
        refreshDiagnostics()
    }

    func handleIncomingURL(_ url: URL) {
        guard let action = Self.widgetAction(from: url) else { return }

        startIfNeeded()
        Task { [weak self] in
            await self?.executeWidgetAction(action)
        }
    }

    func refreshDiagnostics() {
        diagnosticsSnapshot = controller.diagnosticsSnapshot()
        reliabilitySnapshot = reliabilityTracker.snapshot()
        growthSnapshot = analyticsTracker.snapshot()
        premiumSnapshot = premiumAccessStore.snapshot()
    }

    func copyDiagnosticsToClipboard() {
        UIPasteboard.general.string = diagnosticsClipboardText
        diagnosticsStatusMessage = "Diagnostics copied to clipboard."
    }

    func presentPremiumPaywall(source: String = "manual", dismissDevicePicker: Bool = false) {
        func presentNow() {
            hasActivePaywallPresentation = true
            premiumPaywallSource = source
            isPremiumPaywallPresented = true
            recordGrowthEvent(
                .paywallShown,
                metadata: [
                    "source": source,
                    "tier": premiumSnapshot.tier.rawValue
                ]
            )
            Task { [weak self] in
                await self?.syncPremiumEntitlements()
                await self?.loadPremiumCatalog(forceRefresh: false)
            }
        }

        if dismissDevicePicker {
            isDevicePickerPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                Task { @MainActor in
                    self?.presentPremiumPaywall(source: source, dismissDevicePicker: false)
                }
            }
        } else {
            presentNow()
        }
    }

    func handlePremiumPaywallPresentationChanged(isPresented: Bool) {
        if !isPresented, hasActivePaywallPresentation {
            hasActivePaywallPresentation = false
            recordGrowthEvent(.paywallDismissed)
            premiumPaywallSource = "manual"
            refreshDiagnostics()
        }
    }

    func dismissPremiumPaywall() {
        isPremiumPaywallPresented = false
    }

    func activatePremiumFromPaywall() {
        guard let target = featuredPremiumProduct else {
            premiumStatusMessage = "Pro products are loading. Try again in a second."
            Task { [weak self] in
                await self?.loadPremiumCatalog(forceRefresh: true)
            }
            return
        }

        recordGrowthEvent(
            .paywallUpgradeTapped,
            metadata: ["source": premiumPaywallSource]
        )
        purchasePremiumProduct(target.id)
    }

    func restorePremiumFromPaywall() {
        guard !isPremiumRestoreInFlight else { return }

        recordGrowthEvent(
            .paywallRestoreTapped,
            metadata: ["source": premiumPaywallSource]
        )
        isPremiumRestoreInFlight = true
        premiumStatusMessage = "Restoring purchases..."

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isPremiumRestoreInFlight = false
                self.refreshDiagnostics()
            }

            do {
                let restored = try await self.premiumBillingService.restorePurchases()
                _ = self.premiumAccessStore.syncEntitlements(
                    productIDs: self.premiumAccessStore.entitlementProductIDs()
                )
                self.premiumSnapshot = self.premiumAccessStore.snapshot()
                self.premiumStatusMessage = restored
                    ? "Pro access restored."
                    : "No active Pro purchase was found."
                if restored {
                    self.recordGrowthEvent(
                        .premiumUnlocked,
                        metadata: ["method": "restore"]
                    )
                }
            } catch {
                self.premiumStatusMessage = error.userFacingMessage
            }
        }
    }

    func refreshPremiumCatalogFromPaywall() {
        Task { [weak self] in
            await self?.loadPremiumCatalog(forceRefresh: true)
        }
    }

    func runFixMyTVWorkflow() {
        fixMyTVStatusMessage = "Running TV checks..."
        transientErrorMessage = nil
        isFixWorkflowRunning = true
        refreshNetworkDiagnostics()
        if !connectionState.isConnected {
            refreshDiscovery()
        }
        manualIPProbeStatus = nil

        Task {
            var didRecordFixOutcome = false
            defer {
                if !didRecordFixOutcome {
                    isFixWorkflowRunning = false
                }
            }
            @MainActor
            func finishFix(success: Bool) {
                guard !didRecordFixOutcome else { return }
                didRecordFixOutcome = true
                recordReliability(.fixWorkflow, success: success)
                isFixWorkflowRunning = false
            }

            if networkCheckNeedsAttention {
                fixMyTVStatusMessage = "Wi-Fi check failed. Connect iPhone and TV to the same Wi-Fi."
                isDevicePickerPresented = true
                finishFix(success: false)
                return
            }

            let candidate = activeDevice ?? knownDevices
                .sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
                .first

            guard let candidate else {
                fixMyTVStatusMessage = "No saved TV yet. Pick your TV from Devices."
                isDevicePickerPresented = true
                finishFix(success: false)
                return
            }

            if connectionState.isConnected, activeDevice?.id == candidate.id {
                if await controller.fetchVolumeState() != nil {
                    await refreshInputSources()
                    await refreshVolumeState()
                    await refreshQuickLaunchApps()
                    await refreshNowPlayingState()
                    refreshDiagnostics()
                    Haptics.success()
                    fixMyTVStatusMessage = "\(candidate.name) is already connected and healthy."
                    finishFix(success: true)
                    return
                }

                fixMyTVStatusMessage = "Connection looked stale. Attempting reconnect..."
            }

            let port3000 = await probeTCP(host: candidate.ip, port: 3000)
            let port3001 = await probeTCP(host: candidate.ip, port: 3001)
            guard port3000 || port3001 else {
                fixMyTVStatusMessage = "TV was not reachable on 3000/3001. Check TV Wi-Fi and LG Connect Apps."
                isDevicePickerPresented = true
                finishFix(success: false)
                return
            }

            do {
                do {
                    try await controller.connect(to: candidate, asReconnection: true)
                } catch {
                    if Self.isCancellationError(error) {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        try await controller.connect(to: candidate, asReconnection: true)
                    } else {
                        throw error
                    }
                }

                recordReliability(.connection, success: true)
                await refreshInputSources()
                await refreshVolumeState()
                await refreshQuickLaunchApps()
                await refreshNowPlayingState()
                refreshDiagnostics()
                Haptics.success()
                fixMyTVStatusMessage = "Reconnected to \(candidate.name)."
                finishFix(success: true)
            } catch {
                recordReliability(.connection, success: false)
                if Self.isCancellationError(error) {
                    fixMyTVStatusMessage = "TV check was interrupted. Try again."
                    refreshDiagnostics()
                    finishFix(success: false)
                    return
                }
                transientErrorMessage = error.userFacingMessage
                fixMyTVStatusMessage = "Reconnect failed. Open Devices and reconnect manually."
                refreshDiagnostics()
                isDevicePickerPresented = true
                finishFix(success: false)
            }
        }
    }

    func runPlainEnglishCommandFromTextField() {
        let command = plainCommandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            plainCommandStatusMessage = "Type a command first."
            return
        }
        plainCommandText = ""
        Task { [weak self] in
            guard let self else { return }
            _ = await self.executePlainEnglishCommand(command, fallbackToKeyboard: true)
        }
    }

    func runSceneCopilotFromPrompt() {
        let prompt = sceneCopilotPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            sceneCopilotStatusMessage = "Describe what you want first. Example: movie night on HDMI 1 volume 18."
            return
        }

        guard requirePremium(.macroShortcuts, source: "scene_copilot") else { return }

        let suggestions = buildCopilotSuggestions(from: prompt)
        guard !suggestions.isEmpty else {
            sceneCopilotSuggestions = []
            sceneCopilotStatusMessage = "I could not map that request yet. Try app/input/volume/power words."
            return
        }

        sceneCopilotSuggestions = suggestions
        sceneCopilotStatusMessage = "Generated \(suggestions.count) plan\(suggestions.count == 1 ? "" : "s"). Pick Run or Save."
        recordGrowthEvent(
            .automationCreated,
            metadata: [
                "action": "scene_copilot_plan",
                "count": "\(suggestions.count)"
            ]
        )
    }

    func applySceneCopilotPromptSuggestion(_ prompt: String) {
        sceneCopilotPrompt = prompt
    }

    func clearSceneCopilotSuggestions() {
        sceneCopilotSuggestions = []
        sceneCopilotStatusMessage = "Cleared AI plans."
    }

    func clearSceneCopilotContextSuggestions() {
        sceneCopilotContextSuggestions = []
    }

    func saveSceneCopilotSuggestion(_ suggestionID: UUID) {
        guard requirePremium(.macroShortcuts, source: "scene_copilot") else { return }
        guard let suggestion = sceneCopilotSuggestions.first(where: { $0.id == suggestionID }) else {
            sceneCopilotStatusMessage = "Suggestion is no longer available."
            return
        }

        let uniqueName = uniqueSmartSceneName(base: suggestion.name)
        smartScenes.append(
            TVSmartScene(
                name: uniqueName,
                iconSystemName: suggestion.iconSystemName,
                actions: suggestion.actions
            )
        )
        saveSmartScenes()
        syncVoiceMacroDraftSceneSelection()
        sceneCopilotStatusMessage = "Saved scene: \(uniqueName)"
        sceneStatusMessage = "AI Scene Copilot saved \(uniqueName)."
        Haptics.success()
        recordGrowthEvent(
            .automationCreated,
            metadata: [
                "action": "scene_copilot_save",
                "steps": "\(suggestion.actions.count)"
            ]
        )
    }

    func runSceneCopilotSuggestion(_ suggestionID: UUID) {
        guard requirePremium(.macroShortcuts, source: "scene_copilot") else { return }
        guard let suggestion = sceneCopilotSuggestions.first(where: { $0.id == suggestionID }) else {
            sceneCopilotStatusMessage = "Suggestion is no longer available."
            return
        }

        let transientScene = TVSmartScene(
            name: suggestion.name,
            iconSystemName: suggestion.iconSystemName,
            actions: suggestion.actions
        )

        Task { [weak self] in
            guard let self else { return }
            let success = await self.executeSmartScene(
                transientScene,
                source: "scene_copilot"
            )
            self.sceneCopilotStatusMessage = success
                ? "Ran plan: \(suggestion.name)"
                : "Plan failed: \(suggestion.name)"
        }
    }

    func runSceneCopilotContextSuggestion(_ suggestionID: UUID) {
        guard requirePremium(.macroShortcuts, source: "scene_copilot_context") else { return }
        guard let suggestion = sceneCopilotContextSuggestions.first(where: { $0.id == suggestionID }) else {
            sceneCopilotStatusMessage = "Context suggestion is no longer available."
            return
        }

        let transientScene = TVSmartScene(
            name: suggestion.name,
            iconSystemName: suggestion.iconSystemName,
            actions: suggestion.actions
        )

        Task { [weak self] in
            guard let self else { return }
            let success = await self.executeSmartScene(
                transientScene,
                source: "scene_copilot_context"
            )
            self.sceneCopilotStatusMessage = success
                ? "Ran context plan: \(suggestion.name)"
                : "Context plan failed: \(suggestion.name)"
        }
    }

    func saveSceneCopilotContextSuggestion(_ suggestionID: UUID) {
        guard requirePremium(.macroShortcuts, source: "scene_copilot_context") else { return }
        guard let suggestion = sceneCopilotContextSuggestions.first(where: { $0.id == suggestionID }) else {
            sceneCopilotStatusMessage = "Context suggestion is no longer available."
            return
        }

        let uniqueName = uniqueSmartSceneName(base: suggestion.name)
        smartScenes.append(
            TVSmartScene(
                name: uniqueName,
                iconSystemName: suggestion.iconSystemName,
                actions: suggestion.actions
            )
        )
        saveSmartScenes()
        syncVoiceMacroDraftSceneSelection()
        rebuildAIMacroRecommendations()
        sceneCopilotStatusMessage = "Saved context plan: \(uniqueName)"
        sceneStatusMessage = "Saved scene: \(uniqueName)"
        Haptics.success()
        recordGrowthEvent(
            .automationCreated,
            metadata: [
                "action": "scene_copilot_context_save",
                "steps": "\(suggestion.actions.count)"
            ]
        )
    }

    func runAIMacroRecommendation(_ recommendationID: UUID) {
        guard requirePremium(.macroShortcuts, source: "voice_macro_ai") else { return }
        guard let recommendation = aiMacroRecommendations.first(where: { $0.id == recommendationID }) else {
            voiceMacroStatusMessage = "Recommendation is no longer available."
            return
        }

        let transientScene = TVSmartScene(
            name: recommendation.sceneName,
            iconSystemName: recommendation.iconSystemName,
            actions: recommendation.actions
        )

        Task { [weak self] in
            guard let self else { return }
            let success = await self.executeSmartScene(
                transientScene,
                source: "voice_macro_ai"
            )
            self.voiceMacroStatusMessage = success
                ? "Ran AI suggestion: \"\(recommendation.phrase)\"."
                : "AI suggestion failed: \"\(recommendation.phrase)\"."
        }
    }

    func saveAIMacroRecommendation(_ recommendationID: UUID) {
        guard requirePremium(.macroShortcuts, source: "voice_macro_ai") else { return }
        guard let recommendation = aiMacroRecommendations.first(where: { $0.id == recommendationID }) else {
            voiceMacroStatusMessage = "Recommendation is no longer available."
            return
        }

        let signature = actionSignature(for: recommendation.actions)
        let sceneID: UUID
        if let existingScene = smartScenes.first(where: { actionSignature(for: $0.actions) == signature }) {
            sceneID = existingScene.id
        } else {
            let uniqueName = uniqueSmartSceneName(base: recommendation.sceneName)
            let scene = TVSmartScene(
                name: uniqueName,
                iconSystemName: recommendation.iconSystemName,
                actions: recommendation.actions
            )
            smartScenes.append(scene)
            saveSmartScenes()
            sceneID = scene.id
        }

        let phrase = normalizeMacroPhrase(recommendation.phrase)
        guard !phrase.isEmpty else {
            voiceMacroStatusMessage = "AI suggestion needs a valid phrase."
            return
        }
        if let existingMacroIndex = voiceMacros.firstIndex(where: {
            normalizeMacroPhrase($0.phrase) == phrase
        }) {
            voiceMacros[existingMacroIndex].sceneID = sceneID
        } else {
            voiceMacros.append(
                TVVoiceMacro(
                    phrase: phrase,
                    sceneID: sceneID
                )
            )
        }

        saveVoiceMacros()
        syncVoiceMacroDraftSceneSelection()
        rebuildAIMacroRecommendations()
        voiceMacroStatusMessage = "AI saved macro: \"\(phrase)\"."
        Haptics.success()
        recordGrowthEvent(
            .automationCreated,
            metadata: [
                "action": "voice_macro_ai_save",
                "uses": "\(recommendation.useCount)"
            ]
        )
    }

    func dismissAIMacroRecommendation(_ recommendationID: UUID) {
        if let recommendation = aiMacroRecommendations.first(where: { $0.id == recommendationID }) {
            dismissedAIPatternSignatures.insert(actionSignature(for: recommendation.actions))
        }
        aiMacroRecommendations.removeAll { $0.id == recommendationID }
    }

    func setAILearningMode(_ mode: TVAILearningMode) {
        guard aiLearningMode != mode else { return }
        aiLearningMode = mode
        defaults.set(mode.rawValue, forKey: aiLearningModeKey)

        if mode == .off {
            aiMacroRecommendations = []
            voiceMacroStatusMessage = "AI learning turned off."
        } else {
            voiceMacroStatusMessage = "AI learning set to \(mode.title)."
            rebuildAIMacroRecommendations()
        }
    }

    func saveVoiceMacroFromDraft() {
        guard requirePremium(.macroShortcuts, source: "voice_macro") else { return }

        let normalized = normalizeMacroPhrase(voiceMacroDraftPhrase)
        guard !normalized.isEmpty else {
            voiceMacroStatusMessage = "Enter a voice phrase for the macro."
            return
        }

        guard let sceneID = voiceMacroDraftSceneID,
              smartScenes.contains(where: { $0.id == sceneID }) else {
            voiceMacroStatusMessage = "Choose a scene to map this phrase."
            syncVoiceMacroDraftSceneSelection()
            return
        }

        if let existingIndex = voiceMacros.firstIndex(where: {
            normalizeMacroPhrase($0.phrase) == normalized
        }) {
            voiceMacros[existingIndex].sceneID = sceneID
            voiceMacroStatusMessage = "Updated macro: \"\(normalized)\"."
        } else {
            voiceMacros.append(
                TVVoiceMacro(
                    phrase: normalized,
                    sceneID: sceneID
                )
            )
            voiceMacroStatusMessage = "Saved macro: \"\(normalized)\"."
        }

        saveVoiceMacros()
        rebuildAIMacroRecommendations()
        voiceMacroDraftPhrase = ""
        Haptics.success()
        recordGrowthEvent(
            .automationCreated,
            metadata: [
                "action": "voice_macro"
            ]
        )
    }

    func runVoiceMacro(_ macro: TVVoiceMacro) {
        guard requirePremium(.macroShortcuts, source: "voice_macro") else { return }
        guard let scene = smartScenes.first(where: { $0.id == macro.sceneID }) else {
            voiceMacroStatusMessage = "Scene for this macro was removed."
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let success = await self.executeSmartScene(
                scene,
                source: "voice_macro",
                triggeredPhrase: macro.phrase
            )
            if success {
                self.markVoiceMacroUsed(macro.id)
                self.voiceMacroStatusMessage = "Macro ran: \"\(macro.phrase)\"."
            } else if self.voiceMacroStatusMessage == nil {
                self.voiceMacroStatusMessage = "Macro failed: \"\(macro.phrase)\"."
            }
        }
    }

    func removeVoiceMacro(_ macroID: UUID) {
        voiceMacros.removeAll { $0.id == macroID }
        saveVoiceMacros()
        rebuildAIMacroRecommendations()
    }

    func voiceMacroSceneName(for macro: TVVoiceMacro) -> String {
        smartScenes.first(where: { $0.id == macro.sceneID })?.name ?? "Missing Scene"
    }

    func setAppInputLockEnabled(_ enabled: Bool) {
        isAppInputLockEnabled = enabled
        defaults.set(enabled, forKey: appInputLockEnabledKey)
        plainCommandStatusMessage = enabled
            ? "App/input locking enabled."
            : "App/input locking disabled."
    }

    func setCaregiverModeEnabled(_ enabled: Bool) {
        isCaregiverModeEnabled = enabled
        defaults.set(enabled, forKey: caregiverModeKey)

        if enabled {
            usesSwipePad = false
            if !isAppInputLockEnabled {
                setAppInputLockEnabled(true)
            }
            plainCommandStatusMessage = "Caregiver mode is on. Essential controls only."
        } else {
            plainCommandStatusMessage = "Caregiver mode is off."
        }
    }

    func setAdvancedSettingsVisible(_ isVisible: Bool) {
        isAdvancedSettingsVisible = isVisible
        defaults.set(isVisible, forKey: advancedSettingsVisibleKey)
    }

    func isAppLocked(_ app: TVAppShortcut) -> Bool {
        guard isAppInputLockEnabled else { return false }
        return lockedAppIDs.contains(app.id.lowercased())
    }

    func isInputLocked(_ input: TVInputSource) -> Bool {
        guard isAppInputLockEnabled else { return false }
        return lockedInputIDs.contains(input.id.lowercased())
    }

    func toggleAppLock(_ app: TVAppShortcut) {
        let key = app.id.lowercased()
        if lockedAppIDs.contains(key) {
            lockedAppIDs.remove(key)
        } else {
            lockedAppIDs.insert(key)
        }
        defaults.set(Array(lockedAppIDs).sorted(), forKey: lockedAppIDsKey)
    }

    func toggleInputLock(_ input: TVInputSource) {
        let key = input.id.lowercased()
        if lockedInputIDs.contains(key) {
            lockedInputIDs.remove(key)
        } else {
            lockedInputIDs.insert(key)
        }
        defaults.set(Array(lockedInputIDs).sorted(), forKey: lockedInputIDsKey)
    }

    func toggleAutomationEnabled(_ ruleID: UUID, isEnabled: Bool) {
        guard let index = automationRules.firstIndex(where: { $0.id == ruleID }) else { return }
        automationRules[index].isEnabled = isEnabled
        saveAutomationRules()
    }

    func updateAutomationTime(_ ruleID: UUID, using date: Date) {
        guard let index = automationRules.firstIndex(where: { $0.id == ruleID }) else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        automationRules[index].hour = components.hour ?? automationRules[index].hour
        automationRules[index].minute = components.minute ?? automationRules[index].minute
        saveAutomationRules()
    }

    func automationTimeDate(for rule: TVAutomationRule) -> Date {
        var components = DateComponents()
        components.hour = rule.hour
        components.minute = rule.minute
        return Calendar.current.date(from: components) ?? Date()
    }

    func removeAutomation(_ ruleID: UUID) {
        automationRules.removeAll { $0.id == ruleID }
        saveAutomationRules()
    }

    func addWeekdayPowerOnAutomation() {
        let rule = TVAutomationRule(
            name: "Weekday Power On",
            action: .powerOn,
            hour: 7,
            minute: 0,
            weekdays: [2, 3, 4, 5, 6]
        )
        addAutomationRule(rule)
    }

    func addNightPowerOffAutomation() {
        let rule = TVAutomationRule(
            name: "Night Power Off",
            action: .powerOff,
            hour: 23,
            minute: 0,
            weekdays: [1, 2, 3, 4, 5, 6, 7]
        )
        addAutomationRule(rule)
    }

    func addYouTubeTVAutomation() {
        let rule = TVAutomationRule(
            name: "Launch YouTube TV",
            action: .launchApp,
            payload: youtubeTVAppID,
            hour: 18,
            minute: 30,
            weekdays: [1, 2, 3, 4, 5, 6, 7]
        )
        addAutomationRule(rule)
    }

    func presentAutomationComposer() {
        guard requirePremium(.customAutomations, source: "custom_automation") else { return }
        prepareAutomationDraft()
        isAutomationComposerPresented = true
    }

    func setAutomationDraftAction(_ action: TVAutomationActionKind) {
        automationDraftAction = action
        if automationDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            automationDraftName = action.title
        }

        switch action {
        case .setVolume:
            if Int(automationDraftPayload) == nil {
                automationDraftPayload = "20"
            }
        case .launchApp:
            if automationDraftPayload.isEmpty {
                automationDraftPayload = availableAutomationLaunchApps.first?.appID ?? ""
            }
        case .switchInput:
            if automationDraftPayload.isEmpty {
                automationDraftPayload = availableAutomationInputs.first?.inputID ?? ""
            }
        default:
            break
        }
    }

    func toggleAutomationDraftWeekday(_ weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        if automationDraftSelectedWeekdays.contains(weekday) {
            automationDraftSelectedWeekdays.remove(weekday)
        } else {
            automationDraftSelectedWeekdays.insert(weekday)
        }
    }

    func addCustomAutomationFromDraft() {
        let name = automationDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            automationDraftMessage = "Enter a name for this automation."
            return
        }

        let selectedWeekdays = Array(automationDraftSelectedWeekdays).sorted()
        guard !selectedWeekdays.isEmpty else {
            automationDraftMessage = "Select at least one day."
            return
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: automationDraftTime)
        let hour = components.hour ?? 7
        let minute = components.minute ?? 0

        let payload: String?
        switch automationDraftAction {
        case .setVolume:
            guard let level = Int(automationDraftPayload), (0...100).contains(level) else {
                automationDraftMessage = "Volume must be between 0 and 100."
                return
            }
            payload = String(level)
        case .launchApp:
            let selected = automationDraftPayload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else {
                automationDraftMessage = "Pick an app to launch."
                return
            }
            payload = selected
        case .switchInput:
            let selected = automationDraftPayload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else {
                automationDraftMessage = "Pick an input source."
                return
            }
            payload = selected
        default:
            payload = nil
        }

        let rule = TVAutomationRule(
            name: name,
            action: automationDraftAction,
            payload: payload,
            hour: hour,
            minute: minute,
            weekdays: selectedWeekdays,
            isEnabled: true
        )
        addAutomationRule(rule)
        automationDraftMessage = "Automation added."
        isAutomationComposerPresented = false
    }

    func toggleAutomationWeekday(_ ruleID: UUID, weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        guard let index = automationRules.firstIndex(where: { $0.id == ruleID }) else { return }

        if automationRules[index].weekdays.contains(weekday) {
            automationRules[index].weekdays.removeAll { $0 == weekday }
        } else {
            automationRules[index].weekdays.append(weekday)
            automationRules[index].weekdays.sort()
        }

        if automationRules[index].weekdays.isEmpty {
            automationRules[index].weekdays = [2, 3, 4, 5, 6]
        }
        saveAutomationRules()
    }

    func updateAutomationPayload(_ ruleID: UUID, payload: String?) {
        guard let index = automationRules.firstIndex(where: { $0.id == ruleID }) else { return }
        automationRules[index].payload = payload?.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAutomationRules()
    }

    func shortWeekdayLabel(for weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return "-" }
        return symbols[weekday - 1]
    }

    func connect(to device: TVDevice) {
        Task {
            recordGrowthEvent(
                .connectAttempt,
                metadata: [
                    "mode": "discovered",
                    "device": Self.analyticsSafe(device.name)
                ]
            )
            do {
                try await controller.connect(to: device, asReconnection: false)
                recordReliability(.connection, success: true)
                recordGrowthEvent(
                    .connectResult,
                    metadata: [
                        "mode": "discovered",
                        "success": "1"
                    ]
                )
                await refreshInputSources()
                await refreshVolumeState()
                await refreshQuickLaunchApps()
                await refreshNowPlayingState()
                isDevicePickerPresented = false
                Haptics.success()
                fixMyTVStatusMessage = "Connected to \(device.name)."
                refreshDiagnostics()
            } catch {
                recordReliability(.connection, success: false)
                recordGrowthEvent(
                    .connectResult,
                    metadata: [
                        "mode": "discovered",
                        "success": "0",
                        "error": Self.analyticsSafe(error.userFacingMessage)
                    ]
                )
                transientErrorMessage = error.userFacingMessage
                refreshDiagnostics()
            }
        }
    }

    func connectManualIPAddress() {
        let candidate = manualIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            transientErrorMessage = TVControllerError.invalidAddress.localizedDescription
            return
        }

        Task {
            recordGrowthEvent(
                .connectAttempt,
                metadata: [
                    "mode": "manual_ip",
                    "ip": Self.analyticsSafe(candidate)
                ]
            )
            do {
                try await controller.connectUsingManualIP(candidate)
                recordReliability(.connection, success: true)
                recordGrowthEvent(
                    .connectResult,
                    metadata: [
                        "mode": "manual_ip",
                        "success": "1"
                    ]
                )
                isDevicePickerPresented = false
                Haptics.success()
                manualIPProbeStatus = "Connected to \(candidate)."
                await refreshInputSources()
                await refreshVolumeState()
                await refreshQuickLaunchApps()
                await refreshNowPlayingState()
                fixMyTVStatusMessage = "Connected by IP (\(candidate))."
                refreshDiagnostics()
            } catch {
                recordReliability(.connection, success: false)
                recordGrowthEvent(
                    .connectResult,
                    metadata: [
                        "mode": "manual_ip",
                        "success": "0",
                        "error": Self.analyticsSafe(error.userFacingMessage)
                    ]
                )
                transientErrorMessage = error.userFacingMessage
                refreshDiagnostics()
            }
        }
    }

    func runManualIPReachabilityCheck() {
        let candidate = manualIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            manualIPProbeStatus = "Enter a TV IP first."
            return
        }

        guard let parsed = parseManualAddress(candidate) else {
            manualIPProbeStatus = "Invalid IP format. Use 192.168.x.x or ws://<ip>:3000."
            return
        }

        isProbingManualIP = true
        manualIPProbeStatus = nil

        Task {
            let port3000 = await probeTCP(host: parsed.host, port: 3000)
            let port3001 = await probeTCP(host: parsed.host, port: 3001)
            isProbingManualIP = false

            if port3000 || port3001 {
                let reachablePort = port3000 ? 3000 : 3001
                manualIPProbeStatus = "TV is reachable at \(parsed.host):\(reachablePort). Wi-Fi path is working."
            } else {
                manualIPProbeStatus = "Could not reach \(parsed.host) on 3000/3001. Check LG Connect Apps, router isolation, and subnet."
            }
        }
    }

    func disconnect() {
        controller.disconnect()
        stopNowPlayingPolling(clearState: true)
        stopVoiceCapture(keepStatus: false)
        refreshDiagnostics()
    }

    func send(_ command: TVCommand) {
        if command.coalescesWhileBusy {
            let key = command.rateLimitKey
            guard !inFlightContinuousCommandKeys.contains(key) else { return }
            inFlightContinuousCommandKeys.insert(key)
        }

        lastCommandDispatchAt = Date()

        Task { [weak self] in
            guard let self else { return }
            _ = await self.sendCommandAndHandleResult(command)
            if command.coalescesWhileBusy {
                self.inFlightContinuousCommandKeys.remove(command.rateLimitKey)
            }
        }
    }

    func toggleMute() {
        send(.mute(!isMuted))
    }

    func powerOffTV() {
        send(.powerOff)
    }

    func powerOnTV() {
        wakeReconnectTask?.cancel()
        wakeReconnectTask = nil
        isWakeReconnectInProgress = false
        Task {
            if supportsControls {
                wakeMACStatusMessage = "TV is already on."
                return
            }

            guard configuredWakeMACAddress() != nil else {
                transientErrorMessage = "Power On needs Wake-on-LAN setup. Save your TV MAC in Devices > Advanced."
                return
            }

            recordGrowthEvent(
                .commandAttempt,
                metadata: [
                    "command": TVCommand.powerOn.rateLimitKey
                ]
            )
            do {
                try await controller.send(command: .powerOn)
                recordReliability(.command, success: true)
                recordGrowthEvent(
                    .commandResult,
                    metadata: [
                        "command": TVCommand.powerOn.rateLimitKey,
                        "success": "1"
                    ]
                )
                wakeMACStatusMessage = "Wake signal sent. Reconnecting automatically..."
                startWakeReconnectLoop()
            } catch {
                isWakeReconnectInProgress = false
                recordReliability(.command, success: false)
                recordGrowthEvent(
                    .commandResult,
                    metadata: [
                        "command": TVCommand.powerOn.rateLimitKey,
                        "success": "0",
                        "error": Self.analyticsSafe(error.userFacingMessage)
                    ]
                )
                transientErrorMessage = error.userFacingMessage
                refreshDiagnostics()
            }
        }
    }

    private func startWakeReconnectLoop() {
        wakeReconnectTask?.cancel()
        isWakeReconnectInProgress = true
        wakeReconnectTask = Task { [weak self] in
            guard let self else { return }

            // TVs can take several seconds to fully wake and open control sockets.
            let delays: [UInt64] = [
                900_000_000,
                1_400_000_000,
                2_000_000_000,
                2_800_000_000,
                3_800_000_000,
                5_200_000_000
            ]

            for (index, delay) in delays.enumerated() {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }

                if self.connectionState.isConnected {
                    self.wakeMACStatusMessage = "TV is awake and connected."
                    self.refreshDiagnostics()
                    self.wakeReconnectTask = nil
                    self.isWakeReconnectInProgress = false
                    return
                }

                await self.controller.reconnectToLastDeviceIfPossible()
                if self.connectionState.isConnected {
                    self.wakeMACStatusMessage = "TV is awake and connected."
                    self.fixMyTVStatusMessage = nil
                    self.refreshDiagnostics()
                    self.wakeReconnectTask = nil
                    self.isWakeReconnectInProgress = false
                    return
                }

                // Mid-boot refresher pulse for TVs that miss the first packet.
                if index == 2 {
                    try? await self.controller.send(command: .powerOn)
                }
            }

            if !self.connectionState.isConnected {
                self.wakeMACStatusMessage = "Wake signal sent. TV is still booting."
                self.fixMyTVStatusMessage = "Still waking TV. If needed, tap Fix My TV."
                self.refreshDiagnostics()
            }

            self.wakeReconnectTask = nil
            self.isWakeReconnectInProgress = false
        }
    }

    func reconnectCurrentTV() {
        fixMyTVStatusMessage = "Reconnecting..."
        transientErrorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            await self.controller.reconnectToLastDeviceIfPossible()
            if self.connectionState.isConnected {
                Haptics.success()
                self.fixMyTVStatusMessage = "Reconnected."
                Task { [weak self] in
                    guard let self else { return }
                    await self.runPostReconnectRefresh()
                }
            } else if self.fixMyTVStatusMessage == "Reconnecting..." {
                self.fixMyTVStatusMessage = "Reconnect attempt finished. If needed, use Fix My TV."
            }
            self.refreshDiagnostics()
        }
    }

    private func runPostReconnectRefresh() async {
        await refreshInputSources()
        await refreshVolumeState()
        await refreshQuickLaunchApps()
        await refreshNowPlayingState()
        refreshDiagnostics()
    }

    private static func widgetAction(from url: URL) -> WidgetDeepLinkAction? {
        guard url.scheme?.lowercased() == "pulseremote" else { return nil }

        let host = (url.host ?? "").lowercased()
        let pathSegments = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.lowercased() }

        func action(from value: String?) -> WidgetDeepLinkAction? {
            guard let value, !value.isEmpty else { return nil }
            return WidgetDeepLinkAction(rawValue: value)
        }

        if host == "widget" || host == "command" {
            return action(from: pathSegments.first) ?? action(from: url.lastPathComponent.lowercased())
        }

        if host == "open" {
            return .open
        }

        // Allow compact forms like pulseremote://home
        return action(from: host)
    }

    private func executeWidgetAction(_ action: WidgetDeepLinkAction) async {
        switch action {
        case .open:
            return
        case .powerOn:
            powerOnTV()
        case .home:
            await runWidgetCommand(.home)
        case .back:
            await runWidgetCommand(.back)
        case .mute:
            await runWidgetCommand(.mute(!isMuted))
        case .powerOff:
            await runWidgetCommand(.powerOff)
        }
    }

    private func runWidgetCommand(_ command: TVCommand) async {
        guard await prepareConnectionForWidgetCommand() else {
            transientErrorMessage = "Open Pulse Remote and reconnect to your TV, then try again."
            isDevicePickerPresented = true
            return
        }

        _ = await sendCommandAndHandleResult(command)
    }

    private func prepareConnectionForWidgetCommand() async -> Bool {
        if supportsControls {
            return true
        }

        await controller.reconnectToLastDeviceIfPossible()
        await refreshInputSources()
        await refreshVolumeState()
        await refreshQuickLaunchApps()
        await refreshNowPlayingState()
        refreshDiagnostics()

        return supportsControls
    }

    func restartCurrentApp() {
        guard supportsControls else {
            transientErrorMessage = TVControllerError.notConnected.localizedDescription
            return
        }

        let appID = nowPlayingState?.appID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let appID, !appID.isEmpty else {
            transientErrorMessage = "No active app was detected to restart."
            return
        }

        let appName = nowPlayingState?.appName ?? "app"
        fixMyTVStatusMessage = "Restarting \(appName)..."

        Task { [weak self] in
            guard let self else { return }
            let didReturnHome = await self.sendCommandAndHandleResult(.home)
            guard didReturnHome else { return }

            try? await Task.sleep(nanoseconds: 420_000_000)
            let didRelaunch = await self.sendCommandAndHandleResult(.launchApp(appID))
            if didRelaunch {
                Haptics.success()
                self.fixMyTVStatusMessage = "Restarted \(appName)."
            }
        }
    }

    func saveWakeMACAddress() {
        do {
            try controller.updateWakeMACAddress(
                wakeMACAddress.trimmingCharacters(in: .whitespacesAndNewlines),
                for: activeDevice?.id
            )
            wakeMACStatusMessage = wakeMACAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Wake MAC removed."
                : "Wake MAC saved for this TV."
            syncWakeMACDraft()
            refreshDiagnostics()
        } catch {
            transientErrorMessage = error.userFacingMessage
            refreshDiagnostics()
        }
    }

    func savePlexMetadataConfiguration() {
        do {
            try controller.updatePlexMetadataConfiguration(
                serverURL: plexMetadataServerURL,
                token: plexMetadataToken
            )
            let configured = controller.plexMetadataConfiguration().isConfigured
            plexMetadataStatusMessage = configured
                ? "Plex metadata connected."
                : "Plex metadata disabled."
            refreshDiagnostics()
        } catch {
            plexMetadataStatusMessage = nil
            transientErrorMessage = error.userFacingMessage
            refreshDiagnostics()
        }
    }

    func clearPlexMetadataConfiguration() {
        plexMetadataServerURL = ""
        plexMetadataToken = ""
        savePlexMetadataConfiguration()
    }

    func setPowerSetupLGConnectAppsEnabled(_ enabled: Bool) {
        powerSetupLGConnectAppsEnabled = enabled
        defaults.set(enabled, forKey: powerSetupLGConnectKey)
    }

    func setPowerSetupMobileTVOnEnabled(_ enabled: Bool) {
        powerSetupMobileTVOnEnabled = enabled
        defaults.set(enabled, forKey: powerSetupMobileTVOnKey)
    }

    func setPowerSetupQuickStartEnabled(_ enabled: Bool) {
        powerSetupQuickStartEnabled = enabled
        defaults.set(enabled, forKey: powerSetupQuickStartKey)
    }

    func launchApp(_ app: TVAppShortcut) {
        guard !isAppLocked(app) else {
            transientErrorMessage = "\(app.title) is locked."
            return
        }
        send(.launchApp(app.appID))
    }

    var canSendVoiceTranscript: Bool {
        supportsControls
            && !isSendingVoiceTranscript
            && !voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleVoiceCapture() {
        if isVoiceListening {
            stopVoiceCapture()
            return
        }

        guard requirePremium(.talkToTV, source: "talk_to_tv") else { return }
        recordGrowthEvent(.voiceSessionStarted)

        Task {
            await startVoiceCapture()
        }
    }

    func clearVoiceTranscript() {
        voiceTranscript = ""
        if !isVoiceListening {
            voiceStatusMessage = "Tap Talk, speak, then send text to TV."
        }
    }

    func sendVoiceTranscriptToTV() {
        if isVoiceListening {
            stopVoiceCapture()
        }

        let text = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            transientErrorMessage = "Say something first, then send it to the TV."
            return
        }

        guard !isSendingVoiceTranscript else { return }
        isSendingVoiceTranscript = true
        voiceStatusMessage = "Sending to TV..."

        Task { [weak self] in
            guard let self else { return }
            let handled = await self.executePlainEnglishCommand(text, fallbackToKeyboard: true)
            if handled {
                self.voiceStatusMessage = "Sent to TV."
            } else if self.voiceStatusMessage == "Sending to TV..." {
                self.voiceStatusMessage = "Could not send. Open a text field on TV and try again."
            }
            self.isSendingVoiceTranscript = false
        }
    }

    func setVolumeSliderEditing(_ isEditing: Bool) {
        isVolumeSliderEditing = isEditing
        guard !isEditing else { return }

        Task { [weak self] in
            await self?.flushPendingVolumeSet()
            self?.scheduleVolumeStateRefresh(after: 0.24)
        }
    }

    func setVolumeLevel(_ proposedLevel: Double) {
        let clamped = max(0, min(100, proposedLevel))
        volumeLevel = clamped

        guard supportsControls else { return }
        let intLevel = Int(clamped.rounded())
        pendingVolumeLevel = intLevel

        volumeSetTask?.cancel()
        volumeSetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.flushPendingVolumeSet()
        }
    }

    func switchInput(_ input: TVInputSource) {
        guard !isInputLocked(input) else {
            transientErrorMessage = "\(input.title) is locked."
            return
        }
        send(.inputSwitch(input.inputID))
    }

    func presentInputPicker() {
        isInputPickerPresented = true
        Task {
            await refreshInputSources()
        }
    }

    func refreshInputSources() async {
        guard supportsInputSwitching else { return }
        let latest = await controller.fetchInputSources()
        if !latest.isEmpty {
            inputSources = latest
        }
    }

    func refreshQuickLaunchApps() async {
        let latest = await controller.fetchLaunchApps()
        let merged = Self.mergeQuickLaunchApps(primary: latest, fallback: TVAppShortcut.lgDefaults)
        guard !merged.isEmpty else { return }
        quickLaunchApps = merged
        syncFavoriteQuickLaunchSelection()
        refreshSceneCopilotContextSuggestions()
    }

    func toggleQuickLaunchFavorite(_ app: TVAppShortcut) {
        if let index = favoriteQuickLaunchIDs.firstIndex(of: app.id) {
            favoriteQuickLaunchIDs.remove(at: index)
        } else {
            favoriteQuickLaunchIDs.append(app.id)
        }
        saveFavoriteQuickLaunchIDs()
    }

    func moveFavoriteQuickLaunches(from source: IndexSet, to destination: Int) {
        favoriteQuickLaunchIDs.move(fromOffsets: source, toOffset: destination)
        saveFavoriteQuickLaunchIDs()
    }

    func presentSmartSceneComposer() {
        if !canCreateAdditionalSmartScene {
            sceneDraftMessage = "Free plan allows one smart scene. Upgrade to Pro for unlimited scenes."
            premiumStatusMessage = "Smart Scenes with multiple presets are part of Pro."
            presentPremiumPaywall(
                source: "smart_scene_count_limit",
                dismissDevicePicker: isDevicePickerPresented
            )
            return
        }

        prepareSceneDraft()
        isSceneComposerPresented = true
    }

    func addSceneDraftAction() {
        guard canAddSceneDraftAction else {
            sceneDraftMessage = "Free plan allows up to two actions per scene."
            premiumStatusMessage = "Unlimited scene actions are part of Pro."
            presentPremiumPaywall(
                source: "smart_scene_action_limit",
                dismissDevicePicker: isDevicePickerPresented
            )
            return
        }

        let kind: TVSceneActionKind = .home
        sceneDraftActions.append(
            TVSceneAction(
                kind: kind,
                payload: defaultPayload(for: kind)
            )
        )
    }

    func updateSceneDraftActionKind(_ actionID: UUID, kind: TVSceneActionKind) {
        guard let index = sceneDraftActions.firstIndex(where: { $0.id == actionID }) else { return }
        sceneDraftActions[index].kind = kind
        if kind.requiresPayload {
            if sceneDraftActions[index].payload?.isEmpty != false {
                sceneDraftActions[index].payload = defaultPayload(for: kind)
            }
        } else {
            sceneDraftActions[index].payload = nil
        }
    }

    func updateSceneDraftActionPayload(_ actionID: UUID, payload: String) {
        guard let index = sceneDraftActions.firstIndex(where: { $0.id == actionID }) else { return }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        sceneDraftActions[index].payload = trimmed.isEmpty ? nil : trimmed
    }

    func removeSceneDraftAction(_ actionID: UUID) {
        sceneDraftActions.removeAll { $0.id == actionID }
    }

    func saveSmartSceneFromDraft() {
        let sceneName = sceneDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sceneName.isEmpty else {
            sceneDraftMessage = "Enter a name for this scene."
            return
        }

        guard !sceneDraftActions.isEmpty else {
            sceneDraftMessage = "Add at least one action."
            return
        }

        if !canCreateAdditionalSmartScene {
            sceneDraftMessage = "Free plan allows one smart scene."
            presentPremiumPaywall(
                source: "smart_scene_count_limit",
                dismissDevicePicker: isDevicePickerPresented
            )
            return
        }

        if !hasSmartScenesProAccess, sceneDraftActions.count > freeSmartSceneActionLimit {
            sceneDraftMessage = "Free plan allows up to two actions per scene."
            presentPremiumPaywall(
                source: "smart_scene_action_limit",
                dismissDevicePicker: isDevicePickerPresented
            )
            return
        }

        let sanitizedActions = sceneDraftActions.compactMap { action -> TVSceneAction? in
            if action.kind.requiresPayload,
               action.payload?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                return nil
            }
            return TVSceneAction(
                id: action.id,
                kind: action.kind,
                payload: action.payload
            )
        }

        guard !sanitizedActions.isEmpty else {
            sceneDraftMessage = "Some actions are missing values. Complete each payload."
            return
        }

        let icon = sceneIconChoices.contains(sceneDraftIconSystemName)
            ? sceneDraftIconSystemName
            : "sparkles.tv.fill"

        smartScenes.append(
            TVSmartScene(
                name: sceneName,
                iconSystemName: icon,
                actions: sanitizedActions
            )
        )
        saveSmartScenes()
        syncVoiceMacroDraftSceneSelection()
        rebuildAIMacroRecommendations()
        isSceneComposerPresented = false
        sceneStatusMessage = "Saved smart scene: \(sceneName)"
        sceneDraftMessage = nil
        recordGrowthEvent(
            .automationCreated,
            metadata: [
                "action": "smart_scene",
                "steps": "\(sanitizedActions.count)"
            ]
        )
    }

    func runSmartScene(_ scene: TVSmartScene) {
        Task { [weak self] in
            guard let self else { return }
            let success = await self.executeSmartScene(scene)
            if success {
                self.recordAIPatternUsage(
                    actions: scene.actions,
                    sceneName: scene.name,
                    iconSystemName: scene.iconSystemName,
                    fallbackPhrase: "run \(scene.name.lowercased())"
                )
            }
        }
    }

    func removeSmartScene(_ sceneID: UUID) {
        smartScenes.removeAll { $0.id == sceneID }
        voiceMacros.removeAll { $0.sceneID == sceneID }
        saveSmartScenes()
        saveVoiceMacros()
        syncVoiceMacroDraftSceneSelection()
        rebuildAIMacroRecommendations()
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            premiumBillingService.start()
            startAutomationTimerIfNeeded()
            startReliabilityWatchdogIfNeeded()
            startNowPlayingPollingIfNeeded()
            controller.startDiscovery()
            beginDiscoveryReliabilityAttempt(source: "foreground")
            Task {
                await syncPremiumEntitlements()
                await controller.reconnectToLastDeviceIfPossible()
                await refreshVolumeState()
                await refreshQuickLaunchApps()
                await refreshNowPlayingState()
                refreshDiagnostics()
                evaluateAutomationsIfNeeded()
            }
        case .background:
            stopVoiceCapture(keepStatus: false)
            automationTimer?.invalidate()
            automationTimer = nil
            stopReliabilityWatchdog()
            stopNowPlayingPolling(clearState: false)
            break
        case .inactive:
            stopVoiceCapture(keepStatus: false)
            stopReliabilityWatchdog()
            stopNowPlayingPolling(clearState: false)
            break
        @unknown default:
            break
        }
    }

    func clearTransientError() {
        transientErrorMessage = nil
    }

    func clearWatchingHistory() {
        nowWatchingHistory = []
        defaults.removeObject(forKey: watchingHistoryKey)
    }

    func currentNowPlayingManualTitleDraft() -> String {
        guard let state = nowPlayingState else { return "" }
        if let override = manualNowPlayingTitleOverride(for: state) {
            return override
        }
        return state.title ?? ""
    }

    func saveManualNowPlayingTitle(_ rawTitle: String) {
        guard let state = nowPlayingState else { return }
        guard let key = manualNowPlayingKey(for: state) else { return }

        let sanitized = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized = sanitized.nonEmpty {
            manualNowPlayingTitlesByKey[key] = normalized
        } else {
            manualNowPlayingTitlesByKey.removeValue(forKey: key)
        }

        saveManualNowPlayingTitles()
        recordWatchingHistoryIfNeeded(for: resolvedNowPlayingState(state))
        refreshSceneCopilotContextSuggestions()
    }

    func clearManualNowPlayingTitleOverride() {
        guard let state = nowPlayingState else { return }
        guard let key = manualNowPlayingKey(for: state) else { return }
        guard manualNowPlayingTitlesByKey.removeValue(forKey: key) != nil else { return }

        saveManualNowPlayingTitles()
        recordWatchingHistoryIfNeeded(for: resolvedNowPlayingState(state))
        refreshSceneCopilotContextSuggestions()
    }

    func watchingHistoryHeadline(for entry: TVWatchHistoryEntry) -> String {
        if let title = entry.title, !title.isEmpty {
            return title
        }
        return entry.appName
    }

    func watchingHistoryDetail(for entry: TVWatchHistoryEntry) -> String {
        var parts: [String] = []
        if entry.title != nil {
            parts.append(entry.appName)
        }
        if let subtitle = entry.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        parts.append(entry.source.label)
        parts.append(entry.confidence.shortLabel)
        return parts.joined(separator: " • ")
    }

    func watchingHistoryTimestampLabel(for entry: TVWatchHistoryEntry) -> String {
        Self.relativeTimeFormatter.localizedString(for: entry.capturedAt, relativeTo: Date())
    }

    private func bindController() {
        controller.onDevicesChanged = { [weak self] devices in
            guard let self else { return }
            self.discoveredDevices = devices
            if !devices.isEmpty {
                self.completeDiscoveryReliabilityAttempt(success: true)
            }
            self.refreshDiagnostics()
        }
        controller.onKnownDevicesChanged = { [weak self] devices in
            guard let self else { return }
            self.knownDevices = devices
            self.syncWakeMACDraft()
            self.refreshDiagnostics()
        }
        controller.onStateChanged = { [weak self] state in
            guard let self else { return }

            self.connectionState = state
            self.syncWakeMACDraft()
            self.refreshDiagnostics()

            switch state {
            case .reconnecting:
                if !self.isFixWorkflowRunning {
                    self.recordGrowthEvent(
                        .connectAttempt,
                        metadata: [
                            "mode": "auto_reconnect"
                        ]
                    )
                    self.isAutoReconnectTrackingActive = true
                }
            case .connected:
                self.wakeReconnectTask?.cancel()
                self.wakeReconnectTask = nil
                self.isWakeReconnectInProgress = false
                if self.isAutoReconnectTrackingActive {
                    self.recordReliability(.autoReconnect, success: true)
                    self.recordGrowthEvent(
                        .connectResult,
                        metadata: [
                            "mode": "auto_reconnect",
                            "success": "1"
                        ]
                    )
                    self.isAutoReconnectTrackingActive = false
                }
            case .failed:
                if self.isDiscoveryAttemptInFlight && self.discoveredDevices.isEmpty {
                    self.completeDiscoveryReliabilityAttempt(success: false)
                }
                if self.isAutoReconnectTrackingActive {
                    self.recordReliability(.autoReconnect, success: false)
                    self.recordGrowthEvent(
                        .connectResult,
                        metadata: [
                            "mode": "auto_reconnect",
                            "success": "0",
                            "error": Self.analyticsSafe(state.shortLabel)
                        ]
                    )
                    self.isAutoReconnectTrackingActive = false
                }
            case .idle:
                self.wakeReconnectTask?.cancel()
                self.wakeReconnectTask = nil
                self.isWakeReconnectInProgress = false
                self.isAutoReconnectTrackingActive = false
            default:
                break
            }

            guard state.isConnected else {
                self.consecutiveHealthCheckFailures = 0
                self.sceneCopilotContextSuggestions = []
                self.stopNowPlayingPolling(clearState: true)
                self.stopVoiceCapture(keepStatus: false)
                return
            }

            self.startNowPlayingPollingIfNeeded()
            Task { [weak self] in
                await self?.refreshInputSources()
                await self?.refreshVolumeState()
                await self?.refreshQuickLaunchApps()
                await self?.refreshNowPlayingState()
            }
        }
    }

    private func refreshVolumeState() async {
        guard supportsControls else { return }
        guard let volume = await controller.fetchVolumeState() else { return }
        isMuted = volume.isMuted
        if !isVolumeSliderEditing {
            volumeLevel = Double(volume.level)
        }
        refreshSceneCopilotContextSuggestions()
    }

    private func refreshNowPlayingState() async {
        guard supportsControls else {
            nowPlayingState = nil
            sceneCopilotContextSuggestions = []
            return
        }

        if let latest = await controller.fetchNowPlayingState() {
            nowPlayingState = latest
            recordWatchingHistoryIfNeeded(for: resolvedNowPlayingState(latest))
        }
        refreshSceneCopilotContextSuggestions()
    }

    private func startVoiceCapture() async {
        guard supportsControls else {
            transientErrorMessage = TVControllerError.notConnected.localizedDescription
            return
        }

        guard await hasSpeechAndMicPermissions() else {
            transientErrorMessage = "Enable Microphone and Speech Recognition permissions for Pulse Remote in Settings."
            return
        }

        guard let recognizer = speechRecognizer ?? SFSpeechRecognizer(locale: Locale.current) else {
            transientErrorMessage = "Voice recognition is not available for your current language."
            return
        }

        guard recognizer.isAvailable else {
            transientErrorMessage = "Speech recognition is currently unavailable. Try again in a moment."
            return
        }

        speechRecognizer = recognizer
        stopVoiceCapture(keepStatus: false)

        do {
            try configureAudioSessionForRecording()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            speechRecognitionRequest = request

            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) {
                [weak self] buffer, _ in
                self?.speechRecognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isVoiceListening = true
            voiceStatusMessage = "Listening..."
            if voiceTranscript.isEmpty {
                voiceTranscript = ""
            }

            speechRecognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.voiceTranscript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.stopVoiceCapture(keepStatus: true)
                            self.voiceStatusMessage = "Voice captured. Tap Send to TV."
                        }
                    }
                }

                if let error {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.stopVoiceCapture(keepStatus: true)
                        self.voiceStatusMessage = "Voice stopped: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            stopVoiceCapture(keepStatus: false)
            transientErrorMessage = "Could not start microphone: \(error.localizedDescription)"
        }
    }

    private func stopVoiceCapture(keepStatus: Bool = true) {
        speechRecognitionTask?.cancel()
        speechRecognitionTask = nil

        speechRecognitionRequest?.endAudio()
        speechRecognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isVoiceListening = false

        if !keepStatus {
            voiceStatusMessage = "Tap Talk, speak, then send text to TV."
        }
    }

    private func hasSpeechAndMicPermissions() async -> Bool {
        let speechStatus = await requestSpeechPermissionIfNeeded()
        guard speechStatus == .authorized else {
            return false
        }

        let micAllowed = await requestMicrophonePermission()
        return micAllowed
    }

    private func requestSpeechPermissionIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined {
            return current
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func configureAudioSessionForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func flushPendingVolumeSet() async {
        guard supportsControls else { return }
        guard let target = pendingVolumeLevel else { return }
        pendingVolumeLevel = nil

        do {
            try await controller.send(command: .setVolume(target))
        } catch {
            transientErrorMessage = error.userFacingMessage
        }
    }

    private func scheduleVolumeStateRefresh(after seconds: TimeInterval) {
        guard supportsControls else { return }

        volumeRefreshTask?.cancel()
        volumeRefreshTask = Task { [weak self] in
            guard let self else { return }
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self.refreshVolumeState()
        }
    }

    private func syncWakeMACDraft() {
        if let active = activeDevice, let mac = active.wakeMACAddress, !mac.isEmpty {
            wakeMACAddress = mac
            return
        }

        if let knownMatch = knownDevices.first(where: { $0.id == activeDevice?.id }),
           let mac = knownMatch.wakeMACAddress,
           !mac.isEmpty {
            wakeMACAddress = mac
            return
        }

        if let firstKnownMAC = knownDevices.compactMap(\.wakeMACAddress).first(where: { !$0.isEmpty }) {
            wakeMACAddress = firstKnownMAC
        } else {
            wakeMACAddress = ""
        }
    }

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.updateNetworkStatusText(path: path)
                self?.refreshDiagnostics()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
        updateNetworkStatusText(path: pathMonitor.currentPath)
    }

    private func updateNetworkStatusText(path: NWPath) {
        guard path.status == .satisfied else {
            isWiFiReadyForTVControl = false
            networkStatusText = "Wi-Fi not connected. Connect iPhone and TV to the same network."
            return
        }

        if !path.usesInterfaceType(.wifi) {
            isWiFiReadyForTVControl = false
            networkStatusText = "Network is active, but Wi-Fi is not the active interface."
            return
        }

        if let localIP = Self.wifiIPv4Address() {
            isWiFiReadyForTVControl = true
            networkStatusText = "Wi-Fi connected (\(localIP))."
        } else {
            isWiFiReadyForTVControl = false
            networkStatusText = "Wi-Fi connected, but no local IPv4 was detected."
        }
    }

    private func loadWatchingHistory() {
        guard let data = defaults.data(forKey: watchingHistoryKey) else {
            nowWatchingHistory = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([TVWatchHistoryEntry].self, from: data)
            nowWatchingHistory = decoded.sorted { $0.capturedAt > $1.capturedAt }
        } catch {
            nowWatchingHistory = []
        }
    }

    private func saveWatchingHistory() {
        do {
            let data = try JSONEncoder().encode(nowWatchingHistory)
            defaults.set(data, forKey: watchingHistoryKey)
        } catch {
            // Keep the feature resilient if persistence fails.
        }
    }

    private func loadManualNowPlayingTitles() {
        guard let stored = defaults.dictionary(forKey: manualNowPlayingTitlesKey) as? [String: String] else {
            manualNowPlayingTitlesByKey = [:]
            return
        }

        var sanitized: [String: String] = [:]
        for (key, value) in stored {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { continue }
            sanitized[normalizedKey] = normalizedValue
        }
        manualNowPlayingTitlesByKey = sanitized
    }

    private func saveManualNowPlayingTitles() {
        if manualNowPlayingTitlesByKey.isEmpty {
            defaults.removeObject(forKey: manualNowPlayingTitlesKey)
            return
        }
        defaults.set(manualNowPlayingTitlesByKey, forKey: manualNowPlayingTitlesKey)
    }

    private func manualNowPlayingTitleOverride(for state: TVNowPlayingState) -> String? {
        guard let key = manualNowPlayingKey(for: state) else { return nil }
        return manualNowPlayingTitlesByKey[key]
    }

    private func manualNowPlayingKey(for state: TVNowPlayingState) -> String? {
        if let appID = state.appID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            return "id:\(appID.lowercased())"
        }

        let normalizedName = state.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty else { return nil }
        return "name:\(normalizedName)"
    }

    private func resolvedNowPlayingState(_ state: TVNowPlayingState) -> TVNowPlayingState {
        guard let manualTitle = manualNowPlayingTitleOverride(for: state) else { return state }

        return TVNowPlayingState(
            appName: state.appName,
            appID: state.appID,
            title: manualTitle,
            subtitle: state.subtitle,
            source: state.source,
            confidence: state.confidence,
            metadataRestrictionReason: state.metadataRestrictionReason
        )
    }

    private func loadSmartScenes() {
        guard let data = defaults.data(forKey: smartScenesKey) else {
            smartScenes = []
            syncVoiceMacroDraftSceneSelection()
            rebuildAIMacroRecommendations()
            return
        }

        do {
            let decoded = try JSONDecoder().decode([TVSmartScene].self, from: data)
            smartScenes = decoded.filter { scene in
                !scene.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !scene.actions.isEmpty
            }
            syncVoiceMacroDraftSceneSelection()
            rebuildAIMacroRecommendations()
        } catch {
            smartScenes = []
            syncVoiceMacroDraftSceneSelection()
            rebuildAIMacroRecommendations()
        }
    }

    private func saveSmartScenes() {
        do {
            let data = try JSONEncoder().encode(smartScenes)
            defaults.set(data, forKey: smartScenesKey)
        } catch {
            sceneStatusMessage = "Could not save smart scenes."
        }
    }

    private func loadVoiceMacros() {
        guard let data = defaults.data(forKey: voiceMacrosKey) else {
            voiceMacros = []
            syncVoiceMacroDraftSceneSelection()
            rebuildAIMacroRecommendations()
            return
        }

        do {
            let decoded = try JSONDecoder().decode([TVVoiceMacro].self, from: data)
            let validSceneIDs = Set(smartScenes.map(\.id))
            voiceMacros = decoded.filter { macro in
                !normalizeMacroPhrase(macro.phrase).isEmpty && validSceneIDs.contains(macro.sceneID)
            }
            syncVoiceMacroDraftSceneSelection()
            rebuildAIMacroRecommendations()
        } catch {
            voiceMacros = []
            syncVoiceMacroDraftSceneSelection()
            rebuildAIMacroRecommendations()
        }
    }

    private func saveVoiceMacros() {
        do {
            let data = try JSONEncoder().encode(voiceMacros)
            defaults.set(data, forKey: voiceMacrosKey)
        } catch {
            voiceMacroStatusMessage = "Could not save voice macros."
        }
    }

    private func loadAILearningMode() {
        guard let raw = defaults.string(forKey: aiLearningModeKey),
              let mode = TVAILearningMode(rawValue: raw) else {
            aiLearningMode = .balanced
            return
        }
        aiLearningMode = mode
    }

    private func loadAIPatternStats() {
        guard let data = defaults.data(forKey: aiPatternStatsKey) else {
            aiPatternStats = [:]
            return
        }

        do {
            let decoded = try JSONDecoder().decode([String: AIPatternStat].self, from: data)
            aiPatternStats = decoded.filter { _, stat in
                !stat.actions.isEmpty && !stat.sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            trimAIPatternStats(maxEntries: 60)
        } catch {
            aiPatternStats = [:]
        }
    }

    private func saveAIPatternStats() {
        do {
            let data = try JSONEncoder().encode(aiPatternStats)
            defaults.set(data, forKey: aiPatternStatsKey)
        } catch {
            // Best-effort persistence only.
        }
    }

    private func syncVoiceMacroDraftSceneSelection() {
        if let selected = voiceMacroDraftSceneID,
           smartScenes.contains(where: { $0.id == selected }) {
            return
        }
        voiceMacroDraftSceneID = smartScenes.first?.id
    }

    private func recordWatchingHistoryIfNeeded(for nowPlaying: TVNowPlayingState) {
        let normalizedAppName = nowPlaying.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAppName.isEmpty else { return }

        let normalizedTitle = nowPlaying.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let normalizedSubtitle = nowPlaying.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty

        if let latest = nowWatchingHistory.first,
           latest.matches(
            appName: normalizedAppName,
            title: normalizedTitle,
            subtitle: normalizedSubtitle,
            source: nowPlaying.source
           ) {
            if latest.confidence != nowPlaying.confidence {
                nowWatchingHistory[0] = TVWatchHistoryEntry(
                    id: latest.id,
                    capturedAt: latest.capturedAt,
                    appName: latest.appName,
                    title: latest.title,
                    subtitle: latest.subtitle,
                    source: latest.source,
                    confidence: nowPlaying.confidence
                )
                saveWatchingHistory()
            }
            return
        }

        let entry = TVWatchHistoryEntry(
            appName: normalizedAppName,
            title: normalizedTitle,
            subtitle: normalizedSubtitle,
            source: nowPlaying.source,
            confidence: nowPlaying.confidence
        )
        nowWatchingHistory.insert(entry, at: 0)
        if nowWatchingHistory.count > 40 {
            nowWatchingHistory = Array(nowWatchingHistory.prefix(40))
        }
        saveWatchingHistory()
    }

    private func loadPowerSetupChecklistState() {
        powerSetupLGConnectAppsEnabled = defaults.bool(forKey: powerSetupLGConnectKey)
        powerSetupMobileTVOnEnabled = defaults.bool(forKey: powerSetupMobileTVOnKey)
        powerSetupQuickStartEnabled = defaults.bool(forKey: powerSetupQuickStartKey)
    }

    private func loadAdvancedSettingsState() {
        isAdvancedSettingsVisible = defaults.bool(forKey: advancedSettingsVisibleKey)
    }

    private func syncPlexMetadataDraft() {
        let configuration = controller.plexMetadataConfiguration()
        plexMetadataServerURL = configuration.serverURL
        plexMetadataToken = configuration.token
    }

    private func loadLockAndCaregiverState() {
        isAppInputLockEnabled = defaults.bool(forKey: appInputLockEnabledKey)
        isCaregiverModeEnabled = defaults.bool(forKey: caregiverModeKey)

        let storedApps = defaults.array(forKey: lockedAppIDsKey) as? [String] ?? []
        let storedInputs = defaults.array(forKey: lockedInputIDsKey) as? [String] ?? []
        lockedAppIDs = Set(storedApps.map { $0.lowercased() })
        lockedInputIDs = Set(storedInputs.map { $0.lowercased() })
    }

    private func loadAutomationRules() {
        guard let data = defaults.data(forKey: automationRulesKey) else {
            automationRules = []
            return
        }

        do {
            automationRules = try JSONDecoder().decode([TVAutomationRule].self, from: data).map { rule in
                var sanitized = rule
                if sanitized.weekdays.isEmpty {
                    sanitized.weekdays = [1, 2, 3, 4, 5, 6, 7]
                }
                return sanitized
            }
        } catch {
            automationRules = []
        }
    }

    private func saveAutomationRules() {
        do {
            let data = try JSONEncoder().encode(automationRules)
            defaults.set(data, forKey: automationRulesKey)
        } catch {
            automationStatusMessage = "Could not save automations."
        }
    }

    private func addAutomationRule(_ rule: TVAutomationRule) {
        automationRules.append(rule)
        automationRules.sort {
            if $0.hour != $1.hour { return $0.hour < $1.hour }
            if $0.minute != $1.minute { return $0.minute < $1.minute }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        saveAutomationRules()
        automationStatusMessage = "Added automation: \(rule.name)"
        recordGrowthEvent(
            .automationCreated,
            metadata: [
                "action": rule.action.rawValue
            ]
        )
    }

    private func prepareAutomationDraft() {
        automationDraftMessage = nil
        automationDraftName = "Weekday Power On"
        automationDraftAction = .powerOn

        var defaultTimeComponents = DateComponents()
        defaultTimeComponents.hour = 7
        defaultTimeComponents.minute = 0
        automationDraftTime = Calendar.current.date(from: defaultTimeComponents) ?? Date()

        automationDraftSelectedWeekdays = [2, 3, 4, 5, 6]
        automationDraftPayload = ""
    }

    private func prepareSceneDraft() {
        sceneDraftMessage = nil
        sceneDraftName = "TV Night"
        sceneDraftIconSystemName = "sparkles.tv.fill"

        if let app = quickLaunchApps.first {
            sceneDraftActions = [
                TVSceneAction(kind: .powerOn),
                TVSceneAction(kind: .launchApp, payload: app.appID)
            ]
        } else {
            sceneDraftActions = [
                TVSceneAction(kind: .powerOn),
                TVSceneAction(kind: .home)
            ]
        }

        if !hasSmartScenesProAccess, sceneDraftActions.count > freeSmartSceneActionLimit {
            sceneDraftActions = Array(sceneDraftActions.prefix(freeSmartSceneActionLimit))
        }
    }

    private func defaultPayload(for kind: TVSceneActionKind) -> String? {
        switch kind {
        case .setVolume:
            return "20"
        case .launchApp:
            return availableAutomationLaunchApps.first?.appID
        case .switchInput:
            return availableAutomationInputs.first?.inputID
        default:
            return nil
        }
    }

    private func command(for action: TVSceneAction) -> TVCommand? {
        switch action.kind {
        case .powerOn:
            return .powerOn
        case .powerOff:
            return .powerOff
        case .home:
            return .home
        case .back:
            return .back
        case .muteOn:
            return .mute(true)
        case .muteOff:
            return .mute(false)
        case .volumeUp:
            return .volumeUp
        case .volumeDown:
            return .volumeDown
        case .setVolume:
            guard let payload = action.payload,
                  let level = Int(payload),
                  (0...100).contains(level) else {
                return nil
            }
            return .setVolume(level)
        case .launchApp:
            guard let payload = action.payload, !payload.isEmpty else {
                return nil
            }
            return .launchApp(payload)
        case .switchInput:
            guard let payload = action.payload, !payload.isEmpty else {
                return nil
            }
            return .inputSwitch(payload)
        }
    }

    @discardableResult
    private func executeSmartScene(
        _ scene: TVSmartScene,
        source: String = "manual",
        triggeredPhrase: String? = nil
    ) async -> Bool {
        guard !scene.actions.isEmpty else {
            sceneStatusMessage = "This scene has no actions."
            return false
        }

        sceneStatusMessage = "Running \(scene.name)..."
        if source == "voice_macro", let triggeredPhrase {
            voiceMacroStatusMessage = "Running \"\(triggeredPhrase)\"..."
        }

        if !supportsControls {
            sceneStatusMessage = "Reconnecting before scene..."
            await controller.reconnectToLastDeviceIfPossible()
            refreshDiagnostics()
            if supportsControls {
                sceneStatusMessage = "Running \(scene.name)..."
            }
        }

        for (index, action) in scene.actions.enumerated() {
            guard let command = command(for: action) else {
                sceneStatusMessage = "Scene has an invalid step: \(action.kind.title)."
                if source == "voice_macro" {
                    voiceMacroStatusMessage = "Macro stopped at step \(index + 1)."
                }
                return false
            }

            let success = await sendCommandAndHandleResult(command)
            if !success {
                sceneStatusMessage = "Scene stopped at step \(index + 1): \(action.kind.title)."
                if source == "voice_macro" {
                    voiceMacroStatusMessage = "Macro stopped at step \(index + 1)."
                }
                return false
            }

            if index < scene.actions.count - 1 {
                try? await Task.sleep(nanoseconds: 160_000_000)
            }
        }

        if let sceneIndex = smartScenes.firstIndex(where: { $0.id == scene.id }) {
            smartScenes[sceneIndex].lastRunAt = Date()
        }
        saveSmartScenes()
        sceneStatusMessage = "Scene complete: \(scene.name)."
        Haptics.success()
        return true
    }

    private func normalizeMacroPhrase(_ phrase: String) -> String {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        return trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
    }

    private func matchedVoiceMacro(in input: String) -> TVVoiceMacro? {
        let normalizedInput = normalizeMacroPhrase(input)
        guard !normalizedInput.isEmpty else { return nil }

        let candidates = voiceMacros.sorted {
            normalizeMacroPhrase($0.phrase).count > normalizeMacroPhrase($1.phrase).count
        }

        for macro in candidates {
            let phrase = normalizeMacroPhrase(macro.phrase)
            guard !phrase.isEmpty else { continue }
            if normalizedInput == phrase
                || normalizedInput.contains("run \(phrase)")
                || normalizedInput.contains("macro \(phrase)")
                || normalizedInput.contains("scene \(phrase)") {
                return macro
            }
        }
        return nil
    }

    private func markVoiceMacroUsed(_ macroID: UUID) {
        guard let index = voiceMacros.firstIndex(where: { $0.id == macroID }) else { return }
        voiceMacros[index].lastUsedAt = Date()
        saveVoiceMacros()
    }

    private func buildCopilotSuggestions(from prompt: String) -> [TVAICopilotSuggestion] {
        let normalized = prompt
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = draftSmartSceneFromCopilot(prompt: prompt) else { return [] }

        var suggestions: [TVAICopilotSuggestion] = []

        suggestions.append(
            TVAICopilotSuggestion(
                name: base.name,
                iconSystemName: base.iconSystemName,
                actions: base.actions,
                confidence: copilotConfidence(for: base.actions, normalizedPrompt: normalized),
                rationale: "Best match for your wording."
            )
        )

        var quickActions = base.actions
        let hasLaunchOrInput = quickActions.contains(where: { $0.kind == .launchApp || $0.kind == .switchInput })
        let hasPowerOn = quickActions.contains { $0.kind == .powerOn }
        if hasLaunchOrInput && !hasPowerOn {
            quickActions.insert(TVSceneAction(kind: .powerOn), at: 0)
        }
        if !quickActions.contains(where: { $0.kind == .setVolume }) {
            if normalized.contains("movie") || normalized.contains("film") || normalized.contains("quiet") {
                quickActions.append(TVSceneAction(kind: .setVolume, payload: "18"))
            } else if normalized.contains("sports") || normalized.contains("game") {
                quickActions.append(TVSceneAction(kind: .setVolume, payload: "30"))
            }
        }
        quickActions = compactDuplicateActions(quickActions)
        if quickActions != base.actions {
            suggestions.append(
                TVAICopilotSuggestion(
                    name: "\(base.name) Smart Start",
                    iconSystemName: base.iconSystemName,
                    actions: quickActions,
                    confidence: .medium,
                    rationale: "Adds startup reliability and balanced volume."
                )
            )
        }

        var quietActions = base.actions.filter { action in
            action.kind != .volumeUp && action.kind != .volumeDown
        }
        if let index = quietActions.firstIndex(where: { $0.kind == .setVolume }) {
            quietActions[index] = TVSceneAction(kind: .setVolume, payload: "12")
        } else {
            quietActions.append(TVSceneAction(kind: .setVolume, payload: "12"))
        }
        if !quietActions.contains(where: { $0.kind == .muteOff }) {
            quietActions.append(TVSceneAction(kind: .muteOff))
        }
        quietActions = compactDuplicateActions(quietActions)
        if quietActions != base.actions {
            suggestions.append(
                TVAICopilotSuggestion(
                    name: "\(base.name) Quiet",
                    iconSystemName: "moon.stars.fill",
                    actions: quietActions,
                    confidence: .medium,
                    rationale: "Lower volume profile for late-night or shared spaces."
                )
            )
        }

        var uniqueByPlan = Set<String>()
        let unique = suggestions.filter { suggestion in
            let key = suggestion.actions.map {
                "\($0.kind.rawValue)|\(($0.payload ?? "").lowercased())"
            }.joined(separator: "->")
            return uniqueByPlan.insert(key).inserted
        }

        return Array(unique.prefix(3))
    }

    private func copilotConfidence(
        for actions: [TVSceneAction],
        normalizedPrompt: String
    ) -> TVAICopilotConfidence {
        let hasAppOrInput = actions.contains { $0.kind == .launchApp || $0.kind == .switchInput }
        let hasVolume = actions.contains { $0.kind == .setVolume || $0.kind == .volumeUp || $0.kind == .volumeDown }
        let hasPower = actions.contains { $0.kind == .powerOn || $0.kind == .powerOff }

        if hasAppOrInput && (hasVolume || hasPower) {
            return .high
        }
        if actions.count >= 2 || normalizedPrompt.contains("hdmi") || normalizedPrompt.contains("youtube") {
            return .medium
        }
        return .low
    }

    private func compactDuplicateActions(_ actions: [TVSceneAction]) -> [TVSceneAction] {
        actions.reduce(into: [TVSceneAction]()) { result, action in
            if result.last?.kind == action.kind && result.last?.payload == action.payload {
                return
            }
            result.append(action)
        }
    }

    private func uniqueSmartSceneName(base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = trimmed.isEmpty ? "AI Scene" : trimmed
        let existingNames = Set(smartScenes.map { $0.name.lowercased() })
        guard !existingNames.contains(seed.lowercased()) else {
            for index in 2...50 {
                let candidate = "\(seed) \(index)"
                if !existingNames.contains(candidate.lowercased()) {
                    return candidate
                }
            }
            return "\(seed) \(Int(Date().timeIntervalSince1970))"
        }
        return seed
    }

    private func refreshSceneCopilotContextSuggestions() {
        guard supportsControls else {
            sceneCopilotContextSuggestions = []
            return
        }

        var suggestions: [TVAICopilotSuggestion] = []

        if let nowPlayingState,
           let appID = nowPlayingState.appID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appID.isEmpty {
            suggestions.append(
                TVAICopilotSuggestion(
                    name: "Resume \(nowPlayingState.appName)",
                    iconSystemName: "play.rectangle.fill",
                    actions: [
                        TVSceneAction(kind: .launchApp, payload: appID)
                    ],
                    confidence: nowPlayingState.confidence == .high ? .high : .medium,
                    rationale: "Uses your live now-watching signal."
                )
            )
        }

        if supportsVolumeControls {
            if isMuted {
                suggestions.append(
                    TVAICopilotSuggestion(
                        name: "Unmute + 18%",
                        iconSystemName: "speaker.wave.2.fill",
                        actions: [
                            TVSceneAction(kind: .muteOff),
                            TVSceneAction(kind: .setVolume, payload: "18")
                        ],
                        confidence: .high,
                        rationale: "Fast recovery when audio is muted."
                    )
                )
            }

            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 22 || hour < 6 {
                suggestions.append(
                    TVAICopilotSuggestion(
                        name: "Quiet Night",
                        iconSystemName: "moon.stars.fill",
                        actions: [
                            TVSceneAction(kind: .setVolume, payload: "12"),
                            TVSceneAction(kind: .muteOff)
                        ],
                        confidence: .medium,
                        rationale: "Time-aware low-volume profile."
                    )
                )
            }
        }

        if let score = reliabilitySnapshot.overallScore, score < 82 {
            var stabilizeActions: [TVSceneAction] = []
            if activeCapabilities.contains(.home) {
                stabilizeActions.append(TVSceneAction(kind: .home))
            }
            if let nowPlayingState,
               let appID = nowPlayingState.appID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !appID.isEmpty {
                stabilizeActions.append(TVSceneAction(kind: .launchApp, payload: appID))
            }
            stabilizeActions = compactDuplicateActions(stabilizeActions)
            if !stabilizeActions.isEmpty {
                suggestions.append(
                    TVAICopilotSuggestion(
                        name: "Stability Reset",
                        iconSystemName: "shield.checkered",
                        actions: stabilizeActions,
                        confidence: .medium,
                        rationale: "Suggested because reliability is \(score)%."
                    )
                )
            }
        }

        var seenSignatures = Set<String>()
        let filtered = suggestions.filter { suggestion in
            guard !suggestion.actions.isEmpty else { return false }
            guard suggestion.actions.allSatisfy(isSceneActionSupported) else { return false }
            let signature = actionSignature(for: suggestion.actions)
            return seenSignatures.insert(signature).inserted
        }

        sceneCopilotContextSuggestions = Array(filtered.prefix(3))
    }

    private func isSceneActionSupported(_ action: TVSceneAction) -> Bool {
        guard let command = command(for: action) else { return false }
        guard let required = requiredCapability(for: command) else { return true }
        return activeCapabilities.contains(required)
    }

    private func trackAIPatternUsage(from parsed: ParsedPlainCommand, spokenCommand: String) {
        guard aiLearningMode != .off else { return }
        let trimmedPhrase = spokenCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let phrase = trimmedPhrase

        switch parsed {
        case let .command(command):
            guard let action = sceneAction(from: command) else { return }
            let descriptor = sceneDescriptor(for: command)
            recordAIPatternUsage(
                actions: [action],
                sceneName: descriptor.name,
                iconSystemName: descriptor.iconSystemName,
                fallbackPhrase: phrase.isEmpty ? descriptor.name.lowercased() : phrase
            )
        case let .launchApp(app):
            recordAIPatternUsage(
                actions: [TVSceneAction(kind: .launchApp, payload: app.appID)],
                sceneName: "Open \(app.title)",
                iconSystemName: app.iconSystemName,
                fallbackPhrase: phrase.isEmpty ? "open \(app.title.lowercased())" : phrase
            )
        case let .switchInput(input):
            recordAIPatternUsage(
                actions: [TVSceneAction(kind: .switchInput, payload: input.inputID)],
                sceneName: "Switch \(input.title)",
                iconSystemName: input.iconSystemName,
                fallbackPhrase: phrase.isEmpty ? "switch \(input.title.lowercased())" : phrase
            )
        }
    }

    private func recordAIPatternUsage(
        actions: [TVSceneAction],
        sceneName: String,
        iconSystemName: String,
        fallbackPhrase: String
    ) {
        guard aiLearningMode != .off else { return }
        let compactActions = compactDuplicateActions(actions)
        guard !compactActions.isEmpty else { return }

        let signature = actionSignature(for: compactActions)
        var stat = aiPatternStats[signature] ?? AIPatternStat(
            signature: signature,
            samplePhrase: normalizeMacroPhrase(fallbackPhrase),
            sceneName: sceneName,
            iconSystemName: iconSystemName,
            actions: compactActions,
            useCount: 0,
            lastUsedAt: Date()
        )

        stat.useCount += 1
        stat.lastUsedAt = Date()
        stat.actions = compactActions
        stat.sceneName = sceneName
        stat.iconSystemName = iconSystemName

        let normalizedPhrase = normalizeMacroPhrase(fallbackPhrase)
        if !normalizedPhrase.isEmpty {
            stat.samplePhrase = normalizedPhrase
        } else if stat.samplePhrase.isEmpty {
            stat.samplePhrase = "run \(sceneName.lowercased())"
        }

        aiPatternStats[signature] = stat
        dismissedAIPatternSignatures.remove(signature)
        trimAIPatternStats(maxEntries: 60)
        saveAIPatternStats()
        rebuildAIMacroRecommendations()
    }

    private func rebuildAIMacroRecommendations() {
        if aiLearningMode == .off {
            aiMacroRecommendations = []
            return
        }

        let minimumUses = minimumPatternUsesForAIMacroRecommendation
        let recommendationLimit = maximumAIMacroRecommendations
        let existingPhrases = Set(voiceMacros.map { normalizeMacroPhrase($0.phrase) })
        let scenesBySignature = smartScenes.reduce(into: [String: TVSmartScene]()) { result, scene in
            let signature = actionSignature(for: scene.actions)
            if result[signature] == nil {
                result[signature] = scene
            }
        }

        let sortedStats = aiPatternStats.values.sorted { lhs, rhs in
            if lhs.useCount != rhs.useCount {
                return lhs.useCount > rhs.useCount
            }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }

        var recommendations: [TVAIMacroRecommendation] = []
        var seenPhrases = Set<String>()

        for stat in sortedStats {
            guard stat.useCount >= minimumUses else { continue }
            guard !dismissedAIPatternSignatures.contains(stat.signature) else { continue }
            let phraseSeed = stat.samplePhrase.isEmpty
                ? "run \(stat.sceneName.lowercased())"
                : stat.samplePhrase
            let phrase = normalizeMacroPhrase(phraseSeed)
            guard !phrase.isEmpty else { continue }
            guard !existingPhrases.contains(phrase) else { continue }
            guard seenPhrases.insert(phrase).inserted else { continue }

            let scene = scenesBySignature[stat.signature]
            let sceneName = scene?.name ?? stat.sceneName
            let icon = scene?.iconSystemName ?? stat.iconSystemName

            recommendations.append(
                TVAIMacroRecommendation(
                    phrase: phrase,
                    sceneName: sceneName,
                    iconSystemName: icon,
                    actions: stat.actions,
                    confidence: stat.useCount >= (minimumUses + 3) ? .high : .medium,
                    rationale: "You repeated this flow \(stat.useCount)x recently.",
                    useCount: stat.useCount
                )
            )
        }

        aiMacroRecommendations = Array(recommendations.prefix(recommendationLimit))
    }

    private var minimumPatternUsesForAIMacroRecommendation: Int {
        switch aiLearningMode {
        case .off:
            return Int.max
        case .balanced:
            return 3
        case .aggressive:
            return 2
        }
    }

    private var maximumAIMacroRecommendations: Int {
        switch aiLearningMode {
        case .off:
            return 0
        case .balanced:
            return 3
        case .aggressive:
            return 5
        }
    }

    private func sceneAction(from command: TVCommand) -> TVSceneAction? {
        switch command {
        case .powerOn:
            return TVSceneAction(kind: .powerOn)
        case .powerOff:
            return TVSceneAction(kind: .powerOff)
        case .home:
            return TVSceneAction(kind: .home)
        case .back:
            return TVSceneAction(kind: .back)
        case .volumeUp:
            return TVSceneAction(kind: .volumeUp)
        case .volumeDown:
            return TVSceneAction(kind: .volumeDown)
        case let .setVolume(level):
            return TVSceneAction(kind: .setVolume, payload: String(max(0, min(100, level))))
        case let .mute(value):
            if value == false {
                return TVSceneAction(kind: .muteOff)
            }
            return TVSceneAction(kind: .muteOn)
        case let .launchApp(appID):
            return TVSceneAction(kind: .launchApp, payload: appID)
        case let .inputSwitch(inputID):
            return TVSceneAction(kind: .switchInput, payload: inputID)
        case .menu, .up, .down, .left, .right, .select, .keyboardText:
            return nil
        }
    }

    private func sceneDescriptor(for command: TVCommand) -> (name: String, iconSystemName: String) {
        switch command {
        case .powerOn:
            return ("Power On TV", "power.circle.fill")
        case .powerOff:
            return ("Power Off TV", "power")
        case .home:
            return ("Go Home", "house.fill")
        case .back:
            return ("Go Back", "arrow.left")
        case .volumeUp:
            return ("Volume Up", "speaker.plus.fill")
        case .volumeDown:
            return ("Volume Down", "speaker.minus.fill")
        case .setVolume:
            return ("Set Volume", "speaker.wave.2.fill")
        case let .mute(value):
            if value == false {
                return ("Unmute TV", "speaker.wave.2.fill")
            }
            return ("Mute TV", "speaker.slash.fill")
        case .launchApp:
            return ("Open App", "play.rectangle.fill")
        case .inputSwitch:
            return ("Switch Input", "rectangle.on.rectangle")
        case .menu:
            return ("Open Menu", "slider.horizontal.3")
        case .up:
            return ("Navigate Up", "chevron.up")
        case .down:
            return ("Navigate Down", "chevron.down")
        case .left:
            return ("Navigate Left", "chevron.left")
        case .right:
            return ("Navigate Right", "chevron.right")
        case .select:
            return ("Select", "checkmark")
        case .keyboardText:
            return ("Send Text", "text.cursor")
        }
    }

    private func actionSignature(for actions: [TVSceneAction]) -> String {
        actions.map { action in
            "\(action.kind.rawValue)|\((action.payload ?? "").lowercased())"
        }
        .joined(separator: "->")
    }

    private func trimAIPatternStats(maxEntries: Int) {
        guard aiPatternStats.count > maxEntries else { return }
        let keep = aiPatternStats
            .values
            .sorted { lhs, rhs in
                if lhs.useCount != rhs.useCount {
                    return lhs.useCount > rhs.useCount
                }
                return lhs.lastUsedAt > rhs.lastUsedAt
            }
            .prefix(maxEntries)

        aiPatternStats = Dictionary(uniqueKeysWithValues: keep.map { ($0.signature, $0) })
    }

    private func draftSmartSceneFromCopilot(
        prompt: String
    ) -> (name: String, iconSystemName: String, actions: [TVSceneAction])? {
        let normalized = prompt
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        var actions: [TVSceneAction] = []

        if normalized.contains("power on")
            || normalized.contains("turn on")
            || normalized.contains("wake") {
            actions.append(TVSceneAction(kind: .powerOn))
        }

        if let inputID = copilotInputID(from: normalized) {
            actions.append(TVSceneAction(kind: .switchInput, payload: inputID))
        }

        if let appID = copilotAppID(from: normalized) {
            actions.append(TVSceneAction(kind: .launchApp, payload: appID))
        } else if normalized.contains("home") {
            actions.append(TVSceneAction(kind: .home))
        }

        if let volume = copilotVolumeTarget(from: normalized) {
            actions.append(TVSceneAction(kind: .setVolume, payload: String(volume)))
        } else if normalized.contains("volume up")
            || normalized.contains("louder")
            || normalized.contains("turn up") {
            actions.append(TVSceneAction(kind: .volumeUp))
        } else if normalized.contains("volume down")
            || normalized.contains("quieter")
            || normalized.contains("turn down") {
            actions.append(TVSceneAction(kind: .volumeDown))
        }

        if normalized.contains("unmute") {
            actions.append(TVSceneAction(kind: .muteOff))
        } else if normalized.contains("mute") {
            actions.append(TVSceneAction(kind: .muteOn))
        }

        if normalized.contains("power off")
            || normalized.contains("turn off") {
            actions.append(TVSceneAction(kind: .powerOff))
        }

        guard !actions.isEmpty else { return nil }

        let dedupedActions = actions.reduce(into: [TVSceneAction]()) { result, action in
            if result.last?.kind == action.kind && result.last?.payload == action.payload {
                return
            }
            result.append(action)
        }

        return (
            name: copilotSceneName(from: prompt, normalized: normalized),
            iconSystemName: copilotSceneIcon(from: normalized),
            actions: dedupedActions
        )
    }

    private func copilotSceneName(from prompt: String, normalized: String) -> String {
        if normalized.contains("movie") || normalized.contains("film") {
            return "Movie Night"
        }
        if normalized.contains("sport") || normalized.contains("game") {
            return "Game Time"
        }
        if normalized.contains("bedtime")
            || normalized.contains("sleep")
            || normalized.contains("wind down")
            || normalized.contains("night") {
            return "Wind Down"
        }
        if normalized.contains("youtube tv") {
            return "YouTube TV"
        }

        let words = prompt
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0.capitalized }

        let candidate = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? "AI Scene" : candidate
    }

    private func copilotSceneIcon(from normalized: String) -> String {
        if normalized.contains("movie") || normalized.contains("film") {
            return "film.stack.fill"
        }
        if normalized.contains("sport") || normalized.contains("game") {
            return "sportscourt.fill"
        }
        if normalized.contains("bedtime")
            || normalized.contains("sleep")
            || normalized.contains("wind down")
            || normalized.contains("night") {
            return "moon.stars.fill"
        }
        if normalized.contains("youtube")
            || normalized.contains("netflix")
            || normalized.contains("prime")
            || normalized.contains("disney") {
            return "play.rectangle.fill"
        }
        return "sparkles.tv.fill"
    }

    private func copilotVolumeTarget(from normalized: String) -> Int? {
        guard let range = normalized.range(of: "volume") else { return nil }
        let suffix = normalized[range.upperBound...]
        let values = suffix
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard let first = values.first else { return nil }
        return max(0, min(100, first))
    }

    private func copilotAppID(from normalized: String) -> String? {
        if normalized.contains("youtube tv") {
            return youtubeTVAppID
        }

        if let app = availableAutomationLaunchApps.first(where: { app in
            let candidate = "\(app.title) \(app.appID)".lowercased()
            return normalized.contains(app.title.lowercased())
                || normalized.contains(app.appID.lowercased())
                || normalized.contains(candidate)
        }) {
            return app.appID
        }

        return nil
    }

    private func copilotInputID(from normalized: String) -> String? {
        if normalized.contains("hdmi 1") { return "HDMI_1" }
        if normalized.contains("hdmi 2") { return "HDMI_2" }
        if normalized.contains("hdmi 3") { return "HDMI_3" }
        if normalized.contains("hdmi 4") { return "HDMI_4" }

        if let input = availableAutomationInputs.first(where: { input in
            normalized.contains(input.title.lowercased())
                || normalized.contains(input.inputID.lowercased().replacingOccurrences(of: "_", with: " "))
        }) {
            return input.inputID
        }

        return nil
    }

    private func startAutomationTimerIfNeeded() {
        guard automationTimer == nil else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateAutomationsIfNeeded()
            }
        }
        automationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startNowPlayingPollingIfNeeded() {
        guard nowPlayingPollTask == nil else { return }

        nowPlayingPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.connectionState.isConnected {
                    await self.refreshNowPlayingState()
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func stopNowPlayingPolling(clearState: Bool) {
        nowPlayingPollTask?.cancel()
        nowPlayingPollTask = nil
        if clearState {
            nowPlayingState = nil
        }
    }

    private func beginDiscoveryReliabilityAttempt(
        timeout: TimeInterval = 9.0,
        source: String = "auto"
    ) {
        discoveryOutcomeTask?.cancel()
        isDiscoveryAttemptInFlight = true
        recordGrowthEvent(
            .discoveryStarted,
            metadata: [
                "source": source
            ]
        )

        discoveryOutcomeTask = Task { [weak self] in
            let nanoseconds = UInt64(timeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.completeDiscoveryReliabilityAttempt(success: !self.discoveredDevices.isEmpty)
        }
    }

    private func completeDiscoveryReliabilityAttempt(success: Bool) {
        guard isDiscoveryAttemptInFlight else { return }
        isDiscoveryAttemptInFlight = false
        discoveryOutcomeTask?.cancel()
        discoveryOutcomeTask = nil
        recordGrowthEvent(
            .discoveryFinished,
            metadata: [
                "success": success ? "1" : "0",
                "device_count": "\(discoveredDevices.count)"
            ]
        )
        recordReliability(.discovery, success: success)
    }

    private func recordReliability(_ metric: TVReliabilityMetric, success: Bool) {
        reliabilityTracker.record(metric, success: success)
        reliabilitySnapshot = reliabilityTracker.snapshot()
        refreshSceneCopilotContextSuggestions()
    }

    private func recordGrowthEvent(
        _ eventName: TVAnalyticsEventName,
        metadata: [String: String] = [:]
    ) {
        analyticsTracker.record(eventName, metadata: metadata)
        growthSnapshot = analyticsTracker.snapshot()
    }

    func purchasePremiumProduct(_ productID: String) {
        guard !isPremiumPurchaseInFlight else { return }

        isPremiumPurchaseInFlight = true
        purchasingPremiumProductID = productID
        premiumStatusMessage = "Completing purchase..."

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isPremiumPurchaseInFlight = false
                self.purchasingPremiumProductID = nil
                self.refreshDiagnostics()
            }

            do {
                let result = try await self.premiumBillingService.purchase(productID: productID)
                switch result {
                case let .purchased(purchasedProductID):
                    let entitlementIDs = await self.premiumBillingService.syncCurrentEntitlements()
                    _ = self.premiumAccessStore.syncEntitlements(productIDs: entitlementIDs)
                    self.premiumSnapshot = self.premiumAccessStore.snapshot()
                    self.premiumStatusMessage = "Pro unlocked."
                    self.recordGrowthEvent(
                        .premiumUnlocked,
                        metadata: [
                            "method": "storekit",
                            "product": purchasedProductID
                        ]
                    )
                    Haptics.success()
                    self.isPremiumPaywallPresented = false
                case .pending:
                    self.premiumStatusMessage = "Purchase is pending approval."
                case .userCancelled:
                    self.premiumStatusMessage = "Purchase canceled."
                }
            } catch {
                self.premiumStatusMessage = error.userFacingMessage
            }
        }
    }

    private func syncPremiumEntitlements() async {
        let entitlementIDs = await premiumBillingService.syncCurrentEntitlements()
        _ = premiumAccessStore.syncEntitlements(productIDs: entitlementIDs)
        premiumSnapshot = premiumAccessStore.snapshot()
        refreshDiagnostics()
    }

    private func loadPremiumCatalog(forceRefresh: Bool) async {
        if isPremiumCatalogLoading {
            return
        }
        if !forceRefresh, !premiumProducts.isEmpty {
            return
        }

        isPremiumCatalogLoading = true
        defer { isPremiumCatalogLoading = false }

        do {
            let products = try await premiumBillingService.loadProducts()
            premiumProducts = products

            if products.isEmpty {
                premiumStatusMessage = "No Pro products were returned. Check product IDs in App Store Connect."
            } else if premiumStatusMessage?.lowercased().contains("loading") == true {
                premiumStatusMessage = nil
            }
        } catch {
            premiumProducts = []
            premiumStatusMessage = error.userFacingMessage
        }
    }

    private var hasSmartScenesProAccess: Bool {
        premiumAccessStore.hasAccess(to: .macroShortcuts)
    }

    @discardableResult
    private func requirePremium(_ feature: TVPremiumFeature, source: String) -> Bool {
        if premiumAccessStore.hasAccess(to: feature) {
            return true
        }

        premiumStatusMessage = "\(feature.title) is part of Pro."
        presentPremiumPaywall(
            source: source,
            dismissDevicePicker: isDevicePickerPresented
        )
        return false
    }

    private func startReliabilityWatchdogIfNeeded() {
        guard reliabilityWatchdogTask == nil else { return }

        reliabilityWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard let self else { return }
                await self.runConnectionHealthCheckTick()
            }
        }
    }

    private func stopReliabilityWatchdog() {
        reliabilityWatchdogTask?.cancel()
        reliabilityWatchdogTask = nil
        consecutiveHealthCheckFailures = 0
        isAutoReconnectTrackingActive = false
    }

    private func runConnectionHealthCheckTick() async {
        guard connectionState.isConnected else {
            consecutiveHealthCheckFailures = 0
            isHealthCheckInFlight = false
            return
        }

        guard !isHealthCheckInFlight else { return }
        // Avoid watchdog reconnect churn while the user is actively pressing controls.
        if Date().timeIntervalSince(lastCommandDispatchAt) < 2.5 {
            return
        }

        isHealthCheckInFlight = true
        defer { isHealthCheckInFlight = false }

        let isHealthy = await controller.ping()
        if isHealthy {
            consecutiveHealthCheckFailures = 0
            return
        }

        consecutiveHealthCheckFailures += 1
        guard consecutiveHealthCheckFailures >= 2 else { return }
        consecutiveHealthCheckFailures = 0

        isAutoReconnectTrackingActive = true
        await controller.reconnectToLastDeviceIfPossible()
        refreshDiagnostics()
    }

    private func evaluateAutomationsIfNeeded() {
        guard !automationRules.isEmpty else { return }
        let now = Date()
        let calendar = Calendar.current
        var didMutate = false

        for index in automationRules.indices {
            guard automationRules[index].isEnabled else { continue }
            guard automationRules[index].matches(date: now, calendar: calendar) else { continue }
            guard !automationRules[index].hasExecutedInSameMinute(as: now, calendar: calendar) else { continue }

            executeAutomationRule(automationRules[index])
            automationRules[index].lastExecutedAt = now
            didMutate = true
        }

        if didMutate {
            saveAutomationRules()
        }
    }

    private func executeAutomationRule(_ rule: TVAutomationRule) {
        automationStatusMessage = "Running automation: \(rule.name)"

        switch rule.action {
        case .powerOn:
            powerOnTV()
        case .powerOff:
            powerOffTV()
        case .muteOn:
            send(.mute(true))
        case .muteOff:
            send(.mute(false))
        case .setVolume:
            let level = Int(rule.payload ?? "") ?? 20
            send(.setVolume(max(0, min(100, level))))
        case .launchApp:
            guard let payload = rule.payload, !payload.isEmpty else { return }
            send(.launchApp(payload))
        case .switchInput:
            guard let payload = rule.payload, !payload.isEmpty else { return }
            send(.inputSwitch(payload))
        }
    }

    @discardableResult
    private func sendCommandAndHandleResult(_ command: TVCommand) async -> Bool {
        let commandKey = command.rateLimitKey
        if isCaregiverModeEnabled && !isCommandAllowedInCaregiverMode(command) {
            transientErrorMessage = "Caregiver mode blocks that control."
            return false
        }

        if case .powerOn = command {
            if supportsControls {
                // Scene and macro flows often include power-on as a first step.
                // When the TV is already connected, treat it as satisfied.
                return true
            }

            guard configuredWakeMACAddress() != nil else {
                transientErrorMessage = "Power On needs Wake-on-LAN setup. Save your TV MAC in Devices > Advanced."
                return false
            }
        }

        let requiresConnection: Bool
        switch command {
        case .powerOn:
            requiresConnection = false
        default:
            requiresConnection = true
        }

        if requiresConnection && !supportsControls {
            await controller.reconnectToLastDeviceIfPossible()
            refreshDiagnostics()
            guard supportsControls else {
                transientErrorMessage = TVControllerError.notConnected.localizedDescription
                return false
            }
        }

        if requiresConnection,
           let required = requiredCapability(for: command),
           !activeCapabilities.contains(required) {
            transientErrorMessage = TVControllerError.commandUnsupported.localizedDescription
            return false
        }

        recordGrowthEvent(
            .commandAttempt,
            metadata: [
                "command": commandKey
            ]
        )

        do {
            lastCommandDispatchAt = Date()
            try await controller.send(command: command)
            recordReliability(.command, success: true)
            recordGrowthEvent(
                .commandResult,
                metadata: [
                    "command": commandKey,
                    "success": "1"
                ]
            )
            if case let .mute(value) = command, let value {
                isMuted = value
            }
            if command.affectsVolumeState {
                scheduleVolumeStateRefresh(after: 0.30)
            }
            refreshDiagnostics()
            return true
        } catch {
            recordReliability(.command, success: false)
            recordGrowthEvent(
                .commandResult,
                metadata: [
                    "command": commandKey,
                    "success": "0",
                    "error": Self.analyticsSafe(error.userFacingMessage)
                ]
            )
            transientErrorMessage = errorMessage(for: error, command: command)
            refreshDiagnostics()
            return false
        }
    }

    private func executePlainEnglishCommand(_ text: String, fallbackToKeyboard: Bool) async -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            plainCommandStatusMessage = "Type a command first."
            return false
        }

        if let macro = matchedVoiceMacro(in: normalized) {
            guard requirePremium(.macroShortcuts, source: "voice_macro") else { return false }
            guard let scene = smartScenes.first(where: { $0.id == macro.sceneID }) else {
                voiceMacroStatusMessage = "Macro scene is missing. Update or remove this macro."
                return false
            }

            let success = await executeSmartScene(
                scene,
                source: "voice_macro",
                triggeredPhrase: macro.phrase
            )
            if success {
                markVoiceMacroUsed(macro.id)
                plainCommandStatusMessage = "Ran macro: \"\(macro.phrase)\"."
                voiceMacroStatusMessage = "Macro triggered from command."
            }
            return success
        }

        if let parsed = parsePlainEnglishCommand(from: normalized) {
            switch parsed {
            case let .command(command):
                guard await sendCommandAndHandleResult(command) else { return false }
            case let .launchApp(app):
                guard !isAppLocked(app) else {
                    transientErrorMessage = "\(app.title) is locked."
                    return false
                }
                guard await sendCommandAndHandleResult(.launchApp(app.appID)) else { return false }
            case let .switchInput(input):
                guard !isInputLocked(input) else {
                    transientErrorMessage = "\(input.title) is locked."
                    return false
                }
                guard await sendCommandAndHandleResult(.inputSwitch(input.inputID)) else { return false }
            }
            trackAIPatternUsage(from: parsed, spokenCommand: normalized)
            plainCommandStatusMessage = "Command sent: \(text)"
            return true
        }

        guard fallbackToKeyboard else {
            plainCommandStatusMessage = "I couldn't map \"\(text)\" to a remote action."
            return false
        }

        guard await sendCommandAndHandleResult(.keyboardText(text)) else {
            plainCommandStatusMessage = "Could not send text. Open a text field on the TV, then try again."
            return false
        }
        plainCommandStatusMessage = "Sent as keyboard text."
        return true
    }

    private func errorMessage(for error: Error, command: TVCommand) -> String {
        guard case .keyboardText = command else {
            return error.userFacingMessage
        }

        let normalized = error.userFacingMessage.lowercased()
        if normalized.contains("404")
            || normalized.contains("no such service")
            || normalized.contains("no such method")
            || normalized.contains("unsupported")
            || normalized.contains("unknown uri") {
            return "Open a text field on the TV first, then tap Send to TV again."
        }
        return error.userFacingMessage
    }

    private func parsePlainEnglishCommand(from normalized: String) -> ParsedPlainCommand? {
        let numbers = normalized.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }

        if normalized.contains("power on") || normalized.contains("turn on") || normalized.contains("wake tv") {
            return .command(.powerOn)
        }
        if normalized.contains("power off") || normalized.contains("turn off") || normalized.contains("tv off") {
            return .command(.powerOff)
        }
        if normalized.contains("volume up") || normalized.contains("turn up") || normalized.contains("louder") {
            return .command(.volumeUp)
        }
        if normalized.contains("volume down") || normalized.contains("turn down") || normalized.contains("quieter") {
            return .command(.volumeDown)
        }
        if normalized.contains("set volume"), let first = numbers.first {
            return .command(.setVolume(max(0, min(100, first))))
        }
        if normalized.contains("unmute") {
            return .command(.mute(false))
        }
        if normalized.contains("mute") {
            return .command(.mute(true))
        }
        if normalized.contains("home") {
            return .command(.home)
        }
        if normalized.contains("back") {
            return .command(.back)
        }
        if normalized.contains("menu") {
            return .command(.menu)
        }
        if normalized.contains("select") || normalized.contains("ok") || normalized.contains("enter") {
            return .command(.select)
        }
        if normalized == "up" || normalized.contains("go up") {
            return .command(.up)
        }
        if normalized == "down" || normalized.contains("go down") {
            return .command(.down)
        }
        if normalized == "left" || normalized.contains("go left") {
            return .command(.left)
        }
        if normalized == "right" || normalized.contains("go right") {
            return .command(.right)
        }

        if normalized.contains("open") || normalized.contains("launch") || normalized.contains("play") {
            if let app = quickLaunchApps.first(where: { app in
                let candidate = "\(app.title) \(app.appID)".lowercased()
                return normalized.contains(app.title.lowercased()) || normalized.contains(candidate)
            }) {
                return .launchApp(app)
            }
            if normalized.contains("youtube tv") {
                let app = quickLaunchApps.first {
                    "\($0.title) \($0.appID)".lowercased().contains("youtube tv")
                } ?? TVAppShortcut.lgDefaults.first {
                    "\($0.title) \($0.appID)".lowercased().contains("youtube tv")
                }
                if let app {
                    return .launchApp(app)
                }
            }
        }

        if normalized.contains("switch to") || normalized.contains("input") || normalized.contains("hdmi") {
            if let input = inputSources.first(where: { input in
                normalized.contains(input.title.lowercased())
                    || normalized.contains(input.inputID.lowercased().replacingOccurrences(of: "_", with: " "))
            }) {
                return .switchInput(input)
            }
            if normalized.contains("hdmi 1"), let input = inputSources.first(where: { $0.inputID == "HDMI_1" }) {
                return .switchInput(input)
            }
            if normalized.contains("hdmi 2"), let input = inputSources.first(where: { $0.inputID == "HDMI_2" }) {
                return .switchInput(input)
            }
            if normalized.contains("hdmi 3"), let input = inputSources.first(where: { $0.inputID == "HDMI_3" }) {
                return .switchInput(input)
            }
            if normalized.contains("hdmi 4"), let input = inputSources.first(where: { $0.inputID == "HDMI_4" }) {
                return .switchInput(input)
            }
        }

        return nil
    }

    private func isCommandAllowedInCaregiverMode(_ command: TVCommand) -> Bool {
        switch command {
        case .powerOn, .powerOff, .volumeUp, .volumeDown, .setVolume, .mute, .home, .back, .select:
            return true
        case .launchApp:
            return true
        default:
            return false
        }
    }

    private func configuredWakeMACAddress() -> String? {
        let draft = wakeMACAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedDraft = WakeOnLANService.normalizedMACAddress(draft) {
            return normalizedDraft
        }

        if let activeMAC = activeDevice?.wakeMACAddress,
           let normalizedActive = WakeOnLANService.normalizedMACAddress(activeMAC) {
            return normalizedActive
        }

        for known in knownDevices {
            if let knownMAC = known.wakeMACAddress,
               let normalizedKnown = WakeOnLANService.normalizedMACAddress(knownMAC) {
                return normalizedKnown
            }
        }

        return nil
    }

    private func parseManualAddress(_ rawAddress: String) -> (host: String, port: Int)? {
        let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "ws://\(trimmed)"
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty else {
            return nil
        }

        let isSecure = (url.scheme ?? "").lowercased() == "wss"
        let defaultPort = isSecure ? 3001 : 3000
        return (host, url.port ?? defaultPort)
    }

    private func probeTCP(host: String, port: UInt16, timeout: TimeInterval = 1.2) async -> Bool {
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
            let queue = DispatchQueue(label: "com.reggieboi.tvremote.probe.\(host).\(port)")
            let completionGate = TVRemoteProbeCompletionGate()
            let complete: @Sendable (Bool) -> Void = { success in
                guard completionGate.tryComplete() else { return }
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: success)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    complete(true)
                case .failed:
                    complete(false)
                case .cancelled:
                    complete(false)
                default:
                    break
                }
            }
            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                complete(false)
            }
        }
    }

    private static func wifiIPv4Address() -> String? {
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

    private func syncFavoriteQuickLaunchSelection() {
        let validIDs = Set(quickLaunchApps.map(\.id))
        favoriteQuickLaunchIDs = favoriteQuickLaunchIDs.filter { validIDs.contains($0) }

        if favoriteQuickLaunchIDs.isEmpty {
            let preferred = quickLaunchApps.filter {
                let value = "\($0.title) \($0.appID)".lowercased()
                return value.contains("youtube tv")
                    || value.contains("youtube")
                    || value.contains("netflix")
                    || value.contains("prime")
            }
            let seeded = Array((preferred + quickLaunchApps).prefix(4).map(\.id))
            favoriteQuickLaunchIDs = Array(NSOrderedSet(array: seeded).compactMap { $0 as? String })
        }

        saveFavoriteQuickLaunchIDs()
    }

    private var activeCapabilities: Set<TVCapability> {
        activeDevice?.capabilities ?? []
    }

    private func requiredCapability(for command: TVCommand) -> TVCapability? {
        switch command {
        case .up, .down, .left, .right, .select, .menu:
            return .dpad
        case .back:
            return .back
        case .home:
            return .home
        case .volumeUp, .volumeDown, .setVolume:
            return .volume
        case .mute:
            return .mute
        case .powerOff:
            return .power
        case .powerOn:
            return nil
        case .launchApp:
            return .launchApp
        case .inputSwitch:
            return .inputSwitch
        case .keyboardText:
            return nil
        }
    }

    private func saveFavoriteQuickLaunchIDs() {
        defaults.set(favoriteQuickLaunchIDs, forKey: quickLaunchFavoritesKey)
    }

    private static func loadFavorites(from defaults: UserDefaults) -> [String] {
        guard let stored = defaults.array(forKey: "tvremote.quick_launch_favorites.v1") as? [String] else {
            return []
        }
        return stored
    }

    private static func mergeQuickLaunchApps(
        primary: [TVAppShortcut],
        fallback: [TVAppShortcut]
    ) -> [TVAppShortcut] {
        let source = primary.isEmpty ? fallback : (primary + fallback)
        var seen = Set<String>()
        var merged: [TVAppShortcut] = []

        for app in source {
            let normalizedAppID = app.appID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let dedupeKey = normalizedAppID.isEmpty ? app.id.lowercased() : normalizedAppID
            guard seen.insert(dedupeKey).inserted else { continue }
            merged.append(app)
        }

        return merged
    }

    private var youtubeTVAppID: String {
        if let dynamic = quickLaunchApps.first(where: {
            "\($0.title) \($0.appID)".lowercased().contains("youtube tv")
        }) {
            return dynamic.appID
        }
        return "youtube.leanback.ytv.v1"
    }

    private struct AIPatternStat: Codable {
        var signature: String
        var samplePhrase: String
        var sceneName: String
        var iconSystemName: String
        var actions: [TVSceneAction]
        var useCount: Int
        var lastUsedAt: Date
    }

    private enum ParsedPlainCommand {
        case command(TVCommand)
        case launchApp(TVAppShortcut)
        case switchInput(TVInputSource)
    }

    private static let diagnosticsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        let message = error.userFacingMessage.lowercased()
        return message.contains("cancelled") || message.contains("canceled")
    }

    private static func analyticsSafe(_ value: String, maxLength: Int = 72) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard normalized.count > maxLength else { return normalized }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return String(normalized[..<endIndex])
    }
}

private final class TVReliabilityTracker {
    private struct Event: Codable {
        let metric: TVReliabilityMetric
        let success: Bool
        let timestamp: Date
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let windowDays: Int
    private let maxEvents: Int
    private var events: [Event]

    init(
        defaults: UserDefaults,
        storageKey: String,
        windowDays: Int = 14,
        maxEvents: Int = 1_200
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.windowDays = max(7, windowDays)
        self.maxEvents = max(250, maxEvents)
        events = Self.loadEvents(defaults: defaults, key: storageKey)
        pruneOldEvents(referenceDate: Date(), saveIfChanged: true)
    }

    func record(_ metric: TVReliabilityMetric, success: Bool, at date: Date = Date()) {
        events.append(
            Event(
                metric: metric,
                success: success,
                timestamp: date
            )
        )

        pruneOldEvents(referenceDate: date, saveIfChanged: false)
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        save()
    }

    func snapshot(referenceDate: Date = Date()) -> TVReliabilitySnapshot {
        pruneOldEvents(referenceDate: referenceDate, saveIfChanged: true)

        func summary(for metric: TVReliabilityMetric) -> TVReliabilityMetricSummary {
            let metricEvents = events.filter { $0.metric == metric }
            let successes = metricEvents.reduce(into: 0) { partial, event in
                if event.success {
                    partial += 1
                }
            }
            return TVReliabilityMetricSummary(
                attempts: metricEvents.count,
                successes: successes
            )
        }

        return TVReliabilitySnapshot(
            generatedAt: referenceDate,
            windowDays: windowDays,
            discovery: summary(for: .discovery),
            connection: summary(for: .connection),
            command: summary(for: .command),
            fixWorkflow: summary(for: .fixWorkflow),
            autoReconnect: summary(for: .autoReconnect)
        )
    }

    private func pruneOldEvents(referenceDate: Date, saveIfChanged: Bool) {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -windowDays, to: referenceDate) else {
            return
        }

        let previousCount = events.count
        events.removeAll { $0.timestamp < cutoffDate }
        if saveIfChanged, previousCount != events.count {
            save()
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(events)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Keep telemetry best-effort without blocking primary remote flows.
        }
    }

    private static func loadEvents(defaults: UserDefaults, key: String) -> [Event] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([Event].self, from: data)
        } catch {
            return []
        }
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

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension TVWatchHistoryEntry {
    func matches(
        appName: String,
        title: String?,
        subtitle: String?,
        source: TVNowPlayingSource
    ) -> Bool {
        self.appName == appName
            && self.title == title
            && self.subtitle == subtitle
            && self.source == source
    }
}

private extension TVCommand {
    nonisolated var affectsVolumeState: Bool {
        switch self {
        case .volumeUp, .volumeDown, .setVolume, .mute:
            return true
        default:
            return false
        }
    }

    nonisolated var coalescesWhileBusy: Bool {
        switch self {
        case .up, .down, .left, .right, .volumeUp, .volumeDown, .setVolume:
            return true
        default:
            return false
        }
    }
}

private final class TVRemoteProbeCompletionGate: @unchecked Sendable {
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
