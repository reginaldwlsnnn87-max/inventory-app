import Foundation
import Network

@MainActor
final class LGWebOSController: TVController {
    var onDevicesChanged: (([TVDevice]) -> Void)?
    var onKnownDevicesChanged: (([TVDevice]) -> Void)?
    var onStateChanged: ((TVConnectionState) -> Void)?

    private(set) var currentDevice: TVDevice?
    private(set) var knownDevices: [TVDevice]

    private let discoveryService: LGDiscoveryService
    private let socketClient: LGWebOSSocketClient
    private let keychain: KeychainStore
    private let knownDevicesStore: KnownDevicesStore
    private let widgetContextStore: TVWidgetCommandContextStore
    private let defaults: UserDefaults
    private let commandLimiter = CommandRateLimiter()
    private let commandExecutionGate = CommandExecutionGate()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.reggieboi.tvremote.path")

    private var stateMachine = TVConnectionStateMachine()
    private var discoveredDevices: [TVDevice] = []
    private var pendingPairDevice: TVDevice?
    private var reconnectTask: Task<Void, Never>?
    private var postConnectHydrationTask: Task<Void, Never>?
    private var buttonTransportWarmupTask: Task<Void, Never>?
    private var silentKeepAliveTask: Task<Void, Never>?
    private var reconnectAttemptCount = 0
    private var silentKeepAliveFailureCount = 0
    private var lastCommandDispatchAt = Date.distantPast
    private var isNetworkReachable = true
    private var suppressNextDisconnectFailure = false
    private var buttonTransportMode: LGButtonTransportMode = .ssapSendButton
    private var currentServiceNames = Set<String>()
    private var lastCommandError: LGCommandErrorSnapshot?
    private var reconnectAttemptsTotal = 0
    private var commandRetryCount = 0
    private var pingFailureCount = 0
    private var lastAutoRecoveryAt: Date?
    private var markNextReconnectAsAutoRecovery = false
    private var appNameCacheByID: [String: String] = [:]
    private var appNameCacheUpdatedAt: Date?
    private let appNameCacheTTL: TimeInterval = 15 * 60
    private let controlCommandTimeout: TimeInterval = 1.4
    private let stateQueryTimeout: TimeInterval = 1.9
    private let pingTimeout: TimeInterval = 1.2
    private let silentKeepAliveInterval: TimeInterval = 18
    private let silentKeepAliveTimeout: TimeInterval = 1.0
    private let silentKeepAliveCommandGracePeriod: TimeInterval = 4
    private let launchDataTimeout: TimeInterval = 3.2
    private let metadataProbeTimeout: TimeInterval = 1.25
    private let plexMetadataTimeout: TimeInterval = 2.0
    private let plexMetadataRequestCooldown: TimeInterval = 4.0
    private let reconnectRegistrationTimeout: TimeInterval = 3.2
    private let pairingRegistrationTimeout: TimeInterval = 30.0
    private let fallbackEndpointProbeTimeout: TimeInterval = 0.25
    private let plexServerURLDefaultsKey = "tvremote.metadata.plex.server_url.v1"
    private let plexTokenKeychainKey = "tvremote.metadata.plex.token.v1"
    private var plexLastMetadataRequestAtByTVIP: [String: Date] = [:]
    private var plexMetadataCacheByTVIP: [String: LGPlexMetadataSnapshot] = [:]
    private var unsupportedNowPlayingURIs = Set<String>()
    private var lastNowPlayingProbeSummary: String?
    private var appSpecificNowPlayingProbeTimestamps: [String: Date] = [:]
    private let appSpecificNowPlayingProbeCooldown: TimeInterval = 9
    private var commandLatencyEvents: [CommandLatencyEvent] = []
    private let commandLatencyWindowSize = 80

    init(
        discoveryService: LGDiscoveryService,
        socketClient: LGWebOSSocketClient,
        keychain: KeychainStore,
        knownDevicesStore: KnownDevicesStore,
        widgetContextStore: TVWidgetCommandContextStore,
        defaults: UserDefaults = .standard
    ) {
        self.discoveryService = discoveryService
        self.socketClient = socketClient
        self.keychain = keychain
        self.knownDevicesStore = knownDevicesStore
        self.widgetContextStore = widgetContextStore
        self.defaults = defaults
        knownDevices = knownDevicesStore.loadDevices()

        bindCallbacks()
        startPathMonitor()
    }

    deinit {
        pathMonitor.cancel()
        reconnectTask?.cancel()
        postConnectHydrationTask?.cancel()
        buttonTransportWarmupTask?.cancel()
        silentKeepAliveTask?.cancel()
    }

    convenience init() {
        self.init(
            discoveryService: LGDiscoveryService(),
            socketClient: LGWebOSSocketClient(),
            keychain: KeychainStore(),
            knownDevicesStore: KnownDevicesStore(),
            widgetContextStore: TVWidgetCommandContextStore(),
            defaults: .standard
        )
    }

    func startDiscovery() {
        applyTransition(.beginScan)
        discoveryService.start()
    }

    func stopDiscovery() {
        discoveryService.stop()
    }

    func connect(to device: TVDevice, asReconnection: Bool = false) async throws {
        reconnectTask?.cancel()
        reconnectTask = nil
        postConnectHydrationTask?.cancel()
        postConnectHydrationTask = nil
        buttonTransportWarmupTask?.cancel()
        buttonTransportWarmupTask = nil
        silentKeepAliveTask?.cancel()
        silentKeepAliveTask = nil
        silentKeepAliveFailureCount = 0
        buttonTransportMode = .ssapSendButton
        currentServiceNames.removeAll()
        appNameCacheByID.removeAll()
        appNameCacheUpdatedAt = nil
        unsupportedNowPlayingURIs.removeAll()
        lastNowPlayingProbeSummary = nil
        appSpecificNowPlayingProbeTimestamps.removeAll()
        if asReconnection {
            reconnectAttemptsTotal += 1
        }
        let markAutoRecovery = asReconnection && markNextReconnectAsAutoRecovery
        markNextReconnectAsAutoRecovery = false

        var lastError: Error = TVControllerError.networkFailure("TV connection failed.")
        let endpoints = connectionEndpoints(for: device)

        for endpoint in endpoints {
            if asReconnection,
               endpoint.port != device.port,
               let probePort = UInt16(exactly: endpoint.port) {
                let reachable = await probeTCP(
                    host: device.ip,
                    port: probePort,
                    timeout: fallbackEndpointProbeTimeout
                )
                if !reachable {
                    continue
                }
            }

            pendingPairDevice = device
            if asReconnection {
                applyTransition(.beginReconnect(device))
            } else {
                applyTransition(.beginPairing(device))
            }

            do {
                try socketClient.connect(
                    host: device.ip,
                    port: endpoint.port,
                    secure: endpoint.secure
                )
                try await pair(
                    timeout: asReconnection ? reconnectRegistrationTimeout : pairingRegistrationTimeout
                )

                var connected = device
                connected.port = endpoint.port
                connected.lastConnectedAt = Date()

                knownDevicesStore.markConnected(connected)
                knownDevices = knownDevicesStore.loadDevices()
                onKnownDevicesChanged?(knownDevices)

                if let persisted = knownDevices.first(where: { $0.id == connected.id }) {
                    connected = persisted
                }
                currentDevice = connected
                refreshWidgetCommandContext(for: connected)
                pendingPairDevice = nil
                reconnectAttemptCount = 0
                if markAutoRecovery {
                    lastAutoRecoveryAt = Date()
                }

                applyTransition(.didConnect(connected))
                startPostConnectOptimization(for: connected)
                startSilentKeepAliveLoop()
                return
            } catch {
                if Self.isCancellation(error) {
                    throw error
                }
                lastError = error
                recordCommandError(error, command: nil)
                socketClient.disconnect(emitEvent: false)
                guard shouldTryNextEndpoint(after: error) else { break }
            }
        }

        if Self.isCancellation(lastError) {
            throw lastError
        }

        let message = lastError.userFacingMessage
        applyTransition(.fail(message))

        if asReconnection || currentDevice != nil {
            scheduleReconnectWithBackoff()
        }
        throw lastError
    }

    func connectUsingManualIP(_ ip: String) async throws {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TVControllerError.invalidAddress
        }

        guard let parsed = parseManualAddress(trimmed) else {
            throw TVControllerError.invalidAddress
        }
        let manualDevice = TVDevice.manualLG(ip: parsed.host, port: parsed.port)
        try await connect(to: manualDevice, asReconnection: false)
    }

    func pair() async throws {
        try await pair(timeout: pairingRegistrationTimeout)
    }

    private func pair(timeout: TimeInterval) async throws {
        guard let device = pendingPairDevice ?? currentDevice else {
            throw TVControllerError.noDeviceSelected
        }

        let keyName = keychainKey(for: device)
        let existingKey = try keychain.string(for: keyName)

        do {
            let newClientKey = try await socketClient.register(
                existingClientKey: existingKey,
                timeout: timeout
            )
            if !newClientKey.isEmpty {
                try keychain.set(newClientKey, for: keyName)
            }
        } catch {
            guard shouldRetryPairingWithoutClientKey(after: error), existingKey != nil else {
                throw TVControllerError.pairingFailed(error.userFacingMessage)
            }

            try? keychain.removeValue(for: keyName)
            do {
                let newClientKey = try await socketClient.register(
                    existingClientKey: nil,
                    timeout: timeout
                )
                if !newClientKey.isEmpty {
                    try keychain.set(newClientKey, for: keyName)
                }
            } catch {
                throw TVControllerError.pairingFailed(error.userFacingMessage)
            }
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        postConnectHydrationTask?.cancel()
        postConnectHydrationTask = nil
        buttonTransportWarmupTask?.cancel()
        buttonTransportWarmupTask = nil
        silentKeepAliveTask?.cancel()
        silentKeepAliveTask = nil
        silentKeepAliveFailureCount = 0
        reconnectAttemptCount = 0
        markNextReconnectAsAutoRecovery = false

        socketClient.disconnect(emitEvent: false)
        buttonTransportMode = .ssapSendButton
        currentServiceNames.removeAll()
        appNameCacheByID.removeAll()
        appNameCacheUpdatedAt = nil
        unsupportedNowPlayingURIs.removeAll()
        lastNowPlayingProbeSummary = nil
        appSpecificNowPlayingProbeTimestamps.removeAll()
        currentDevice = nil
        pendingPairDevice = nil
        applyTransition(.disconnect)

        Task {
            await commandLimiter.reset()
        }
    }

    func send(command: TVCommand) async throws {
        let startedAt = Date()
        lastCommandDispatchAt = startedAt

        try await commandExecutionGate.withPermit {
            do {
                if case .powerOn = command {
                    try await powerOnViaWakeOnLAN()
                    recordCommandLatency(command: command, startedAt: startedAt, success: true, error: nil)
                    return
                }

                guard let connectedDevice = currentDevice else {
                    throw TVControllerError.notConnected
                }

                if let requiredCapability = capability(for: command),
                   !connectedDevice.capabilities.contains(requiredCapability) {
                    throw TVControllerError.commandUnsupported
                }

                await commandLimiter.waitIfNeeded(for: command)
                do {
                    try await sendCommand(command)
                    recordCommandLatency(command: command, startedAt: startedAt, success: true, error: nil)
                    return
                } catch {
                    if shouldRetryCommand(command: command, after: error) {
                        do {
                            try await recoverConnectionForCommandRetry(using: connectedDevice)
                            try await sendCommand(command)
                            recordCommandLatency(command: command, startedAt: startedAt, success: true, error: nil)
                            return
                        } catch {
                            recordCommandError(error, command: command)
                            if shouldMarkCapabilityUnsupported(command: command, after: error),
                               let unsupportedCapability = capability(for: command) {
                                markCapabilityUnsupported(unsupportedCapability, on: connectedDevice.id)
                                throw TVControllerError.commandUnsupported
                            }
                            throw error
                        }
                    }

                    recordCommandError(error, command: command)
                    if shouldMarkCapabilityUnsupported(command: command, after: error),
                       let unsupportedCapability = capability(for: command) {
                        markCapabilityUnsupported(unsupportedCapability, on: connectedDevice.id)
                        throw TVControllerError.commandUnsupported
                    }
                    throw error
                }
            } catch {
                recordCommandLatency(command: command, startedAt: startedAt, success: false, error: error)
                throw error
            }
        }
    }

    func fetchLaunchApps() async -> [TVAppShortcut] {
        guard currentDevice != nil else { return TVAppShortcut.lgDefaults }

        do {
            let response = try await socketClient.request(
                uri: LGWebOSURI.listLaunchPoints,
                timeout: launchDataTimeout
            )
            let parsed = Self.parseLaunchApps(from: response, tvHost: currentDevice?.ip)
            mergeAppNameCache(with: parsed)
            return parsed.isEmpty ? TVAppShortcut.lgDefaults : parsed
        } catch {
            return TVAppShortcut.lgDefaults
        }
    }

    func fetchInputSources() async -> [TVInputSource] {
        guard currentDevice != nil else { return TVInputSource.lgDefaults }

        do {
            let response = try await socketClient.request(
                uri: LGWebOSURI.getExternalInputList,
                timeout: stateQueryTimeout
            )
            let parsed = Self.parseInputSources(from: response)
            return parsed.isEmpty ? TVInputSource.lgDefaults : parsed
        } catch {
            return TVInputSource.lgDefaults
        }
    }

    func fetchVolumeState() async -> TVVolumeState? {
        guard currentDevice != nil else { return nil }
        do {
            let response = try await socketClient.request(
                uri: LGWebOSURI.getVolume,
                timeout: stateQueryTimeout
            )
            return Self.parseVolumeState(from: response)
        } catch {
            return nil
        }
    }

    func fetchNowPlayingState() async -> TVNowPlayingState? {
        guard currentDevice != nil else { return nil }

        await refreshAppNameCacheIfNeeded()
        var probeEntries: [String] = []
        let recordProbe: (String) -> Void = { entry in
            probeEntries.append(entry)
        }

        var foregroundResponse = await requestNowPlayingURI(
            LGWebOSURI.getForegroundAppInfo,
            payload: ["extraInfo": true],
            probe: recordProbe
        )
        if foregroundResponse == nil {
            foregroundResponse = await requestNowPlayingURI(
                LGWebOSURI.getForegroundAppInfo,
                probe: recordProbe
            )
        }
        guard
            let foregroundResponse,
            var foreground = Self.parseForegroundApp(from: foregroundResponse)
        else {
            lastNowPlayingProbeSummary = Self.buildNowPlayingProbeSummary(
                appID: nil,
                appName: "Unknown",
                title: nil,
                subtitle: nil,
                source: .app,
                confidence: .low,
                probes: probeEntries
            )
            return nil
        }

        foreground.appName = resolvedAppName(for: foreground.appID, fallbackName: foreground.appName)
        if let appID = foreground.appID {
            appNameCacheByID[appID.lowercased()] = foreground.appName
        }

        var title: String?
        var subtitle: String?
        var metadataRestrictionReason: String?
        var source: TVNowPlayingSource = .app
        let foregroundMetadata = Self.parseMetadataHints(
            from: foregroundResponse,
            appName: foreground.appName,
            appID: foreground.appID
        )
        title = foregroundMetadata.title
        subtitle = foregroundMetadata.subtitle

        let isLikelyLiveTV = Self.looksLikeLiveTVApp(appID: foreground.appID, appName: foreground.appName)
        if isLikelyLiveTV {
            source = .liveTV
            if let channelResponse = await requestNowPlayingURI(
                LGWebOSURI.getCurrentChannel,
                probe: recordProbe
            ),
               let channelName = Self.parseChannelName(from: channelResponse) {
                subtitle = channelName
            }

            var programResponse = await requestNowPlayingURI(
                LGWebOSURI.getChannelCurrentProgramInfo,
                probe: recordProbe
            )
            if programResponse == nil {
                programResponse = await requestNowPlayingURI(
                    LGWebOSURI.getChannelProgramInfo,
                    probe: recordProbe
                )
            }
            if let programResponse,
               let programTitle = Self.parseProgramTitle(from: programResponse) {
                title = programTitle
            }
        }

        if let mediaResponse = await requestNowPlayingURI(LGWebOSURI.getMediaInfo, probe: recordProbe) {
            let parsed = Self.parseMediaInfo(from: mediaResponse)
            title = title ?? parsed.title
            subtitle = subtitle ?? parsed.subtitle
            if parsed.title != nil || parsed.subtitle != nil {
                source = .media
            }
        }

        if let appID = foreground.appID {
            if title == nil || subtitle == nil {
                if let runningAppsResponse = await requestNowPlayingURI(
                    LGWebOSURI.listRunningApps,
                    probe: recordProbe
                ) {
                    let runningMetadata = Self.parseRunningAppsMetadata(
                        from: runningAppsResponse,
                        preferredAppID: appID
                    )
                    if let runningAppName = runningMetadata.appName {
                        appNameCacheByID[appID.lowercased()] = runningAppName
                        foreground.appName = runningAppName
                    }
                    title = title ?? runningMetadata.title
                    subtitle = subtitle ?? runningMetadata.subtitle
                }
            }

            if title == nil || subtitle == nil {
                if let appInfoResponse = await requestNowPlayingURI(
                    LGWebOSURI.getAppInfo,
                    payload: ["id": appID],
                    probe: recordProbe
                ) {
                    let appInfo = Self.parseAppInfo(from: appInfoResponse)
                    if let appInfoName = appInfo.appName {
                        appNameCacheByID[appID.lowercased()] = appInfoName
                        foreground.appName = appInfoName
                    }
                    title = title ?? appInfo.title
                    subtitle = subtitle ?? appInfo.subtitle
                }
            }

            if title == nil || subtitle == nil {
                if let appStatusResponse = await requestNowPlayingURI(
                    LGWebOSURI.getAppStatus,
                    payload: ["appId": appID],
                    probe: recordProbe
                ) {
                    let parsedStatus = Self.parseAppStatus(from: appStatusResponse)
                    title = title ?? parsedStatus.title
                    subtitle = subtitle ?? parsedStatus.subtitle
                    if let statusAppName = parsedStatus.appName {
                        appNameCacheByID[appID.lowercased()] = statusAppName
                        foreground.appName = statusAppName
                    }
                }
            }

            if title == nil || subtitle == nil {
                if let appStateResponse = await requestNowPlayingURI(
                    LGWebOSURI.getAppState,
                    payload: ["id": appID],
                    probe: recordProbe
                ) {
                    let parsedState = Self.parseAppState(from: appStateResponse)
                    title = title ?? parsedState.title
                    subtitle = subtitle ?? parsedState.subtitle
                }
            }
        }

        title = Self.sanitizedNowPlayingValue(title, appName: foreground.appName, title: nil)
        subtitle = Self.sanitizedNowPlayingValue(subtitle, appName: foreground.appName, title: title)
        if source == .app && (title != nil || subtitle != nil) {
            source = isLikelyLiveTV ? .liveTV : .media
        }
        var confidence = Self.resolveNowPlayingConfidence(
            appName: foreground.appName,
            appID: foreground.appID,
            title: title,
            subtitle: subtitle,
            source: source
        )

        if let appID = foreground.appID,
           confidence != .high,
           let appSpecificMetadata = await resolveAppSpecificNowPlayingMetadata(
                appID: appID,
                appName: foreground.appName,
                existingTitle: title,
                existingSubtitle: subtitle,
                probe: recordProbe
           ) {
            title = appSpecificMetadata.title
            subtitle = appSpecificMetadata.subtitle

            if source == .app && (title != nil || subtitle != nil) {
                source = isLikelyLiveTV ? .liveTV : .media
            }

            confidence = Self.resolveNowPlayingConfidence(
                appName: foreground.appName,
                appID: foreground.appID,
                title: title,
                subtitle: subtitle,
                source: source
            )
        }

        if let plexMetadata = await resolvePlexNowPlayingMetadata(
            appID: foreground.appID,
            appName: foreground.appName,
            tvIP: currentDevice?.ip,
            existingTitle: title,
            existingSubtitle: subtitle,
            probe: recordProbe
        ) {
            title = Self.preferredMetadataValue(
                existing: title,
                candidate: plexMetadata.title,
                appName: foreground.appName,
                appID: foreground.appID,
                preferTitleSignal: true
            )
            subtitle = Self.preferredMetadataValue(
                existing: subtitle,
                candidate: plexMetadata.subtitle,
                appName: foreground.appName,
                appID: foreground.appID,
                preferTitleSignal: false
            )
            title = Self.sanitizedNowPlayingValue(title, appName: foreground.appName, title: nil)
            subtitle = Self.sanitizedNowPlayingValue(subtitle, appName: foreground.appName, title: title)
            source = .media
            confidence = Self.maxNowPlayingConfidence(confidence, plexMetadata.confidence)
            metadataRestrictionReason = nil
        }

        if title == nil,
           subtitle == nil,
           let restrictionReason = Self.restrictedMetadataReason(
                appID: foreground.appID,
                appName: foreground.appName
           ) {
            metadataRestrictionReason = restrictionReason
        }

        lastNowPlayingProbeSummary = Self.buildNowPlayingProbeSummary(
            appID: foreground.appID,
            appName: foreground.appName,
            title: title,
            subtitle: subtitle,
            source: source,
            confidence: confidence,
            probes: probeEntries
        )

        return TVNowPlayingState(
            appName: foreground.appName,
            appID: foreground.appID,
            title: title,
            subtitle: subtitle,
            source: source,
            confidence: confidence,
            metadataRestrictionReason: metadataRestrictionReason
        )
    }

    private func resolveAppSpecificNowPlayingMetadata(
        appID: String,
        appName: String,
        existingTitle: String?,
        existingSubtitle: String?,
        probe: ((String) -> Void)? = nil
    ) async -> (title: String?, subtitle: String?)? {
        let normalizedAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedAppID == Self.youtubeTVAppID else { return nil }

        guard shouldRunAppSpecificNowPlayingProbe(for: normalizedAppID) else {
            probe?("appFallback:\(normalizedAppID):cooldown")
            return nil
        }

        var bestTitle = Self.sanitizedNowPlayingValue(existingTitle, appName: appName, title: nil)
        var bestSubtitle = Self.sanitizedNowPlayingValue(existingSubtitle, appName: appName, title: bestTitle)
        let initialScore = Self.metadataPairScore(
            title: bestTitle,
            subtitle: bestSubtitle,
            appName: appName,
            appID: appID
        )
        var bestScore = initialScore

        let attempts: [(uri: String, payload: [String: Any]?, label: String)] = [
            (LGWebOSURI.getAppStatus, ["appId": appID], "appStatus(appId)"),
            (LGWebOSURI.getAppStatus, ["id": appID], "appStatus(id)"),
            (LGWebOSURI.getAppStatus, ["appID": appID], "appStatus(appID)"),
            (LGWebOSURI.getAppState, ["id": appID], "appState(id)"),
            (LGWebOSURI.getAppState, ["appId": appID], "appState(appId)"),
            (LGWebOSURI.getForegroundAppInfo, ["id": appID, "extraInfo": true], "foreground(id,extraInfo)"),
            (LGWebOSURI.getForegroundAppInfo, ["appId": appID, "extraInfo": true], "foreground(appId,extraInfo)")
        ]

        for attempt in attempts {
            probe?("appFallback:\(normalizedAppID):\(attempt.label)")
            guard let response = await requestNowPlayingURI(
                attempt.uri,
                payload: attempt.payload,
                probe: probe
            ) else { continue }

            let genericMetadata = Self.parseMetadataHints(
                from: response,
                appName: appName,
                appID: appID
            )
            let youtubeMetadata = Self.parseYouTubeTVMetadata(
                from: response,
                appName: appName,
                appID: appID
            )

            var candidateTitle = bestTitle
            var candidateSubtitle = bestSubtitle

            candidateTitle = Self.preferredMetadataValue(
                existing: candidateTitle,
                candidate: genericMetadata.title,
                appName: appName,
                appID: appID,
                preferTitleSignal: true
            )
            candidateTitle = Self.preferredMetadataValue(
                existing: candidateTitle,
                candidate: youtubeMetadata.title,
                appName: appName,
                appID: appID,
                preferTitleSignal: true
            )

            candidateSubtitle = Self.preferredMetadataValue(
                existing: candidateSubtitle,
                candidate: genericMetadata.subtitle,
                appName: appName,
                appID: appID,
                preferTitleSignal: false
            )
            candidateSubtitle = Self.preferredMetadataValue(
                existing: candidateSubtitle,
                candidate: youtubeMetadata.subtitle,
                appName: appName,
                appID: appID,
                preferTitleSignal: false
            )

            candidateTitle = Self.sanitizedNowPlayingValue(candidateTitle, appName: appName, title: nil)
            candidateSubtitle = Self.sanitizedNowPlayingValue(candidateSubtitle, appName: appName, title: candidateTitle)

            let candidateScore = Self.metadataPairScore(
                title: candidateTitle,
                subtitle: candidateSubtitle,
                appName: appName,
                appID: appID
            )
            if candidateScore > bestScore {
                bestScore = candidateScore
                bestTitle = candidateTitle
                bestSubtitle = candidateSubtitle
            }
        }

        guard bestScore > initialScore else {
            probe?("appFallback:\(normalizedAppID):no-improvement")
            return nil
        }

        probe?("appFallback:\(normalizedAppID):improved(\(initialScore)->\(bestScore))")
        return (title: bestTitle, subtitle: bestSubtitle)
    }

    func plexMetadataConfiguration() -> TVPlexMetadataConfiguration {
        let serverURL = defaults.string(forKey: plexServerURLDefaultsKey) ?? ""
        let token = (try? keychain.string(for: plexTokenKeychainKey)) ?? ""
        return TVPlexMetadataConfiguration(serverURL: serverURL, token: token)
    }

    func updatePlexMetadataConfiguration(serverURL: String, token: String) throws {
        let trimmedServerURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedServerURL.isEmpty && trimmedToken.isEmpty {
            defaults.removeObject(forKey: plexServerURLDefaultsKey)
            try keychain.removeValue(for: plexTokenKeychainKey)
            plexMetadataCacheByTVIP.removeAll()
            plexLastMetadataRequestAtByTVIP.removeAll()
            return
        }

        guard let normalizedServerURL = normalizedPlexServerURLString(trimmedServerURL) else {
            throw TVControllerError.networkFailure("Enter a valid Plex server URL (example: http://192.168.1.20:32400).")
        }
        guard !trimmedToken.isEmpty else {
            throw TVControllerError.networkFailure("Enter a Plex token.")
        }

        defaults.set(normalizedServerURL, forKey: plexServerURLDefaultsKey)
        try keychain.set(trimmedToken, for: plexTokenKeychainKey)
        plexMetadataCacheByTVIP.removeAll()
        plexLastMetadataRequestAtByTVIP.removeAll()
    }

    private func resolvePlexNowPlayingMetadata(
        appID: String?,
        appName: String,
        tvIP: String?,
        existingTitle: String?,
        existingSubtitle: String?,
        probe: ((String) -> Void)? = nil
    ) async -> LGPlexMetadataSnapshot? {
        guard Self.looksLikePlexApp(appID: appID, appName: appName) else {
            return nil
        }

        guard let configuration = normalizedPlexConfiguration() else {
            probe?("plex:config-missing")
            return nil
        }

        let tvIPKey = tvIP?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nonEmpty ?? "unknown"
        let now = Date()
        if let lastRequestAt = plexLastMetadataRequestAtByTVIP[tvIPKey],
           now.timeIntervalSince(lastRequestAt) < plexMetadataRequestCooldown,
           let cached = plexMetadataCacheByTVIP[tvIPKey] {
            probe?("plex:cache")
            return cached
        }

        plexLastMetadataRequestAtByTVIP[tvIPKey] = now
        guard let sessions = await requestPlexSessions(using: configuration, probe: probe) else {
            return nil
        }
        guard let selection = selectPlexSession(from: sessions, tvIP: tvIP) else {
            probe?("plex:no-matching-session")
            return nil
        }

        var metadata = Self.plexMetadataSnapshot(
            from: selection.session,
            appName: appName,
            appID: appID,
            existingTitle: existingTitle,
            existingSubtitle: existingSubtitle
        )
        metadata.confidence = selection.confidence

        guard metadata.title != nil || metadata.subtitle != nil else {
            probe?("plex:no-title")
            return nil
        }

        plexMetadataCacheByTVIP[tvIPKey] = metadata
        probe?("plex:matched(\(selection.confidence.shortLabel.lowercased()))")
        return metadata
    }

    private func requestPlexSessions(
        using configuration: LGPlexConfiguration,
        probe: ((String) -> Void)? = nil
    ) async -> [LGPlexSession]? {
        let sessionsPathURL = configuration.serverURL.appendingPathComponent("status/sessions")
        guard var components = URLComponents(url: sessionsPathURL, resolvingAgainstBaseURL: false) else {
            probe?("plex:invalid-url")
            return nil
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "X-Plex-Token", value: configuration.token))
        components.queryItems = queryItems

        guard let requestURL = components.url else {
            probe?("plex:invalid-url")
            return nil
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = plexMetadataTimeout
        request.setValue("application/xml,text/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(AppBranding.displayName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue("iOS", forHTTPHeaderField: "X-Plex-Platform")
        request.setValue("1.0", forHTTPHeaderField: "X-Plex-Version")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        probe?("plex:auth-failed")
                    } else {
                        probe?("plex:http-\(httpResponse.statusCode)")
                    }
                    return nil
                }
            }

            let sessions = LGPlexSessionsParser.parse(data)
            probe?("plex:sessions-\(sessions.count)")
            return sessions
        } catch {
            probe?("plex:\(Self.nowPlayingErrorLabel(from: error))")
            return nil
        }
    }

    private func selectPlexSession(
        from sessions: [LGPlexSession],
        tvIP: String?
    ) -> LGPlexSessionSelection? {
        guard !sessions.isEmpty else { return nil }

        let activeStates: Set<String> = ["playing", "paused", "buffering"]
        let activeSessions = sessions.filter { session in
            let state = session.playerState?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard let state, !state.isEmpty else { return true }
            return activeStates.contains(state)
        }
        let candidates = activeSessions.isEmpty ? sessions : activeSessions

        if let tvIP = tvIP?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let matchedByAddress = candidates.first(where: { session in
               session.playerAddress?
                   .trimmingCharacters(in: .whitespacesAndNewlines)
                   .lowercased() == tvIP
           }) {
            return LGPlexSessionSelection(session: matchedByAddress, confidence: .high)
        }

        if candidates.count == 1, let single = candidates.first {
            return LGPlexSessionSelection(session: single, confidence: .medium)
        }

        if let likelyTVSession = candidates.first(where: { session in
            let playerTitle = session.playerTitle?.lowercased() ?? ""
            return playerTitle.contains("lg")
                || playerTitle.contains("webos")
                || playerTitle.contains("tv")
        }) {
            return LGPlexSessionSelection(session: likelyTVSession, confidence: .medium)
        }

        return candidates.first.map { LGPlexSessionSelection(session: $0, confidence: .low) }
    }

    private static func plexMetadataSnapshot(
        from session: LGPlexSession,
        appName: String,
        appID: String?,
        existingTitle: String?,
        existingSubtitle: String?
    ) -> LGPlexMetadataSnapshot {
        let normalizedType = session.type.lowercased()
        let sessionTitle = sanitizedNowPlayingValue(session.title, appName: appName, title: nil)
        let sessionSeries = sanitizedNowPlayingValue(session.grandparentTitle, appName: appName, title: sessionTitle)
        let sessionSeason = sanitizedNowPlayingValue(session.parentTitle, appName: appName, title: sessionTitle)

        var title = sessionTitle
        var subtitle: String?

        switch normalizedType {
        case "episode":
            title = title ?? sanitizedNowPlayingValue(existingTitle, appName: appName, title: nil)
            subtitle = sessionSeries ?? sessionSeason
        case "track":
            title = title ?? sanitizedNowPlayingValue(existingTitle, appName: appName, title: nil)
            subtitle =
                sessionSeries ??
                sanitizedNowPlayingValue(session.originalTitle, appName: appName, title: title) ??
                sessionSeason
        default:
            title = title ?? sanitizedNowPlayingValue(existingTitle, appName: appName, title: nil)
            subtitle =
                sessionSeries ??
                sessionSeason ??
                sanitizedNowPlayingValue(session.originalTitle, appName: appName, title: title)
        }

        subtitle = sanitizedNowPlayingValue(subtitle, appName: appName, title: title)
        if subtitle == nil {
            subtitle = sanitizedNowPlayingValue(existingSubtitle, appName: appName, title: title)
        }

        return LGPlexMetadataSnapshot(title: title, subtitle: subtitle, confidence: .medium)
    }

    private func normalizedPlexConfiguration() -> LGPlexConfiguration? {
        let rawServerURL = defaults.string(forKey: plexServerURLDefaultsKey) ?? ""
        let rawToken = (try? keychain.string(for: plexTokenKeychainKey)) ?? ""
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        guard let normalizedServerURL = normalizedPlexServerURLString(rawServerURL),
              let url = URL(string: normalizedServerURL) else {
            return nil
        }
        return LGPlexConfiguration(serverURL: url, token: token)
    }

    private func normalizedPlexServerURLString(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "http://\(trimmed)"
        }

        guard let url = URL(string: withScheme), let scheme = url.scheme, let host = url.host else {
            return nil
        }
        guard (scheme == "http" || scheme == "https"), !host.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port ?? 32400
        components.path = ""
        return components.string
    }

    private func shouldRunAppSpecificNowPlayingProbe(for normalizedAppID: String) -> Bool {
        let now = Date()
        if let lastProbeDate = appSpecificNowPlayingProbeTimestamps[normalizedAppID],
           now.timeIntervalSince(lastProbeDate) < appSpecificNowPlayingProbeCooldown {
            return false
        }
        appSpecificNowPlayingProbeTimestamps[normalizedAppID] = now
        return true
    }

    private func requestNowPlayingURI(
        _ uri: String,
        payload: [String: Any]? = nil,
        probe: ((String) -> Void)? = nil
    ) async -> [String: Any]? {
        let compactURI = Self.compactNowPlayingURI(uri)
        if unsupportedNowPlayingURIs.contains(uri) {
            probe?("\(compactURI):unsupported(cached)")
            return nil
        }

        do {
            let response = try await socketClient.request(
                uri: uri,
                payload: payload,
                timeout: metadataProbeTimeout
            )
            let keySummary = Self.payloadKeySummary(from: response)
            probe?("\(compactURI):ok[\(keySummary)]")
            return response
        } catch {
            if isUnsupportedMethodError(error) {
                unsupportedNowPlayingURIs.insert(uri)
            }
            probe?("\(compactURI):\(Self.nowPlayingErrorLabel(from: error))")
            return nil
        }
    }

    private func refreshAppNameCacheIfNeeded(force: Bool = false) async {
        let now = Date()
        if !force,
           let appNameCacheUpdatedAt,
           now.timeIntervalSince(appNameCacheUpdatedAt) < appNameCacheTTL,
           !appNameCacheByID.isEmpty {
            return
        }

        var refreshedCatalog: [String: String] = [:]

        if let launchResponse = await requestNowPlayingURI(LGWebOSURI.listLaunchPoints) {
            mergeCatalog(Self.parseAppCatalog(from: launchResponse), into: &refreshedCatalog)
        }

        if let appListResponse = await requestNowPlayingURI(LGWebOSURI.listApps) {
            mergeCatalog(Self.parseAppCatalog(from: appListResponse), into: &refreshedCatalog)
        }

        if !refreshedCatalog.isEmpty {
            mergeCatalog(refreshedCatalog, into: &appNameCacheByID)
            appNameCacheUpdatedAt = now
        }
    }

    private func mergeAppNameCache(with apps: [TVAppShortcut]) {
        for app in apps {
            let normalizedID = app.appID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedTitle = app.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty, !normalizedTitle.isEmpty else { continue }
            appNameCacheByID[normalizedID] = normalizedTitle
        }
        if !apps.isEmpty {
            appNameCacheUpdatedAt = Date()
        }
    }

    private func resolvedAppName(for appID: String?, fallbackName: String) -> String {
        let fallback = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let appID, !appID.isEmpty else {
            return fallback.isEmpty ? "Unknown App" : fallback
        }

        let normalizedID = appID.lowercased()
        if let cached = appNameCacheByID[normalizedID], !cached.isEmpty {
            return cached
        }
        if let alias = Self.knownAppAliases[normalizedID], !alias.isEmpty {
            return alias
        }
        if !fallback.isEmpty, !Self.looksLikeBundleIdentifier(fallback) {
            return fallback
        }
        return Self.humanReadableAppName(from: appID)
    }

    func ping() async -> Bool {
        guard currentDevice != nil else { return false }
        do {
            _ = try await socketClient.request(
                uri: LGWebOSURI.getServiceList,
                timeout: pingTimeout
            )
            return true
        } catch {
            pingFailureCount += 1
            recordCommandError(error, command: nil)
            if isTransientConnectionError(error) {
                scheduleReconnectWithBackoff()
            }
            return false
        }
    }

    func diagnosticsSnapshot() -> TVDiagnosticsSnapshot {
        let device = currentDevice ?? knownDevicesStore.lastConnectedDevice()
        let capabilities = (device?.capabilities ?? [])
            .sorted { $0.rawValue < $1.rawValue }

        return TVDiagnosticsSnapshot(
            timestamp: Date(),
            connectionStateLabel: stateMachine.state.shortLabel,
            deviceName: device?.name ?? "No TV",
            deviceIP: device?.ip ?? "N/A",
            endpointPort: device?.port,
            commandTransport: buttonTransportMode.label,
            reconnectAttempts: reconnectAttemptsTotal,
            commandRetryCount: commandRetryCount,
            pingFailureCount: pingFailureCount,
            lastAutoRecoveryAt: lastAutoRecoveryAt,
            lastErrorCode: lastCommandError?.code,
            lastErrorMessage: lastCommandError?.message,
            lastFailedCommand: lastCommandError?.commandKey,
            lastErrorAt: lastCommandError?.timestamp,
            serviceNames: currentServiceNames.sorted(),
            supportedCapabilities: capabilities,
            nowPlayingProbeSummary: lastNowPlayingProbeSummary,
            commandLatencyTelemetry: buildCommandLatencyTelemetry()
        )
    }

    func sendCommand(_ command: TVCommand) async throws {
        switch command {
        case .up:
            _ = try await sendButton("UP")
        case .down:
            _ = try await sendButton("DOWN")
        case .left:
            _ = try await sendButton("LEFT")
        case .right:
            _ = try await sendButton("RIGHT")
        case .select:
            _ = try await sendButton("ENTER")
        case .back:
            _ = try await sendButton("BACK")
        case .home:
            _ = try await sendButton("HOME")
        case .menu:
            _ = try await sendButton("MENU")
        case .volumeUp:
            _ = try await socketClient.request(
                uri: LGWebOSURI.volumeUp,
                timeout: controlCommandTimeout
            )
        case .volumeDown:
            _ = try await socketClient.request(
                uri: LGWebOSURI.volumeDown,
                timeout: controlCommandTimeout
            )
        case let .setVolume(level):
            let clamped = max(0, min(100, level))
            _ = try await socketClient.request(
                uri: LGWebOSURI.setVolume,
                payload: ["volume": clamped],
                timeout: controlCommandTimeout
            )
        case let .mute(muted):
            _ = try await socketClient.request(
                uri: LGWebOSURI.setMute,
                payload: ["mute": muted ?? true],
                timeout: controlCommandTimeout
            )
        case .powerOff:
            suppressNextDisconnectFailure = true
            _ = try await socketClient.request(
                uri: LGWebOSURI.turnOff,
                timeout: stateQueryTimeout
            )
        case .powerOn:
            try await powerOnViaWakeOnLAN()
        case let .launchApp(appID):
            _ = try await socketClient.request(
                uri: LGWebOSURI.launchApp,
                payload: ["id": appID],
                timeout: launchDataTimeout
            )
        case let .inputSwitch(inputID):
            _ = try await socketClient.request(
                uri: LGWebOSURI.switchInput,
                payload: ["inputId": inputID],
                timeout: stateQueryTimeout
            )
        case let .keyboardText(text):
            // NOTE: verify IME payload shape for your target webOS firmware.
            _ = try await socketClient.request(
                uri: LGWebOSURI.insertText,
                payload: ["text": text, "replace": 0],
                timeout: controlCommandTimeout
            )
        }
    }

    func reconnectToLastDeviceIfPossible() async {
        if stateMachine.state.isConnected {
            return
        }

        let candidate = currentDevice ?? knownDevicesStore.lastConnectedDevice()
        guard let candidate else { return }

        do {
            markNextReconnectAsAutoRecovery = true
            try await connect(to: candidate, asReconnection: true)
        } catch {
            if Self.isCancellation(error) {
                return
            }
            applyTransition(.fail(error.userFacingMessage))
        }
    }

    private func sendButton(_ name: String) async throws -> [String: Any] {
        if buttonTransportMode == .pointerSocket {
            try await socketClient.sendPointerButton(name)
            return [:]
        }

        do {
            return try await socketClient.request(
                uri: LGWebOSURI.sendButton,
                payload: ["name": name],
                timeout: controlCommandTimeout
            )
        } catch {
            guard shouldFallbackToPointerButton(after: error) else {
                throw error
            }
            try await socketClient.sendPointerButton(name)
            buttonTransportMode = .pointerSocket
            return [:]
        }
    }

    private func bindCallbacks() {
        discoveryService.onDevicesChanged = { [weak self] devices in
            guard let self else { return }
            discoveredDevices = devices
            onDevicesChanged?(devices)

            for device in devices {
                knownDevicesStore.upsert(device)
            }
            knownDevices = knownDevicesStore.loadDevices()
            onKnownDevicesChanged?(knownDevices)

            if !stateMachine.state.isConnected {
                applyTransition(.foundDevices(devices.count))
            }
        }

        discoveryService.onFailure = { [weak self] error in
            self?.applyTransition(.fail(error.localizedDescription))
        }

        socketClient.onPairingPrompt = { [weak self] in
            guard let self, let pairingDevice = self.pendingPairDevice else { return }
            self.applyTransition(.beginPairing(pairingDevice))
        }

        socketClient.onDisconnected = { [weak self] reason in
            guard let self else { return }
            if self.suppressNextDisconnectFailure {
                self.suppressNextDisconnectFailure = false
                self.reconnectAttemptCount = 0
                self.postConnectHydrationTask?.cancel()
                self.postConnectHydrationTask = nil
                self.buttonTransportWarmupTask?.cancel()
                self.buttonTransportWarmupTask = nil
                self.silentKeepAliveFailureCount = 0
                self.applyTransition(.disconnect)
                return
            }
            let message = reason ?? "Connection to the TV was lost."
            self.recordCommandError(message: message, command: nil)
            self.postConnectHydrationTask?.cancel()
            self.postConnectHydrationTask = nil
            self.buttonTransportWarmupTask?.cancel()
            self.buttonTransportWarmupTask = nil
            self.silentKeepAliveFailureCount = 0
            self.applyTransition(.fail(message))
            self.scheduleReconnectWithBackoff()
        }
    }

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePathUpdate(isSatisfied: path.status == .satisfied)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func handlePathUpdate(isSatisfied: Bool) {
        let becameReachable = isSatisfied && !isNetworkReachable
        isNetworkReachable = isSatisfied
        if !isSatisfied {
            reconnectTask?.cancel()
            reconnectTask = nil
            return
        }
        if becameReachable {
            reconnectAttemptCount = 0
            Task { [weak self] in
                await self?.reconnectToLastDeviceIfPossible()
            }
        }
    }

    private func scheduleReconnectWithBackoff() {
        guard isNetworkReachable else { return }
        guard currentDevice != nil || knownDevicesStore.lastConnectedDevice() != nil else { return }

        if reconnectAttemptCount == 0 {
            reconnectAttemptCount = 1
            scheduleReconnect(after: 0.05)
            return
        }

        let exponent = min(reconnectAttemptCount - 1, 6)
        let baseDelay = min(0.30 * pow(1.70, Double(exponent)), 6.5)
        let jitter = Double.random(in: 0...0.12)
        reconnectAttemptCount += 1
        scheduleReconnect(after: baseDelay + jitter)
    }

    private func scheduleReconnect(after seconds: TimeInterval) {
        guard isNetworkReachable else { return }
        guard !stateMachine.state.isConnected else { return }
        guard let reconnectCandidate = currentDevice ?? knownDevicesStore.lastConnectedDevice() else {
            return
        }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            let nanos = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled else { return }
            do {
                self.markNextReconnectAsAutoRecovery = true
                try await self.connect(to: reconnectCandidate, asReconnection: true)
            } catch {
                if Self.isCancellation(error) {
                    return
                }
                self.applyTransition(.fail(error.userFacingMessage))
            }
        }
    }

    private func recoverConnectionForCommandRetry(using device: TVDevice) async throws {
        commandRetryCount += 1
        markNextReconnectAsAutoRecovery = true
        postConnectHydrationTask?.cancel()
        postConnectHydrationTask = nil
        buttonTransportWarmupTask?.cancel()
        buttonTransportWarmupTask = nil
        silentKeepAliveTask?.cancel()
        silentKeepAliveTask = nil
        silentKeepAliveFailureCount = 0
        socketClient.disconnect(emitEvent: false)
        buttonTransportMode = .ssapSendButton
        currentServiceNames.removeAll()
        try await connect(to: device, asReconnection: true)
    }

    private func startSilentKeepAliveLoop() {
        silentKeepAliveTask?.cancel()
        silentKeepAliveTask = nil
        silentKeepAliveFailureCount = 0

        silentKeepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let intervalNanoseconds = UInt64(self.silentKeepAliveInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                guard !Task.isCancelled else { return }

                guard self.stateMachine.state.isConnected, self.currentDevice != nil else {
                    self.silentKeepAliveFailureCount = 0
                    continue
                }

                // Skip keepalive right after active user input to avoid unnecessary traffic.
                if Date().timeIntervalSince(self.lastCommandDispatchAt) < self.silentKeepAliveCommandGracePeriod {
                    continue
                }

                let isHealthy = await self.socketClient.sendPing(timeout: self.silentKeepAliveTimeout)
                if isHealthy {
                    self.silentKeepAliveFailureCount = 0
                    continue
                }

                self.silentKeepAliveFailureCount += 1
                guard self.silentKeepAliveFailureCount >= 2 else { continue }

                self.silentKeepAliveFailureCount = 0
                self.markNextReconnectAsAutoRecovery = true
                self.reconnectAttemptCount = 0
                self.socketClient.disconnect(emitEvent: false)
                self.scheduleReconnectWithBackoff()
            }
        }
    }

    private func startPostConnectOptimization(for device: TVDevice) {
        postConnectHydrationTask?.cancel()
        postConnectHydrationTask = Task { [weak self] in
            guard let self else { return }
            let hydrated = await self.hydrateDeviceContext(device)
            guard !Task.isCancelled else { return }
            guard self.currentDevice?.id == device.id else { return }

            var normalizedHydrated = hydrated
            normalizedHydrated.port = device.port
            normalizedHydrated.lastConnectedAt = device.lastConnectedAt
            normalizedHydrated.wakeMACAddress = device.wakeMACAddress
            self.currentDevice = normalizedHydrated

            self.knownDevicesStore.markConnected(normalizedHydrated)
            self.knownDevices = self.knownDevicesStore.loadDevices()
            self.onKnownDevicesChanged?(self.knownDevices)
            self.refreshWidgetCommandContext(for: normalizedHydrated)

            if self.stateMachine.state.isConnected {
                self.applyTransition(.didConnect(normalizedHydrated))
            }
        }

        buttonTransportWarmupTask?.cancel()
        buttonTransportWarmupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.socketClient.prewarmPointerSocket()
                guard !Task.isCancelled else { return }
                guard self.currentDevice?.id == device.id else { return }
                self.buttonTransportMode = .pointerSocket
            } catch {
                guard self.currentDevice?.id == device.id else { return }
                self.buttonTransportMode = .ssapSendButton
            }
        }
    }

    private func probeTCP(host: String, port: UInt16, timeout: TimeInterval = 0.35) async -> Bool {
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
            let queue = DispatchQueue(label: "com.reggieboi.tvremote.controller.probe.\(host).\(port)")
            let completionGate = LGProbeCompletionGate()
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

    private func applyTransition(_ event: TVConnectionEvent) {
        let state = stateMachine.transition(event)
        onStateChanged?(state)
    }

    private func connectionEndpoints(for device: TVDevice) -> [LGConnectionEndpoint] {
        var endpoints: [LGConnectionEndpoint] = []
        var seen = Set<LGConnectionEndpoint>()

        func append(_ endpoint: LGConnectionEndpoint) {
            guard seen.insert(endpoint).inserted else { return }
            endpoints.append(endpoint)
        }

        append(LGConnectionEndpoint(port: device.port, secure: device.port == 3001))
        append(LGConnectionEndpoint(port: 3000, secure: false))
        append(LGConnectionEndpoint(port: 3001, secure: true))

        return endpoints
    }

    private func shouldTryNextEndpoint(after error: Error) -> Bool {
        let message = error.userFacingMessage.lowercased()
        if message.contains("denied") || message.contains("rejected") {
            return false
        }
        return true
    }

    private func shouldRetryCommand(command: TVCommand, after error: Error) -> Bool {
        guard isSafeForRetry(command) else { return false }
        guard !isUnsupportedMethodError(error) else { return false }
        return isTransientConnectionError(error)
    }

    private func isSafeForRetry(_ command: TVCommand) -> Bool {
        switch command {
        case .powerOff, .keyboardText:
            return false
        default:
            return true
        }
    }

    private func isTransientConnectionError(_ error: Error) -> Bool {
        if Self.isCancellation(error) {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let transientCodes: Set<Int> = [
                NSURLErrorTimedOut,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorCannotFindHost
            ]
            if transientCodes.contains(nsError.code) {
                return true
            }
        }

        let message = error.userFacingMessage.lowercased()
        return message.contains("timed out")
            || message.contains("timeout")
            || message.contains("not connected")
            || message.contains("connection was lost")
            || message.contains("socket is not connected")
            || message.contains("network failure")
            || message.contains("broken pipe")
            || message.contains("econnreset")
    }

    private func isTimeoutError(_ error: Error) -> Bool {
        if case LGWebOSSocketError.requestTimedOut = error {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
            return true
        }

        let message = error.userFacingMessage.lowercased()
        return message.contains("timeout")
            || message.contains("timed out")
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        let message = error.userFacingMessage.lowercased()
        return message == "cancelled"
            || message == "canceled"
            || message.contains("cancelled")
            || message.contains("canceled")
    }

    private func shouldFallbackToPointerButton(after error: Error) -> Bool {
        let message = error.userFacingMessage.lowercased()
        return message.contains("404")
            || message.contains("not found")
            || message.contains("no such service")
            || message.contains("no such method")
            || message.contains("networkinput")
            || message.contains("unsupported")
            || message.contains("unknown uri")
    }

    private func shouldRetryPairingWithoutClientKey(after error: Error) -> Bool {
        let message = error.userFacingMessage.lowercased()
        return message.contains("client-key")
            || message.contains("401")
            || message.contains("403")
            || message.contains("not registered")
            || message.contains("not authorized")
            || message.contains("authentication")
    }

    private func recordCommandError(_ error: Error, command: TVCommand?) {
        recordCommandError(message: error.userFacingMessage, command: command)
    }

    private func recordCommandError(message: String, command: TVCommand?) {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        lastCommandError = LGCommandErrorSnapshot(
            code: Self.parseErrorCode(from: normalized),
            message: normalized,
            commandKey: command?.rateLimitKey,
            timestamp: Date()
        )
    }

    private static func parseErrorCode(from message: String) -> Int? {
        let numericParts = message.split(whereSeparator: { !$0.isNumber })
        for part in numericParts {
            guard let value = Int(part) else { continue }
            if (100...599).contains(value) {
                return value
            }
        }
        return nil
    }

    private func recordCommandLatency(
        command: TVCommand,
        startedAt: Date,
        success: Bool,
        error: Error?
    ) {
        let elapsedMs = max(Int((Date().timeIntervalSince(startedAt) * 1000).rounded()), 0)
        let timedOut = error.map(isTimeoutError) ?? false

        commandLatencyEvents.append(
            CommandLatencyEvent(
                commandKey: command.rateLimitKey,
                latencyMs: elapsedMs,
                succeeded: success,
                timedOut: timedOut,
                capturedAt: Date()
            )
        )

        if commandLatencyEvents.count > commandLatencyWindowSize {
            commandLatencyEvents.removeFirst(commandLatencyEvents.count - commandLatencyWindowSize)
        }
    }

    private func buildCommandLatencyTelemetry() -> TVCommandLatencyTelemetry {
        let events = commandLatencyEvents
        guard !events.isEmpty else { return .empty }

        let sortedLatencies = events.map(\.latencyMs).sorted()
        let averageMs = Int((Double(sortedLatencies.reduce(0, +)) / Double(sortedLatencies.count)).rounded())
        let p50Ms = percentileLatency(0.50, in: sortedLatencies)
        let p95Ms = percentileLatency(0.95, in: sortedLatencies)
        let successfulCount = events.reduce(0) { $0 + ($1.succeeded ? 1 : 0) }
        let timeoutCount = events.reduce(0) { $0 + ($1.timedOut ? 1 : 0) }
        let last = events.last

        return TVCommandLatencyTelemetry(
            windowSampleCount: events.count,
            successfulCount: successfulCount,
            timeoutCount: timeoutCount,
            lastCommandKey: last?.commandKey,
            lastLatencyMs: last?.latencyMs,
            lastWasSuccess: last?.succeeded ?? false,
            lastWasTimeout: last?.timedOut ?? false,
            averageLatencyMs: averageMs,
            p50LatencyMs: p50Ms,
            p95LatencyMs: p95Ms
        )
    }

    private func percentileLatency(_ percentile: Double, in sortedLatencies: [Int]) -> Int? {
        guard !sortedLatencies.isEmpty else { return nil }
        let normalized = min(max(percentile, 0), 1)
        let index = Int((Double(sortedLatencies.count - 1) * normalized).rounded())
        return sortedLatencies[index]
    }

    private func shouldMarkCapabilityUnsupported(command: TVCommand, after error: Error) -> Bool {
        guard isUnsupportedMethodError(error) else { return false }
        guard let capability = capability(for: command) else { return false }
        guard currentDevice?.capabilities.contains(capability) == true else { return false }
        return true
    }

    private func isUnsupportedMethodError(_ error: Error) -> Bool {
        let message = error.userFacingMessage.lowercased()
        return message.contains("404")
            || message.contains("not found")
            || message.contains("no such service")
            || message.contains("no such method")
            || message.contains("unsupported")
            || message.contains("unknown uri")
    }

    private func capability(for command: TVCommand) -> TVCapability? {
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
        case .powerOn, .powerOff:
            return .power
        case .launchApp:
            return .launchApp
        case .inputSwitch:
            return .inputSwitch
        case .keyboardText:
            return nil
        }
    }

    private func markCapabilityUnsupported(_ capability: TVCapability, on deviceID: String) {
        guard var connected = currentDevice, connected.id == deviceID else { return }
        guard connected.capabilities.remove(capability) != nil else { return }

        currentDevice = connected
        knownDevicesStore.upsert(connected)
        knownDevices = knownDevicesStore.loadDevices()
        onKnownDevicesChanged?(knownDevices)

        if stateMachine.state.isConnected {
            applyTransition(.didConnect(connected))
        }
    }

    private func hydrateDeviceContext(_ device: TVDevice) async -> TVDevice {
        var hydrated = device

        let servicesResponse = try? await socketClient.request(
            uri: LGWebOSURI.getServiceList,
            timeout: stateQueryTimeout
        )
        if let servicesResponse {
            let parsedServiceNames = Self.parseServiceNames(from: servicesResponse)
            currentServiceNames = parsedServiceNames
            if !parsedServiceNames.isEmpty {
                hydrated.capabilities = Self.inferCapabilities(
                    from: parsedServiceNames,
                    fallback: hydrated.capabilities
                )
            }
        } else {
            currentServiceNames.removeAll()
        }

        if let launchResponse = try? await socketClient.request(
            uri: LGWebOSURI.listLaunchPoints,
            timeout: launchDataTimeout
        ) {
            let launchApps = Self.parseLaunchApps(from: launchResponse, tvHost: device.ip)
            mergeAppNameCache(with: launchApps)
            if !launchApps.isEmpty {
                hydrated.capabilities.insert(.launchApp)
            }
        }

        if let appListResponse = await requestNowPlayingURI(LGWebOSURI.listApps) {
            let catalog = Self.parseAppCatalog(from: appListResponse)
            if !catalog.isEmpty {
                mergeCatalog(catalog, into: &appNameCacheByID)
                appNameCacheUpdatedAt = Date()
            }
        }

        return hydrated
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

    private func keychainKey(for device: TVDevice) -> String {
        "lg.webos.clientKey.\(device.id.lowercased())"
    }

    private func refreshWidgetCommandContext(for device: TVDevice) {
        let clientKey = (try? keychain.string(for: keychainKey(for: device))) ?? nil
        guard let clientKey, !clientKey.isEmpty else {
            return
        }

        let context = TVWidgetCommandContext(
            deviceID: device.id,
            ip: device.ip,
            port: device.port,
            secure: device.port == 3001,
            clientKey: clientKey,
            updatedAt: Date()
        )

        try? widgetContextStore.save(context)
    }

    private func powerOnViaWakeOnLAN() async throws {
        let lastKnown = knownDevicesStore.lastConnectedDevice()
        let preferredDevice = currentDevice ?? lastKnown
        guard let preferredDevice else {
            throw TVControllerError.noDeviceSelected
        }

        let wakeMAC = preferredDevice.wakeMACAddress
            ?? knownDevices.first(where: { $0.id == preferredDevice.id })?.wakeMACAddress
            ?? lastKnown?.wakeMACAddress

        guard
            let rawMAC = wakeMAC,
            let normalizedMAC = WakeOnLANService.normalizedMACAddress(rawMAC)
        else {
            throw TVControllerError.invalidWakeMACAddress
        }

        try await WakeOnLANService.sendMagicPacket(
            macAddress: normalizedMAC,
            preferredHost: preferredDevice.ip
        )
    }

    func updateWakeMACAddress(_ macAddress: String?, for deviceID: String?) throws {
        let targetID = deviceID ?? currentDevice?.id ?? knownDevicesStore.lastConnectedDevice()?.id
        guard let targetID else { throw TVControllerError.noDeviceSelected }

        let trimmed = macAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized: String?
        if trimmed.isEmpty {
            normalized = nil
        } else {
            guard let parsed = WakeOnLANService.normalizedMACAddress(trimmed) else {
                throw TVControllerError.invalidWakeMACAddress
            }
            normalized = parsed
        }

        var devices = knownDevicesStore.loadDevices()
        guard let index = devices.firstIndex(where: { $0.id == targetID }) else {
            throw TVControllerError.noDeviceSelected
        }
        devices[index].wakeMACAddress = normalized
        knownDevicesStore.saveDevices(devices)
        knownDevices = knownDevicesStore.loadDevices()
        onKnownDevicesChanged?(knownDevices)

        if currentDevice?.id == targetID {
            currentDevice?.wakeMACAddress = normalized
        }
    }

    private static func parseInputSources(from payload: [String: Any]) -> [TVInputSource] {
        let rawEntries: [[String: Any]] =
            (payload["devices"] as? [[String: Any]]) ??
            (payload["deviceList"] as? [[String: Any]]) ??
            (payload["inputs"] as? [[String: Any]]) ??
            (payload["inputList"] as? [[String: Any]]) ??
            []

        guard !rawEntries.isEmpty else { return [] }

        var seen = Set<String>()
        var sources: [TVInputSource] = []

        for entry in rawEntries {
            let rawInputID =
                (entry["id"] as? String) ??
                (entry["inputId"] as? String) ??
                (entry["appId"] as? String) ??
                ""
            let normalizedInputID = rawInputID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedInputID.isEmpty else { continue }

            let rawTitle =
                (entry["label"] as? String) ??
                (entry["name"] as? String) ??
                normalizedInputID
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceID = normalizedInputID.lowercased()
            guard seen.insert(sourceID).inserted else { continue }

            let icon = iconSystemName(
                inputID: normalizedInputID,
                title: title,
                rawType: entry["type"] as? String
            )

            sources.append(
                TVInputSource(
                    id: sourceID,
                    title: title.isEmpty ? normalizedInputID : title,
                    iconSystemName: icon,
                    inputID: normalizedInputID
                )
            )
        }

        return sources.sorted(by: sortInputSources)
    }

    private static func parseServiceNames(from response: [String: Any]) -> Set<String> {
        let payload = (response["payload"] as? [String: Any]) ?? response
        let serviceEntries: [Any] =
            (payload["services"] as? [Any]) ??
            (payload["serviceList"] as? [Any]) ??
            []

        var names = Set<String>()
        for entry in serviceEntries {
            if let directName = entry as? String {
                let normalized = directName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !normalized.isEmpty {
                    names.insert(normalized)
                }
                continue
            }

            guard let dictionary = entry as? [String: Any] else { continue }
            let rawName =
                (dictionary["name"] as? String) ??
                (dictionary["service"] as? String) ??
                (dictionary["serviceName"] as? String) ??
                (dictionary["uri"] as? String) ??
                ""
            let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty {
                names.insert(normalized)
            }
        }

        return names
    }

    private static func inferCapabilities(
        from serviceNames: Set<String>,
        fallback: Set<TVCapability>
    ) -> Set<TVCapability> {
        guard !serviceNames.isEmpty else { return fallback }

        var capabilities = fallback

        if !containsAnyService(serviceNames, tokens: ["audio"]) {
            capabilities.remove(.volume)
            capabilities.remove(.mute)
        } else {
            capabilities.insert(.volume)
            capabilities.insert(.mute)
        }

        if !containsAnyService(serviceNames, tokens: ["launcher", "applicationmanager"]) {
            capabilities.remove(.launchApp)
        } else {
            capabilities.insert(.launchApp)
        }

        if !containsAnyService(serviceNames, tokens: ["tv", "broadcast"]) {
            capabilities.remove(.inputSwitch)
        } else {
            capabilities.insert(.inputSwitch)
        }

        if !containsAnyService(serviceNames, tokens: ["ime"]) {
            capabilities.remove(.keyboard)
        } else {
            capabilities.insert(.keyboard)
        }

        if !containsAnyService(serviceNames, tokens: ["system"]) {
            capabilities.remove(.power)
        } else {
            capabilities.insert(.power)
        }

        return capabilities
    }

    private static func containsAnyService(_ serviceNames: Set<String>, tokens: [String]) -> Bool {
        for service in serviceNames {
            for token in tokens where service.contains(token) {
                return true
            }
        }
        return false
    }

    private func mergeCatalog(_ source: [String: String], into destination: inout [String: String]) {
        for (rawID, rawTitle) in source {
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !title.isEmpty else { continue }
            destination[id] = title
        }
    }

    private static func parseLaunchApps(
        from response: [String: Any],
        tvHost: String?
    ) -> [TVAppShortcut] {
        let payload = payloadDictionary(from: response)
        let rawEntries = appEntries(from: payload)

        guard !rawEntries.isEmpty else { return [] }

        var seenIDs = Set<String>()
        var apps: [TVAppShortcut] = []

        for entry in rawEntries {
            let rawAppID =
                (entry["id"] as? String) ??
                (entry["appId"] as? String) ??
                (entry["appid"] as? String) ??
                ""
            let appID = rawAppID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !appID.isEmpty else { continue }
            let loweredID = appID.lowercased()

            let rawTitle =
                (entry["title"] as? String) ??
                (entry["appName"] as? String) ??
                (entry["visibleName"] as? String) ??
                (entry["name"] as? String) ??
                knownAppAliases[loweredID] ??
                humanReadableAppName(from: appID)
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            guard seenIDs.insert(loweredID).inserted else { continue }

            let iconURLString = launchIconURLString(from: entry, tvHost: tvHost)
            let brandColorHex = launchBrandColorHex(from: entry)

            apps.append(
                TVAppShortcut(
                    id: loweredID,
                    title: title,
                    iconSystemName: appIconSymbol(title: title, appID: appID),
                    appID: appID,
                    iconURLString: iconURLString,
                    brandColorHex: brandColorHex
                )
            )
        }

        return apps.sorted(by: sortLaunchApps)
    }

    private static func parseAppCatalog(from response: [String: Any]) -> [String: String] {
        let payload = payloadDictionary(from: response)
        let entries = appEntries(from: payload)
        guard !entries.isEmpty else { return [:] }

        var catalog: [String: String] = [:]
        for entry in entries {
            guard
                let rawID = firstString(in: entry, keys: ["id", "appId", "appid", "appID"]),
                !rawID.isEmpty
            else { continue }

            let normalizedID = rawID.lowercased()
            let resolvedTitle =
                firstString(in: entry, keys: ["title", "appName", "visibleName", "name"]) ??
                knownAppAliases[normalizedID] ??
                humanReadableAppName(from: rawID)

            guard !resolvedTitle.isEmpty else { continue }
            catalog[normalizedID] = resolvedTitle
        }
        return catalog
    }

    private static func sortLaunchApps(lhs: TVAppShortcut, rhs: TVAppShortcut) -> Bool {
        let lhsRank = launchRank(for: lhs)
        let rhsRank = launchRank(for: rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func launchRank(for app: TVAppShortcut) -> Int {
        let value = "\(app.title) \(app.appID)".lowercased()
        if value.contains("youtube tv") { return 0 }
        if value.contains("youtube") { return 1 }
        if value.contains("netflix") { return 2 }
        if value.contains("prime") { return 3 }
        if value.contains("disney") { return 4 }
        if value.contains("plex") { return 5 }
        if value.contains("browser") { return 6 }
        return 20
    }

    private static func appIconSymbol(title: String, appID: String) -> String {
        let value = "\(title) \(appID)".lowercased()
        if value.contains("youtube tv") {
            return "tv.badge.wifi"
        }
        if value.contains("youtube") {
            return "play.tv.fill"
        }
        if value.contains("netflix") {
            return "film.stack.fill"
        }
        if value.contains("prime") {
            return "sparkles.tv.fill"
        }
        if value.contains("disney") {
            return "star.circle.fill"
        }
        if value.contains("apple tv") {
            return "appletv.fill"
        }
        if value.contains("browser") {
            return "safari.fill"
        }
        if value.contains("music") {
            return "music.note.tv.fill"
        }
        return "tv.fill"
    }

    private static func launchIconURLString(from entry: [String: Any], tvHost: String?) -> String? {
        guard
            let rawIconValue = firstString(
                in: entry,
                keys: [
                    "largeIcon",
                    "icon",
                    "iconURL",
                    "iconUrl",
                    "iconPath",
                    "image",
                    "thumbnail"
                ]
            )
        else {
            return nil
        }

        let raw = rawIconValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let lowered = raw.lowercased()

        if lowered.hasPrefix("data:image/") {
            return raw
        }

        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return rewriteLocalhostIconURL(raw, tvHost: tvHost) ?? raw
        }

        guard let tvHost, !tvHost.isEmpty else { return nil }

        if raw.hasPrefix("/") {
            return "http://\(tvHost)\(raw)"
        }

        if !raw.contains("://") {
            return "http://\(tvHost)/\(raw)"
        }

        return nil
    }

    private static func rewriteLocalhostIconURL(_ rawURL: String, tvHost: String?) -> String? {
        guard let tvHost, !tvHost.isEmpty else { return nil }
        guard var components = URLComponents(string: rawURL), let host = components.host else { return nil }
        let loweredHost = host.lowercased()
        if loweredHost == "localhost" || loweredHost == "127.0.0.1" {
            components.host = tvHost
            return components.string
        }
        return nil
    }

    private static func launchBrandColorHex(from entry: [String: Any]) -> String? {
        guard
            let rawColor = firstString(
                in: entry,
                keys: [
                    "bgColor",
                    "backgroundColor",
                    "iconColor",
                    "color",
                    "tileColor"
                ]
            )
        else {
            return nil
        }
        return normalizeHexColor(rawColor)
    }

    private static func normalizeHexColor(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            if hex.count == 3 || hex.count == 6 || hex.count == 8 {
                return "#\(hex.uppercased())"
            }
        }

        if trimmed.lowercased().hasPrefix("0x") {
            let hex = String(trimmed.dropFirst(2))
            if hex.count == 6 || hex.count == 8 {
                return "#\(hex.uppercased())"
            }
        }

        return nil
    }

    private static func parseVolumeState(from response: [String: Any]) -> TVVolumeState? {
        let payload = (response["payload"] as? [String: Any]) ?? response
        let status = (payload["volumeStatus"] as? [String: Any]) ?? payload

        let rawVolume =
            (status["volume"] as? Int) ??
            (status["volume"] as? NSNumber)?.intValue

        guard let rawVolume else { return nil }
        let clamped = max(0, min(100, rawVolume))

        let muted =
            (status["mute"] as? Bool) ??
            (status["muted"] as? Bool) ??
            (status["muteStatus"] as? Bool) ??
            false

        return TVVolumeState(level: clamped, isMuted: muted)
    }

    private static func sortInputSources(lhs: TVInputSource, rhs: TVInputSource) -> Bool {
        let lhsRank = inputRank(for: lhs)
        let rhsRank = inputRank(for: rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func inputRank(for source: TVInputSource) -> Int {
        let value = "\(source.title) \(source.inputID)".lowercased()
        if value.contains("hdmi") { return 0 }
        if value.contains("live") || value.contains("dtv") || value == "tv" { return 1 }
        if value.contains("av") { return 2 }
        if value.contains("usb") { return 3 }
        return 4
    }

    private static func iconSystemName(inputID: String, title: String, rawType: String?) -> String {
        let value = "\(inputID) \(title) \(rawType ?? "")".lowercased()
        if value.contains("hdmi") {
            return "cable.connector"
        }
        if value.contains("live") || value.contains("dtv") || value.contains("tv") {
            return "antenna.radiowaves.left.and.right"
        }
        if value.contains("av") {
            return "rectangle.connected.to.line.below"
        }
        if value.contains("usb") {
            return "externaldrive.fill"
        }
        if value.contains("airplay") || value.contains("screen share") {
            return "airplayvideo"
        }
        return "rectangle.connected.to.line.below"
    }

    private static func parseForegroundApp(from response: [String: Any]) -> (appName: String, appID: String?)? {
        let payload = payloadDictionary(from: response)
        let foregroundPayload =
            (payload["foregroundAppInfo"] as? [String: Any]) ??
            ((payload["foregroundAppInfo"] as? [[String: Any]])?.first) ??
            payload

        let appID =
            firstString(in: foregroundPayload, keys: ["appId", "id", "appID", "appid"]) ??
            firstString(in: payload, keys: ["appId", "id", "appID", "appid"])

        let appName =
            firstString(in: foregroundPayload, keys: ["appName", "title", "name", "visibleName"]) ??
            appID ??
            ""

        let normalizedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }
        let normalizedID = appID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        return (normalizedName, normalizedID)
    }

    private static func parseMediaInfo(from response: [String: Any]) -> (title: String?, subtitle: String?) {
        parseMetadataHints(from: response)
    }

    private static func parseAppStatus(from response: [String: Any]) -> (appName: String?, title: String?, subtitle: String?) {
        let payload = payloadDictionary(from: response)
        let appName = firstString(for: appNameKeys, in: payload)
        let appID = firstString(for: appIDKeys, in: payload)
        let metadata = parseMetadataHints(from: payload, appName: appName, appID: appID)
        return (
            appName: appName,
            title: metadata.title,
            subtitle: metadata.subtitle
        )
    }

    private static func parseAppState(from response: [String: Any]) -> (title: String?, subtitle: String?) {
        let payload = payloadDictionary(from: response)
        return parseMetadataHints(from: payload)
    }

    private static func parseRunningAppsMetadata(
        from response: [String: Any],
        preferredAppID: String?
    ) -> (appName: String?, title: String?, subtitle: String?) {
        let payload = payloadDictionary(from: response)
        let entries = appEntries(from: payload)
        guard !entries.isEmpty else {
            return (appName: nil, title: nil, subtitle: nil)
        }

        let preferredID = preferredAppID?.lowercased()
        let candidate = entries.first { entry in
            guard let preferredID else { return false }
            let rawID =
                firstString(in: entry, keys: ["id", "appId", "appid", "appID"]) ??
                ""
            return rawID.lowercased() == preferredID
        } ?? entries.first

        guard let candidate else {
            return (appName: nil, title: nil, subtitle: nil)
        }

        let appName = firstString(for: appNameKeys, in: candidate)
        let appID =
            firstString(in: candidate, keys: ["id", "appId", "appid", "appID"]) ??
            preferredAppID
        let metadata = parseMetadataHints(from: candidate, appName: appName, appID: appID)
        return (
            appName: appName,
            title: metadata.title,
            subtitle: metadata.subtitle
        )
    }

    private static func parseAppInfo(from response: [String: Any]) -> (appName: String?, title: String?, subtitle: String?) {
        let payload = payloadDictionary(from: response)
        let appInfo =
            (payload["appInfo"] as? [String: Any]) ??
            ((payload["appInfo"] as? [[String: Any]])?.first) ??
            payload

        let appName = firstString(for: appNameKeys, in: appInfo)
        let appID =
            firstString(for: appIDKeys, in: appInfo) ??
            firstString(for: appIDKeys, in: payload)
        let metadata = parseMetadataHints(from: appInfo, appName: appName, appID: appID)
        return (
            appName: appName,
            title: metadata.title,
            subtitle: metadata.subtitle
        )
    }

    private static func parseMetadataHints(
        from response: [String: Any],
        appName: String? = nil,
        appID: String? = nil
    ) -> (title: String?, subtitle: String?) {
        let payload = payloadDictionary(from: response)

        let titleCandidates = valuesForKeys(nowPlayingTitleKeys, in: payload)
        let subtitleCandidates = valuesForKeys(nowPlayingSubtitleKeys, in: payload)

        var title = bestMetadataValue(
            from: titleCandidates,
            appName: appName,
            appID: appID,
            preferTitleSignal: true
        )
        var subtitle = bestMetadataValue(
            from: subtitleCandidates,
            appName: appName,
            appID: appID,
            preferTitleSignal: false
        )

        if let currentTitle = title,
           let split = splitCompoundMetadata(currentTitle, appName: appName, appID: appID) {
            if let splitTitle = split.title {
                title = splitTitle
            }
            if subtitle == nil, let splitSubtitle = split.subtitle {
                subtitle = splitSubtitle
            }
        }

        if title == nil {
            let combinedCandidates = titleCandidates + subtitleCandidates
            for candidate in combinedCandidates {
                guard let split = splitCompoundMetadata(candidate, appName: appName, appID: appID) else {
                    continue
                }
                if let splitTitle = split.title, title == nil {
                    title = splitTitle
                }
                if let splitSubtitle = split.subtitle, subtitle == nil {
                    subtitle = splitSubtitle
                }
                if title != nil {
                    break
                }
            }
        }

        subtitle = sanitizedMetadataCandidate(
            subtitle,
            appName: appName,
            appID: appID,
            duplicateOf: title
        )
        title = sanitizedMetadataCandidate(
            title,
            appName: appName,
            appID: appID,
            duplicateOf: subtitle
        )

        return (title: title, subtitle: subtitle)
    }

    private static func parseYouTubeTVMetadata(
        from response: [String: Any],
        appName: String,
        appID: String
    ) -> (title: String?, subtitle: String?) {
        let payload = payloadDictionary(from: response)
        let titleCandidates = valuesForKeys(youtubeTVNowPlayingTitleKeys, in: payload)
        let subtitleCandidates = valuesForKeys(youtubeTVNowPlayingSubtitleKeys, in: payload)

        var title = bestMetadataValue(
            from: titleCandidates,
            appName: appName,
            appID: appID,
            preferTitleSignal: true
        )
        var subtitle = bestMetadataValue(
            from: subtitleCandidates,
            appName: appName,
            appID: appID,
            preferTitleSignal: false
        )

        if title == nil {
            let combinedCandidates = titleCandidates + subtitleCandidates
            for candidate in combinedCandidates {
                guard let split = splitCompoundMetadata(candidate, appName: appName, appID: appID) else {
                    continue
                }
                if let splitTitle = split.title {
                    title = splitTitle
                }
                if let splitSubtitle = split.subtitle, subtitle == nil {
                    subtitle = splitSubtitle
                }
                if title != nil {
                    break
                }
            }
        }

        subtitle = sanitizedMetadataCandidate(
            subtitle,
            appName: appName,
            appID: appID,
            duplicateOf: title
        )
        title = sanitizedMetadataCandidate(
            title,
            appName: appName,
            appID: appID,
            duplicateOf: subtitle
        )
        return (title: title, subtitle: subtitle)
    }

    private static func preferredMetadataValue(
        existing: String?,
        candidate: String?,
        appName: String?,
        appID: String?,
        preferTitleSignal: Bool
    ) -> String? {
        let existingScore = metadataSignalScore(
            existing,
            appName: appName,
            appID: appID,
            preferTitleSignal: preferTitleSignal
        )
        let candidateScore = metadataSignalScore(
            candidate,
            appName: appName,
            appID: appID,
            preferTitleSignal: preferTitleSignal
        )

        if candidateScore > existingScore {
            return sanitizedMetadataCandidate(candidate, appName: appName, appID: appID)
        }
        if candidateScore == existingScore,
           let candidateText = sanitizedMetadataCandidate(candidate, appName: appName, appID: appID),
           let existingText = sanitizedMetadataCandidate(existing, appName: appName, appID: appID),
           candidateText.count > existingText.count {
            return candidateText
        }
        return sanitizedMetadataCandidate(existing, appName: appName, appID: appID)
    }

    private static func metadataPairScore(
        title: String?,
        subtitle: String?,
        appName: String?,
        appID: String?
    ) -> Int {
        let titleScore = metadataSignalScore(
            title,
            appName: appName,
            appID: appID,
            preferTitleSignal: true
        )
        let subtitleScore = metadataSignalScore(
            subtitle,
            appName: appName,
            appID: appID,
            preferTitleSignal: false
        )
        return (titleScore * 3) + subtitleScore
    }

    private static func parseChannelName(from response: [String: Any]) -> String? {
        let payload = payloadDictionary(from: response)
        return firstString(for: channelNameKeys, in: payload)
    }

    private static func parseProgramTitle(from response: [String: Any]) -> String? {
        let payload = payloadDictionary(from: response)
        return firstString(for: programTitleKeys, in: payload)
    }

    private static func sanitizedNowPlayingValue(_ raw: String?, appName: String, title: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            return nil
        }

        let lowered = value.lowercased()
        if lowered == appName.lowercased() {
            return nil
        }
        if let title, lowered == title.lowercased() {
            return nil
        }
        if looksLikeBundleIdentifier(value) {
            return nil
        }
        return value
    }

    private static func compactNowPlayingURI(_ uri: String) -> String {
        uri.replacingOccurrences(of: "ssap://", with: "")
    }

    private static func payloadKeySummary(from response: [String: Any]) -> String {
        let payload = payloadDictionary(from: response)
        let keys = payload.keys.sorted()
        guard !keys.isEmpty else { return "-" }
        return keys.prefix(5).joined(separator: "|")
    }

    private static func nowPlayingErrorLabel(from error: Error) -> String {
        let message = error.userFacingMessage.lowercased()
        if message.contains("timeout") || message.contains("timed out") {
            return "timeout"
        }
        if message.contains("permission") || message.contains("not authorized") || message.contains("401") || message.contains("403") {
            return "unauthorized"
        }
        if message.contains("unsupported") || message.contains("no such") || message.contains("404") {
            return "unsupported"
        }
        if message.contains("not connected") || message.contains("network") {
            return "network"
        }
        return "error"
    }

    private static func buildNowPlayingProbeSummary(
        appID: String?,
        appName: String,
        title: String?,
        subtitle: String?,
        source: TVNowPlayingSource,
        confidence: TVNowPlayingConfidence,
        probes: [String]
    ) -> String {
        let id = appID ?? "none"
        let resolvedTitle = title ?? "nil"
        let resolvedSubtitle = subtitle ?? "nil"
        let endpointSummary = probes.isEmpty ? "none" : probes.joined(separator: "; ")
        return "app=\(appName) (\(id)) source=\(source.rawValue) confidence=\(confidence.rawValue) title=\(resolvedTitle) subtitle=\(resolvedSubtitle) probes=[\(endpointSummary)]"
    }

    private static func payloadDictionary(from response: [String: Any]) -> [String: Any] {
        (response["payload"] as? [String: Any]) ?? response
    }

    private static func appEntries(from payload: [String: Any]) -> [[String: Any]] {
        (payload["launchPoints"] as? [[String: Any]]) ??
            (payload["applications"] as? [[String: Any]]) ??
            (payload["apps"] as? [[String: Any]]) ??
            (payload["runningApps"] as? [[String: Any]]) ??
            (payload["currentRunning"] as? [[String: Any]]) ??
            (payload["appList"] as? [[String: Any]]) ??
            (payload["running"] as? [[String: Any]]) ??
            []
    }

    private static func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = normalizedString(from: dictionary[key]) {
                return value
            }
            let loweredKey = key.lowercased()
            for (candidateKey, candidateValue) in dictionary where candidateKey.lowercased() == loweredKey {
                if let value = normalizedString(from: candidateValue) {
                    return value
                }
            }
        }
        return nil
    }

    private static func firstString(for keys: [String], in value: Any) -> String? {
        for key in keys {
            if let resolved = valueForKey(key, in: value) {
                return resolved
            }
        }
        return nil
    }

    private static func valuesForKeys(_ keys: [String], in value: Any) -> [String] {
        let resolved = keys.flatMap { valuesForKey($0, in: value) }
        return deduplicateStrings(resolved)
    }

    private static func valueForKey(_ key: String, in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let direct = normalizedString(from: dictionary[key]) {
                return direct
            }
            let loweredKey = key.lowercased()
            for (candidateKey, candidateValue) in dictionary where candidateKey.lowercased() == loweredKey {
                if let direct = normalizedString(from: candidateValue) {
                    return direct
                }
            }
            for nestedValue in dictionary.values {
                if let nested = valueForKey(key, in: nestedValue) {
                    return nested
                }
            }
            return nil
        }

        if let array = value as? [Any] {
            for item in array {
                if let nested = valueForKey(key, in: item) {
                    return nested
                }
            }
        }

        return nil
    }

    private static func valuesForKey(_ key: String, in value: Any) -> [String] {
        var results: [String] = []

        if let dictionary = value as? [String: Any] {
            if let direct = normalizedString(from: dictionary[key]) {
                results.append(direct)
            }

            let loweredKey = key.lowercased()
            for (candidateKey, candidateValue) in dictionary where candidateKey.lowercased() == loweredKey {
                if let direct = normalizedString(from: candidateValue) {
                    results.append(direct)
                }
            }

            for nestedValue in dictionary.values {
                results.append(contentsOf: valuesForKey(key, in: nestedValue))
            }
        } else if let array = value as? [Any] {
            for item in array {
                results.append(contentsOf: valuesForKey(key, in: item))
            }
        }

        return results
    }

    private static func normalizedString(from value: Any?) -> String? {
        guard let value else { return nil }

        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }

        if let number = value as? NSNumber {
            return number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }

        return nil
    }

    private static func resolveNowPlayingConfidence(
        appName: String,
        appID: String?,
        title: String?,
        subtitle: String?,
        source: TVNowPlayingSource
    ) -> TVNowPlayingConfidence {
        let titleScore = metadataSignalScore(
            title,
            appName: appName,
            appID: appID,
            preferTitleSignal: true
        )
        let subtitleScore = metadataSignalScore(
            subtitle,
            appName: appName,
            appID: appID,
            preferTitleSignal: false
        )

        if titleScore >= 6 {
            return .high
        }
        if source != .app && titleScore >= 4 {
            return .high
        }
        if titleScore >= 3 || subtitleScore >= 3 {
            return .medium
        }
        if titleScore > 0 || subtitleScore > 0 {
            return .medium
        }
        return .low
    }

    private static func maxNowPlayingConfidence(
        _ lhs: TVNowPlayingConfidence,
        _ rhs: TVNowPlayingConfidence
    ) -> TVNowPlayingConfidence {
        let rank: [TVNowPlayingConfidence: Int] = [
            .low: 0,
            .medium: 1,
            .high: 2
        ]
        return (rank[lhs] ?? 0) >= (rank[rhs] ?? 0) ? lhs : rhs
    }

    private static func looksLikePlexApp(appID: String?, appName: String) -> Bool {
        let token = "\(appID ?? "") \(appName)".lowercased()
        return token.contains("plex")
            || token.contains("tv.plex.app")
            || token.contains("com.plexapp.plex")
    }

    private static func bestMetadataValue(
        from values: [String],
        appName: String?,
        appID: String?,
        preferTitleSignal: Bool
    ) -> String? {
        let unique = deduplicateStrings(values)
        var winner: (value: String, score: Int)?

        for candidate in unique {
            let score = metadataSignalScore(
                candidate,
                appName: appName,
                appID: appID,
                preferTitleSignal: preferTitleSignal
            )
            guard score > 0 else { continue }

            if let currentWinner = winner {
                if score > currentWinner.score || (score == currentWinner.score && candidate.count > currentWinner.value.count) {
                    winner = (candidate, score)
                }
            } else {
                winner = (candidate, score)
            }
        }

        return winner?.value
    }

    private static func splitCompoundMetadata(
        _ value: String,
        appName: String?,
        appID: String?
    ) -> (title: String?, subtitle: String?)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for separator in compoundMetadataSeparators {
            guard trimmed.contains(separator) else { continue }
            let parts = trimmed
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard parts.count >= 2 else { continue }

            let left = parts[0]
            let right = parts[1]
            let leftIsApp = isLikelyAppDescriptor(left, appName: appName, appID: appID)
            let rightIsApp = isLikelyAppDescriptor(right, appName: appName, appID: appID)

            let rawTitle: String?
            let rawSubtitle: String?
            if leftIsApp && !rightIsApp {
                rawTitle = right
                rawSubtitle = left
            } else if rightIsApp && !leftIsApp {
                rawTitle = left
                rawSubtitle = right
            } else {
                rawTitle = left
                rawSubtitle = right
            }

            let title = sanitizedMetadataCandidate(rawTitle, appName: appName, appID: appID)
            let subtitle = sanitizedMetadataCandidate(rawSubtitle, appName: appName, appID: appID, duplicateOf: title)
            if title != nil || subtitle != nil {
                return (title: title, subtitle: subtitle)
            }
        }

        return nil
    }

    private static func sanitizedMetadataCandidate(
        _ value: String?,
        appName: String?,
        appID: String?,
        duplicateOf: String? = nil
    ) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            return nil
        }

        let lowered = normalized.lowercased()
        if placeholderMetadataTokens.contains(lowered) {
            return nil
        }
        if let appName, lowered == appName.lowercased() {
            return nil
        }
        if let appID, lowered == appID.lowercased() {
            return nil
        }
        if let duplicateOf, lowered == duplicateOf.lowercased() {
            return nil
        }
        if looksLikeBundleIdentifier(normalized) {
            return nil
        }
        return normalized
    }

    private static func metadataSignalScore(
        _ value: String?,
        appName: String?,
        appID: String?,
        preferTitleSignal: Bool
    ) -> Int {
        guard let normalized = sanitizedMetadataCandidate(value, appName: appName, appID: appID) else {
            return 0
        }

        let lowered = normalized.lowercased()
        var score = 1

        if normalized.count >= 4 {
            score += 2
        }
        if normalized.count >= 8 {
            score += 1
        }
        if normalized.count > 80 {
            score -= 2
        }
        if normalized.rangeOfCharacter(from: CharacterSet.letters) != nil {
            score += 2
        }
        if normalized.contains(" ") {
            score += 1
        }
        if isDigitsOnly(normalized) {
            score -= 3
        }
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("www.") {
            score -= 4
        }

        if preferTitleSignal {
            if lowered.contains("episode") || lowered.contains("season") || lowered.contains("movie") {
                score += 1
            }
        } else {
            if lowered.contains("channel") || lowered.contains("network") {
                score += 1
            }
        }

        return score
    }

    private static func deduplicateStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var deduplicated: [String] = []

        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            if seen.insert(key).inserted {
                deduplicated.append(normalized)
            }
        }

        return deduplicated
    }

    private static func isDigitsOnly(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.allSatisfy(\.isNumber)
    }

    private static func isLikelyAppDescriptor(
        _ value: String,
        appName: String?,
        appID: String?
    ) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        if let appName, normalized == appName.lowercased() {
            return true
        }
        if let appID {
            if normalized == appID.lowercased() {
                return true
            }
            if normalized == humanReadableAppName(from: appID).lowercased() {
                return true
            }
        }
        if knownAppAliases.values.contains(where: { $0.lowercased() == normalized }) {
            return true
        }
        return looksLikeBundleIdentifier(normalized)
    }

    private static func looksLikeLiveTVApp(appID: String?, appName: String) -> Bool {
        let token = "\(appID ?? "") \(appName)".lowercased()
        return token.contains("livetv")
            || token.contains("live tv")
            || token.contains("broadcast")
            || token.contains("com.webos.app.tv")
            || token.contains("com.webos.app.livetv")
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.contains(".") && !candidate.contains(" ")
    }

    private static func restrictedMetadataReason(appID: String?, appName: String) -> String? {
        let token = "\(appID ?? "") \(appName)".lowercased()
        if token.contains("netflix") {
            return "Netflix hides title metadata on LG webOS."
        }
        if token.contains("prime") || token.contains("amazon") {
            return "Prime Video hides title metadata on LG webOS."
        }
        if token.contains("disney") {
            return "Disney+ hides title metadata on LG webOS."
        }
        if token.contains("hulu") {
            return "Hulu hides title metadata on LG webOS."
        }
        if token.contains("max") || token.contains("hbo") {
            return "Max hides title metadata on LG webOS."
        }
        return nil
    }

    private static func humanReadableAppName(from appID: String) -> String {
        let normalized = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "Unknown App" }

        let lowered = normalized.lowercased()
        if let alias = knownAppAliases[lowered] {
            return alias
        }

        let sanitized = lowered
            .replacingOccurrences(of: "com.webos.app.", with: "")
            .replacingOccurrences(of: "com.webos.", with: "")
            .replacingOccurrences(of: ".v1", with: "")
            .replacingOccurrences(of: ".v2", with: "")
            .replacingOccurrences(of: ".v3", with: "")
            .replacingOccurrences(of: ".v4", with: "")
            .replacingOccurrences(of: "leanback", with: "")
            .replacingOccurrences(of: "ytv", with: "youtube tv")

        let components = sanitized
            .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !components.isEmpty else { return normalized }
        return components
            .joined(separator: " ")
            .capitalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let nowPlayingTitleKeys = [
        "title",
        "mainTitle",
        "displayTitle",
        "windowTitle",
        "window_title",
        "activityName",
        "currentTitle",
        "currentProgram",
        "program",
        "programTitleShort",
        "contentName",
        "contentTitle",
        "content",
        "mediaTitle",
        "mediaName",
        "programName",
        "programTitle",
        "eventName",
        "eventTitle",
        "trackName",
        "songTitle",
        "videoTitle",
        "episodeTitle",
        "episodeName",
        "episode",
        "movieTitle",
        "headline",
        "name",
        "nowPlaying",
        "streamTitle"
    ]

    private static let nowPlayingSubtitleKeys = [
        "description",
        "shortDescription",
        "longDescription",
        "subtitle",
        "subTitle",
        "secondaryTitle",
        "artist",
        "creator",
        "author",
        "seriesName",
        "seriesTitle",
        "showName",
        "showTitle",
        "album",
        "serviceName",
        "service",
        "stationName",
        "channelTitle",
        "channelName",
        "channelNameLong",
        "channelNumber",
        "networkName"
    ]

    private static let appIDKeys = [
        "appId",
        "appID",
        "appid",
        "id",
        "applicationId",
        "appIdentifier"
    ]

    private static let youtubeTVAppID = "youtube.leanback.ytv.v1"

    private static let youtubeTVNowPlayingTitleKeys = [
        "programTitle",
        "program_title",
        "programName",
        "program_name",
        "episodeTitle",
        "episode_title",
        "episodeName",
        "episode_name",
        "videoTitle",
        "video_title",
        "contentTitle",
        "content_title",
        "mediaTitle",
        "media_title",
        "assetTitle",
        "asset_title",
        "titleText",
        "title_text",
        "primaryText",
        "primary_text",
        "nowPlaying",
        "now_playing",
        "headline"
    ]

    private static let youtubeTVNowPlayingSubtitleKeys = [
        "showName",
        "show_name",
        "showTitle",
        "show_title",
        "seriesName",
        "series_name",
        "seriesTitle",
        "series_title",
        "channelName",
        "channel_name",
        "networkName",
        "network_name",
        "stationName",
        "station_name",
        "serviceName",
        "service_name",
        "secondaryTitle",
        "secondary_title",
        "secondaryText",
        "secondary_text",
        "subTitle",
        "sub_title",
        "subtitle"
    ]

    private static let compoundMetadataSeparators = [
        " - ",
        " | ",
        " • ",
        " : "
    ]

    private static let placeholderMetadataTokens: Set<String> = [
        "unknown",
        "unavailable",
        "metadata unavailable",
        "not available",
        "n/a",
        "na",
        "none",
        "null",
        "nil",
        "untitled",
        "loading"
    ]

    private static let channelNameKeys = [
        "channelName",
        "channelNameLong",
        "channelNumber",
        "channelId"
    ]

    private static let programTitleKeys = [
        "programName",
        "programTitle",
        "eventName",
        "title"
    ]

    private static let appNameKeys = [
        "appName",
        "visibleName",
        "title",
        "name"
    ]

    private static let knownAppAliases: [String: String] = [
        "com.webos.app.livetv": "Live TV",
        "com.webos.app.hdmi1": "HDMI 1",
        "com.webos.app.hdmi2": "HDMI 2",
        "com.webos.app.hdmi3": "HDMI 3",
        "com.webos.app.hdmi4": "HDMI 4",
        "youtube.leanback.v4": "YouTube",
        "youtube.leanback.ytv.v1": "YouTube TV",
        "netflix": "Netflix",
        "amazon": "Prime Video",
        "com.disney.disneyplus-prod": "Disney+",
        "tv.plex.app": "Plex",
        "com.plexapp.plex": "Plex",
        "plex": "Plex",
        "com.webos.app.browser": "Browser",
        "com.webos.app.gallery": "Gallery",
        "com.apple.appletv": "Apple TV",
        "com.webos.app.music": "Music"
    ]
}

private struct LGPlexConfiguration {
    let serverURL: URL
    let token: String
}

private struct LGPlexSession {
    var type: String
    var title: String?
    var parentTitle: String?
    var grandparentTitle: String?
    var originalTitle: String?
    var playerAddress: String?
    var playerTitle: String?
    var playerState: String?
}

private struct LGPlexSessionSelection {
    let session: LGPlexSession
    let confidence: TVNowPlayingConfidence
}

private struct LGPlexMetadataSnapshot {
    var title: String?
    var subtitle: String?
    var confidence: TVNowPlayingConfidence
}

private final class LGPlexSessionsParser: NSObject, XMLParserDelegate {
    private var sessions: [LGPlexSession] = []
    private var currentSession: LGPlexSession?

    static func parse(_ data: Data) -> [LGPlexSession] {
        let parserDelegate = LGPlexSessionsParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parserDelegate
        guard xmlParser.parse() else { return [] }
        return parserDelegate.sessions
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "Video", "Track":
            currentSession = LGPlexSession(
                type: attributeDict["type"]?.lowercased() ?? elementName.lowercased(),
                title: attributeDict["title"],
                parentTitle: attributeDict["parentTitle"],
                grandparentTitle: attributeDict["grandparentTitle"],
                originalTitle: attributeDict["originalTitle"],
                playerAddress: nil,
                playerTitle: nil,
                playerState: nil
            )
        case "Player":
            guard currentSession != nil else { return }
            currentSession?.playerAddress = attributeDict["address"] ?? attributeDict["publicAddress"]
            currentSession?.playerTitle = attributeDict["title"]
            currentSession?.playerState = attributeDict["state"]
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "Video" || elementName == "Track" else { return }
        guard let session = currentSession else { return }
        sessions.append(session)
        currentSession = nil
    }
}

private struct LGConnectionEndpoint: Hashable {
    let port: Int
    let secure: Bool
}

private enum LGButtonTransportMode {
    case ssapSendButton
    case pointerSocket

    var label: String {
        switch self {
        case .ssapSendButton:
            return "SSAP sendButton"
        case .pointerSocket:
            return "Pointer socket"
        }
    }
}

private struct CommandLatencyEvent {
    let commandKey: String
    let latencyMs: Int
    let succeeded: Bool
    let timedOut: Bool
    let capturedAt: Date
}

private struct LGCommandErrorSnapshot {
    let code: Int?
    let message: String
    let commandKey: String?
    let timestamp: Date
}

private final class LGProbeCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var completed = false

    nonisolated func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

private enum LGWebOSURI {
    static let getServiceList = "ssap://api/getServiceList"
    static let getForegroundAppInfo = "ssap://com.webos.applicationManager/getForegroundAppInfo"
    static let listLaunchPoints = "ssap://com.webos.applicationManager/listLaunchPoints"
    static let listApps = "ssap://com.webos.applicationManager/listApps"
    static let listRunningApps = "ssap://com.webos.applicationManager/listRunningApps"
    static let getAppInfo = "ssap://com.webos.applicationManager/getAppInfo"
    static let getMediaInfo = "ssap://media.controls/getMediaInfo"
    static let getAppStatus = "ssap://com.webos.service.appstatus/getAppStatus"
    static let getAppState = "ssap://system.launcher/getAppState"
    static let sendButton = "ssap://com.webos.service.networkinput/sendButton"
    static let getVolume = "ssap://audio/getVolume"
    static let setVolume = "ssap://audio/setVolume"
    static let volumeUp = "ssap://audio/volumeUp"
    static let volumeDown = "ssap://audio/volumeDown"
    static let setMute = "ssap://audio/setMute"
    static let turnOff = "ssap://system/turnOff"
    static let launchApp = "ssap://system.launcher/launch"
    static let switchInput = "ssap://tv/switchInput"
    static let getExternalInputList = "ssap://tv/getExternalInputList"
    static let getCurrentChannel = "ssap://tv/getCurrentChannel"
    static let getChannelCurrentProgramInfo = "ssap://tv/getChannelCurrentProgramInfo"
    static let getChannelProgramInfo = "ssap://tv/getChannelProgramInfo"
    static let insertText = "ssap://com.webos.service.ime/insertText"
}

private actor CommandExecutionGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withPermit<T>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
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
