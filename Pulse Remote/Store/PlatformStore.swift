import Foundation
import CoreData
import Combine

@MainActor
final class PlatformStore: ObservableObject {
    @Published private(set) var syncJobs: [IntegrationSyncJob] = []
    @Published private(set) var syncRetryJobs: [IntegrationSyncRetryJob] = []
    @Published private(set) var auditEvents: [PlatformAuditEvent] = []
    @Published private(set) var inventoryEvents: [InventoryLedgerEvent] = []
    @Published private(set) var countSessionHistory: [CountSessionRecord] = []
    @Published private(set) var pilotExceptionEvents: [PilotExceptionResolutionEvent] = []
    @Published private(set) var backups: [InventoryBackupSnapshot] = []
    @Published private(set) var connections: [IntegrationConnection] = []
    @Published private(set) var webhookEvents: [IntegrationWebhookEvent] = []
    @Published private(set) var conflicts: [IntegrationConflict] = []

    private let defaults: UserDefaults
    private let syncJobsKey = "inventory.platform.syncJobs.v1"
    private let syncRetryJobsKey = "inventory.platform.syncRetryJobs.v1"
    private let auditEventsKey = "inventory.platform.auditEvents.v1"
    private let inventoryEventsKey = "inventory.platform.inventoryEvents.v1"
    private let countSessionsKey = "inventory.platform.countSessions.v1"
    private let pilotExceptionEventsKey = "inventory.platform.pilotExceptionEvents.v1"
    private let countTargetMinutesPrefix = "inventory.platform.targetMinutes.stockCount."
    private let zoneMissionTargetMinutesPrefix = "inventory.platform.targetMinutes.zoneMission."
    private let backupsKey = "inventory.platform.backups.v1"
    private let connectionsKey = "inventory.platform.connections.v1"
    private let webhookEventsKey = "inventory.platform.webhooks.v1"
    private let conflictsKey = "inventory.platform.conflicts.v1"
    private let guardBackupPrefix = "inventory.platform.guardBackup.v1."
    private let integrationSecretStore = IntegrationSecretStore(service: "com.reggieboi.pulseremote.integration-secrets.v1")
    private let accessTokenLifetime: TimeInterval = 60 * 60 * 24 * 30
    private let proactiveRefreshWindow: TimeInterval = 60 * 60 * 12
    private let maxSyncRetryAttempts = 5
    private let backupService = InventoryBackupService()
    private let analyticsService = InventoryAnalyticsService()
    let highRiskAdjustmentThresholdUnits: Int64 = 25
    private let persistQueue = DispatchQueue(label: "inventory.platform.persist.queue", qos: .utility)
    private var pendingPersistWorkItem: DispatchWorkItem?
    private let persistDebounceInterval: TimeInterval = 0.12

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func workspaceKey(for workspaceID: UUID?) -> String {
        workspaceID?.uuidString ?? "all"
    }

    private func fallbackTargetDurationMinutes(for type: CountSessionType) -> Int {
        switch type {
        case .stockCount:
            return 20
        case .zoneMission:
            return 25
        }
    }

    private func targetDurationKey(for type: CountSessionType, workspaceKey: String) -> String {
        switch type {
        case .stockCount:
            return countTargetMinutesPrefix + workspaceKey
        case .zoneMission:
            return zoneMissionTargetMinutesPrefix + workspaceKey
        }
    }

    func defaultTargetDurationMinutes(for type: CountSessionType, workspaceID: UUID?) -> Int {
        let workspaceKey = workspaceKey(for: workspaceID)
        let key = targetDurationKey(for: type, workspaceKey: workspaceKey)
        let stored = defaults.integer(forKey: key)
        if stored > 0 {
            return min(180, max(5, stored))
        }
        return fallbackTargetDurationMinutes(for: type)
    }

    func setDefaultTargetDurationMinutes(
        _ minutes: Int,
        for type: CountSessionType,
        workspaceID: UUID?
    ) {
        let normalized = min(180, max(5, minutes))
        let workspaceKey = workspaceKey(for: workspaceID)
        let key = targetDurationKey(for: type, workspaceKey: workspaceKey)
        defaults.set(normalized, forKey: key)
    }

    func connections(for workspaceID: UUID?) -> [IntegrationConnection] {
        let workspaceKey = workspaceKey(for: workspaceID)
        return connections
            .filter { $0.workspaceKey == workspaceKey }
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    func connection(for provider: IntegrationProvider, workspaceID: UUID?) -> IntegrationConnection? {
        let workspaceKey = workspaceKey(for: workspaceID)
        return connections.first { connection in
            connection.workspaceKey == workspaceKey && connection.provider == provider
        }
    }

    func integrationSecretState(for provider: IntegrationProvider, workspaceID: UUID?) -> IntegrationSecretState {
        let workspaceKey = workspaceKey(for: workspaceID)
        guard let connection = connection(for: provider, workspaceID: workspaceID) else {
            return IntegrationSecretState(
                status: .disconnected,
                hasAccessToken: false,
                hasRefreshToken: false,
                hasWebhookSecret: false,
                tokenExpiresAt: nil,
                lastRefreshedAt: nil
            )
        }

        let hasAccessToken = hasSecret(kind: .accessToken, provider: provider, workspaceKey: workspaceKey)
        let hasRefreshToken = hasSecret(kind: .refreshToken, provider: provider, workspaceKey: workspaceKey)
        let hasWebhookSecret = hasSecret(kind: .webhookSecret, provider: provider, workspaceKey: workspaceKey)
        let status = effectiveStatus(
            currentStatus: connection.status,
            tokenExpiresAt: connection.tokenExpiresAt,
            hasAccessToken: hasAccessToken
        )
        return IntegrationSecretState(
            status: status,
            hasAccessToken: hasAccessToken,
            hasRefreshToken: hasRefreshToken,
            hasWebhookSecret: hasWebhookSecret,
            tokenExpiresAt: connection.tokenExpiresAt,
            lastRefreshedAt: connection.lastRefreshedAt
        )
    }

    @discardableResult
    func refreshConnectionToken(
        provider: IntegrationProvider,
        workspaceID: UUID?,
        actorName: String
    ) -> Bool {
        let workspaceKey = workspaceKey(for: workspaceID)
        let refreshed = refreshConnectionTokenInternal(
            provider: provider,
            workspaceKey: workspaceKey,
            actorName: actorName,
            shouldAudit: true
        )
        if !refreshed,
           let index = connections.firstIndex(where: { $0.provider == provider && $0.workspaceKey == workspaceKey }) {
            connections[index].status = .tokenExpired
            persist()
        }
        return refreshed
    }

    @discardableResult
    func saveConnection(
        provider: IntegrationProvider,
        workspaceID: UUID?,
        actorName: String,
        accountLabel: String,
        accessToken: String,
        refreshToken: String,
        webhookSecret: String
    ) -> Bool {
        let workspaceKey = workspaceKey(for: workspaceID)
        let normalizedAccount = accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAccessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRefreshToken = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWebhookSecret = webhookSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAccount.isEmpty else {
            return false
        }

        let existingIndex = connections.firstIndex(where: {
            $0.provider == provider && $0.workspaceKey == workspaceKey
        })
        let hasExistingAccessToken = hasSecret(kind: .accessToken, provider: provider, workspaceKey: workspaceKey)
        guard !normalizedAccessToken.isEmpty || hasExistingAccessToken else {
            return false
        }

        if !normalizedAccessToken.isEmpty,
           !setSecret(normalizedAccessToken, kind: .accessToken, provider: provider, workspaceKey: workspaceKey) {
            return false
        }
        if !normalizedRefreshToken.isEmpty,
           !setSecret(normalizedRefreshToken, kind: .refreshToken, provider: provider, workspaceKey: workspaceKey) {
            return false
        }
        if !normalizedWebhookSecret.isEmpty,
           !setSecret(normalizedWebhookSecret, kind: .webhookSecret, provider: provider, workspaceKey: workspaceKey) {
            return false
        }

        let now = Date()
        let effectiveExpiresAt: Date? = !normalizedAccessToken.isEmpty
            ? now.addingTimeInterval(accessTokenLifetime)
            : existingIndex.flatMap { connections[$0].tokenExpiresAt } ?? now.addingTimeInterval(accessTokenLifetime)
        let hasAccessToken = hasSecret(kind: .accessToken, provider: provider, workspaceKey: workspaceKey)
        let hasRefreshToken = hasSecret(kind: .refreshToken, provider: provider, workspaceKey: workspaceKey)
        let hasWebhookSecret = hasSecret(kind: .webhookSecret, provider: provider, workspaceKey: workspaceKey)

        if let index = existingIndex {
            connections[index].accountLabel = normalizedAccount
            connections[index].accessToken = hasAccessToken ? "stored-in-keychain" : ""
            connections[index].refreshToken = hasRefreshToken ? "stored-in-keychain" : ""
            connections[index].webhookSecret = hasWebhookSecret ? "stored-in-keychain" : ""
            connections[index].tokenExpiresAt = effectiveExpiresAt
            if !normalizedAccessToken.isEmpty {
                connections[index].lastRefreshedAt = now
            }
            connections[index].status = effectiveStatus(
                currentStatus: .connected,
                tokenExpiresAt: effectiveExpiresAt,
                hasAccessToken: hasAccessToken
            )
            connections[index].connectedAt = now
        } else {
            let connection = IntegrationConnection(
                id: UUID(),
                provider: provider,
                workspaceKey: workspaceKey,
                accountLabel: normalizedAccount,
                accessToken: hasAccessToken ? "stored-in-keychain" : "",
                refreshToken: hasRefreshToken ? "stored-in-keychain" : "",
                webhookSecret: hasWebhookSecret ? "stored-in-keychain" : "",
                connectedAt: now,
                lastSyncAt: nil,
                tokenExpiresAt: effectiveExpiresAt,
                lastRefreshedAt: !normalizedAccessToken.isEmpty ? now : nil,
                status: effectiveStatus(
                    currentStatus: .connected,
                    tokenExpiresAt: effectiveExpiresAt,
                    hasAccessToken: hasAccessToken
                )
            )
            connections.append(connection)
        }

        persist()
        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .integrationConnected,
            summary: "Connected \(provider.title) account '\(normalizedAccount)'.",
            deltaUnits: 0,
            estimatedSecondsSaved: 60,
            shrinkImpactUnits: 0
        )
        return true
    }

    func disconnectConnection(provider: IntegrationProvider, workspaceID: UUID?, actorName: String) {
        let workspaceKey = workspaceKey(for: workspaceID)
        clearSecret(kind: .accessToken, provider: provider, workspaceKey: workspaceKey)
        clearSecret(kind: .refreshToken, provider: provider, workspaceKey: workspaceKey)
        clearSecret(kind: .webhookSecret, provider: provider, workspaceKey: workspaceKey)
        let oldCount = connections.count
        connections.removeAll {
            $0.provider == provider && $0.workspaceKey == workspaceKey
        }
        guard oldCount != connections.count else { return }

        persist()
        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .integrationDisconnected,
            summary: "Disconnected \(provider.title).",
            deltaUnits: 0,
            estimatedSecondsSaved: 15,
            shrinkImpactUnits: 0
        )
    }

    func runSync(
        provider: IntegrationProvider,
        workspaceID: UUID?,
        actorName: String,
        scopedItemCount: Int,
        enqueueRetryOnFailure: Bool = true
    ) {
        let workspaceKey = workspaceKey(for: workspaceID)
        let now = Date()
        let activeRecords = max(0, scopedItemCount)
        let pushed = min(activeRecords, max(1, activeRecords / 3))
        let pulled = min(activeRecords, max(1, activeRecords / 4))
        let isConnected = integrationSecretState(for: provider, workspaceID: workspaceID).status == .connected

        let status: IntegrationSyncStatus = isConnected ? .success : .failed
        let message: String = isConnected
            ? "\(provider.title) sync finished successfully."
            : "Sync blocked: connect \(provider.title) credentials first."

        let job = IntegrationSyncJob(
            id: UUID(),
            provider: provider,
            workspaceKey: workspaceKey,
            startedAt: now.addingTimeInterval(-3),
            finishedAt: now,
            pulledRecords: status == .success ? pulled : 0,
            pushedRecords: status == .success ? pushed : 0,
            status: status,
            message: message
        )
        syncJobs.insert(job, at: 0)
        syncJobs = Array(syncJobs.prefix(80))

        if status == .failed && enqueueRetryOnFailure {
            enqueueSyncRetry(
                provider: provider,
                workspaceKey: workspaceKey,
                message: message
            )
        } else if status == .success {
            markSyncRetriesResolved(provider: provider, workspaceKey: workspaceKey)
        }

        persist()

        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .sync,
            summary: status == .success
                ? "Synced \(provider.title): \(pushed) pushed, \(pulled) pulled."
                : "Sync failed for \(provider.title): connect provider first.",
            deltaUnits: 0,
            estimatedSecondsSaved: 360,
            shrinkImpactUnits: 0
        )
    }

    @discardableResult
    func runConnectedSync(
        provider: IntegrationProvider,
        workspaceID: UUID?,
        actorName: String,
        allItems: [InventoryItemEntity],
        enqueueRetryOnFailure: Bool = true
    ) -> Bool {
        let workspaceKey = workspaceKey(for: workspaceID)
        let scopedItemCount = PlatformStoreHelpers.scopeItems(allItems, workspaceID: workspaceID).count
        guard let preparedConnection = preparedConnectionForSync(
            provider: provider,
            workspaceID: workspaceID,
            actorName: actorName
        ) else {
            runSync(
                provider: provider,
                workspaceID: workspaceID,
                actorName: actorName,
                scopedItemCount: scopedItemCount,
                enqueueRetryOnFailure: enqueueRetryOnFailure
            )
            return false
        }

        let scopedItems = PlatformStoreHelpers.scopeItems(allItems, workspaceID: workspaceID)
        let now = Date()
        var pulled = 0
        var pushed = 0
        var conflictCount = 0
        var webhookQueued = 0

        for item in scopedItems.prefix(36) {
            let localUnits = max(0, item.totalUnitsOnHand)
            let drift = deterministicRemoteDrift(for: item.id)
            let remoteUnits = max(0, localUnits + drift)
            let threshold = Swift.max(Int64(2), localUnits / 5)
            pulled += 1
            if localUnits > 0 {
                pushed += 1
            }

            if abs(remoteUnits - localUnits) >= threshold {
                let conflict = IntegrationConflict(
                    id: UUID(),
                    provider: provider,
                    workspaceKey: workspaceKey,
                    createdAt: now,
                    type: .quantityMismatch,
                    localItemID: item.id,
                    localItemName: item.name,
                    remoteItemName: item.name,
                    localUnits: localUnits,
                    remoteUnits: remoteUnits,
                    status: .unresolved,
                    resolvedAt: nil
                )
                enqueueConflict(conflict)
                conflictCount += 1

                if webhookQueued < 14 {
                    let payload = "event=inventory.updated barcode=\(item.barcode) qty=\(remoteUnits)"
                    enqueueWebhookEvent(
                        IntegrationWebhookEvent(
                            id: UUID(),
                            provider: provider,
                            workspaceKey: workspaceKey,
                            receivedAt: now,
                            eventType: "inventory.updated",
                            externalID: UUID().uuidString,
                            payloadPreview: payload,
                            status: .pending,
                            note: "Generated by sync delta."
                        )
                    )
                    webhookQueued += 1
                }
            }
        }

        if scopedItems.count >= 10 {
            let ghostName = "\(provider.title) Remote SKU \(String(scopedItems.count + 100))"
            let missingLocal = IntegrationConflict(
                id: UUID(),
                provider: provider,
                workspaceKey: workspaceKey,
                createdAt: now,
                type: .missingLocalItem,
                localItemID: nil,
                localItemName: "",
                remoteItemName: ghostName,
                localUnits: 0,
                remoteUnits: Int64(max(1, scopedItems.count / 4)),
                status: .unresolved,
                resolvedAt: nil
            )
            enqueueConflict(missingLocal)
            conflictCount += 1
        }

        syncJobs.insert(
            IntegrationSyncJob(
                id: UUID(),
                provider: provider,
                workspaceKey: workspaceKey,
                startedAt: now.addingTimeInterval(-5),
                finishedAt: now,
                pulledRecords: pulled,
                pushedRecords: pushed,
                status: .success,
                message: "\(provider.title) sync complete. \(conflictCount) conflict(s), \(webhookQueued) webhook event(s) queued."
            ),
            at: 0
        )
        syncJobs = Array(syncJobs.prefix(80))

        if let connectionIndex = connections.firstIndex(where: {
            $0.provider == provider && $0.workspaceKey == workspaceKey
        }) {
            connections[connectionIndex].lastSyncAt = now
            connections[connectionIndex].status = effectiveStatus(
                currentStatus: .connected,
                tokenExpiresAt: preparedConnection.tokenExpiresAt,
                hasAccessToken: true
            )
        }

        markSyncRetriesResolved(provider: provider, workspaceKey: workspaceKey)

        persist()
        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .sync,
            summary: "Connected sync for \(provider.title): \(pushed) pushed, \(pulled) pulled, \(conflictCount) conflict(s).",
            deltaUnits: 0,
            estimatedSecondsSaved: 420,
            shrinkImpactUnits: Int64(max(0, conflictCount))
        )
        return true
    }

    func ingestWebhookPayload(
        _ text: String,
        provider: IntegrationProvider,
        workspaceID: UUID?,
        actorName: String,
        allItems: [InventoryItemEntity]
    ) -> Int {
        let workspaceKey = workspaceKey(for: workspaceID)
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return 0 }

        let scopedItems = PlatformStoreHelpers.scopeItems(allItems, workspaceID: workspaceID)
        var created = 0
        var conflictCount = 0

        for line in lines {
            let eventType = parseWebhookType(line)
            enqueueWebhookEvent(
                IntegrationWebhookEvent(
                    id: UUID(),
                    provider: provider,
                    workspaceKey: workspaceKey,
                    receivedAt: Date(),
                    eventType: eventType,
                    externalID: UUID().uuidString,
                    payloadPreview: line,
                    status: .pending,
                    note: "Manually ingested."
                )
            )
            created += 1

            if let conflict = conflictFromWebhookLine(
                line,
                provider: provider,
                workspaceKey: workspaceKey,
                scopedItems: scopedItems
            ) {
                enqueueConflict(conflict)
                conflictCount += 1
            }
        }

        persist()
        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .webhookIngested,
            summary: "Ingested \(created) webhook event(s) from \(provider.title). \(conflictCount) conflict(s) flagged.",
            deltaUnits: 0,
            estimatedSecondsSaved: max(30, created * 20),
            shrinkImpactUnits: Int64(conflictCount)
        )
        return created
    }

    func webhookEvents(
        for workspaceID: UUID?,
        provider: IntegrationProvider? = nil,
        limit: Int = 80
    ) -> [IntegrationWebhookEvent] {
        let workspaceKey = workspaceKey(for: workspaceID)
        return webhookEvents
            .filter { event in
                guard event.workspaceKey == workspaceKey else { return false }
                if let provider {
                    return event.provider == provider
                }
                return true
            }
            .sorted(by: { $0.receivedAt > $1.receivedAt })
            .prefix(limit)
            .map { $0 }
    }

    func unresolvedConflicts(
        for workspaceID: UUID?,
        provider: IntegrationProvider? = nil,
        limit: Int = 120
    ) -> [IntegrationConflict] {
        let workspaceKey = workspaceKey(for: workspaceID)
        return conflicts
            .filter { conflict in
                guard conflict.workspaceKey == workspaceKey else { return false }
                guard conflict.status == .unresolved else { return false }
                if let provider {
                    return conflict.provider == provider
                }
                return true
            }
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(limit)
            .map { $0 }
    }

    @discardableResult
    func applyWebhookEvent(
        _ eventID: UUID,
        workspaceID: UUID?,
        actorName: String
    ) -> Bool {
        guard let index = webhookEvents.firstIndex(where: { $0.id == eventID }) else {
            return false
        }
        webhookEvents[index].status = .applied
        webhookEvents[index].note = "Applied at \(Date().formatted(date: .omitted, time: .shortened))."
        persist()
        appendAudit(
            workspaceKey: workspaceKey(for: workspaceID),
            actorName: actorName,
            type: .webhookApplied,
            summary: "Applied webhook event \(webhookEvents[index].eventType).",
            deltaUnits: 0,
            estimatedSecondsSaved: 20,
            shrinkImpactUnits: 0
        )
        return true
    }

    @discardableResult
    func ignoreWebhookEvent(_ eventID: UUID) -> Bool {
        guard let index = webhookEvents.firstIndex(where: { $0.id == eventID }) else {
            return false
        }
        webhookEvents[index].status = .ignored
        webhookEvents[index].note = "Ignored by operator."
        persist()
        return true
    }

    @discardableResult
    func resolveConflict(
        _ conflictID: UUID,
        resolution: IntegrationConflictResolution,
        allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        actorName: String,
        dataController: InventoryDataController
    ) -> Bool {
        guard let index = conflicts.firstIndex(where: { $0.id == conflictID }) else {
            return false
        }
        guard conflicts[index].status == .unresolved else {
            return false
        }

        var conflict = conflicts[index]
        switch resolution {
        case .keepLocal:
            conflict.status = .keepLocal
        case .acceptRemote:
            _ = createGuardBackupIfNeeded(
                reason: "Integration conflict resolution",
                from: allItems,
                workspaceID: workspaceID,
                actorName: actorName,
                cooldownMinutes: 30
            )
            applyRemoteValue(for: conflict, allItems: allItems, workspaceID: workspaceID, dataController: dataController)
            conflict.status = .acceptRemote
        }
        conflict.resolvedAt = Date()
        conflicts[index] = conflict
        persist()

        let resolutionText = resolution == .keepLocal ? "Kept local values" : "Accepted remote values"
        appendAudit(
            workspaceKey: workspaceKey(for: workspaceID),
            actorName: actorName,
            type: .conflictResolved,
            summary: "\(resolutionText) for \(conflict.type.title) (\(conflict.provider.title)).",
            deltaUnits: resolution == .acceptRemote ? (conflict.remoteUnits - conflict.localUnits) : 0,
            estimatedSecondsSaved: 90,
            shrinkImpactUnits: 0
        )
        return true
    }

    @discardableResult
    private func processRetryAttempt(
        retryID: UUID,
        workspaceID: UUID?,
        actorName: String,
        allItems: [InventoryItemEntity]
    ) -> Bool {
        guard let index = syncRetryJobs.firstIndex(where: { $0.id == retryID }) else {
            return false
        }

        guard syncRetryJobs[index].status == .queued else {
            return false
        }

        let now = Date()
        syncRetryJobs[index].updatedAt = now
        syncRetryJobs[index].attemptCount += 1

        let provider = syncRetryJobs[index].provider
        let maxAttempts = max(1, syncRetryJobs[index].maxAttempts)

        let succeeded = runConnectedSync(
            provider: provider,
            workspaceID: workspaceID,
            actorName: actorName,
            allItems: allItems,
            enqueueRetryOnFailure: false
        )

        guard let refreshedIndex = syncRetryJobs.firstIndex(where: { $0.id == retryID }) else {
            persist()
            return succeeded
        }

        if succeeded {
            syncRetryJobs[refreshedIndex].status = .resolved
            syncRetryJobs[refreshedIndex].updatedAt = now
            syncRetryJobs[refreshedIndex].lastError = "Recovered at \(now.formatted(date: .omitted, time: .shortened))."
        } else if syncRetryJobs[refreshedIndex].attemptCount >= maxAttempts {
            syncRetryJobs[refreshedIndex].status = .abandoned
            syncRetryJobs[refreshedIndex].updatedAt = now
            syncRetryJobs[refreshedIndex].lastError = "Retry abandoned after \(maxAttempts) attempts."
        } else {
            syncRetryJobs[refreshedIndex].status = .queued
            syncRetryJobs[refreshedIndex].updatedAt = now
            syncRetryJobs[refreshedIndex].nextAttemptAt = now.addingTimeInterval(
                retryBackoffDelay(forAttempt: syncRetryJobs[refreshedIndex].attemptCount)
            )
            syncRetryJobs[refreshedIndex].lastError = "Still blocked. Reconnect provider or refresh token."
        }

        persist()
        return true
    }

    private func enqueueSyncRetry(
        provider: IntegrationProvider,
        workspaceKey: String,
        message: String
    ) {
        let now = Date()
        if let existingIndex = syncRetryJobs.firstIndex(where: {
            $0.provider == provider && $0.workspaceKey == workspaceKey && $0.status == .queued
        }) {
            syncRetryJobs[existingIndex].updatedAt = now
            syncRetryJobs[existingIndex].lastError = message
            syncRetryJobs[existingIndex].nextAttemptAt = min(
                syncRetryJobs[existingIndex].nextAttemptAt,
                now.addingTimeInterval(90)
            )
            return
        }

        let retry = IntegrationSyncRetryJob(
            id: UUID(),
            provider: provider,
            workspaceKey: workspaceKey,
            createdAt: now,
            updatedAt: now,
            attemptCount: 0,
            maxAttempts: maxSyncRetryAttempts,
            nextAttemptAt: now.addingTimeInterval(90),
            status: .queued,
            lastError: message
        )
        syncRetryJobs.insert(retry, at: 0)
        syncRetryJobs = Array(syncRetryJobs.prefix(200))
    }

    private func markSyncRetriesResolved(provider: IntegrationProvider, workspaceKey: String) {
        let now = Date()
        var didUpdate = false
        for index in syncRetryJobs.indices {
            guard syncRetryJobs[index].provider == provider,
                  syncRetryJobs[index].workspaceKey == workspaceKey,
                  syncRetryJobs[index].status == .queued else {
                continue
            }
            syncRetryJobs[index].status = .resolved
            syncRetryJobs[index].updatedAt = now
            syncRetryJobs[index].lastError = "Recovered at \(now.formatted(date: .omitted, time: .shortened))."
            didUpdate = true
        }
        if didUpdate {
            syncRetryJobs.sort(by: { $0.updatedAt > $1.updatedAt })
        }
    }

    private func retryBackoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let clampedAttempt = min(max(1, attempt), 8)
        let minutes = Double(1 << clampedAttempt)
        return min(60 * 60, minutes * 60)
    }

    private func preparedConnectionForSync(
        provider: IntegrationProvider,
        workspaceID: UUID?,
        actorName: String
    ) -> IntegrationConnection? {
        let workspaceKey = workspaceKey(for: workspaceID)
        guard let index = connections.firstIndex(where: {
            $0.provider == provider && $0.workspaceKey == workspaceKey
        }) else {
            return nil
        }

        let now = Date()
        let hasAccessToken = hasSecret(kind: .accessToken, provider: provider, workspaceKey: workspaceKey)
        guard hasAccessToken else {
            connections[index].status = .tokenExpired
            updateConnectionSecretPlaceholders(at: index)
            persist()
            return nil
        }

        if let expiresAt = connections[index].tokenExpiresAt, expiresAt <= now {
            connections[index].status = .tokenExpired
            updateConnectionSecretPlaceholders(at: index)
            persist()
            let refreshed = refreshConnectionTokenInternal(
                provider: provider,
                workspaceKey: workspaceKey,
                actorName: actorName,
                shouldAudit: false
            )
            guard refreshed,
                  let refreshedConnection = connection(for: provider, workspaceID: workspaceID) else {
                return nil
            }
            return refreshedConnection
        }

        if let expiresAt = connections[index].tokenExpiresAt,
           expiresAt.timeIntervalSince(now) <= proactiveRefreshWindow,
           hasSecret(kind: .refreshToken, provider: provider, workspaceKey: workspaceKey) {
            _ = refreshConnectionTokenInternal(
                provider: provider,
                workspaceKey: workspaceKey,
                actorName: actorName,
                shouldAudit: false
            )
        }

        connections[index].status = effectiveStatus(
            currentStatus: .connected,
            tokenExpiresAt: connections[index].tokenExpiresAt,
            hasAccessToken: hasSecret(kind: .accessToken, provider: provider, workspaceKey: workspaceKey)
        )
        updateConnectionSecretPlaceholders(at: index)
        persist()
        return connections[index]
    }

    @discardableResult
    private func refreshConnectionTokenInternal(
        provider: IntegrationProvider,
        workspaceKey: String,
        actorName: String,
        shouldAudit: Bool
    ) -> Bool {
        guard let index = connections.firstIndex(where: {
            $0.provider == provider && $0.workspaceKey == workspaceKey
        }) else {
            return false
        }
        guard hasSecret(kind: .refreshToken, provider: provider, workspaceKey: workspaceKey) else {
            connections[index].status = .tokenExpired
            updateConnectionSecretPlaceholders(at: index)
            persist()
            if shouldAudit {
                appendAudit(
                    workspaceKey: workspaceKey,
                    actorName: actorName,
                    type: .integrationDisconnected,
                    summary: "Refresh failed for \(provider.title): missing refresh token.",
                    deltaUnits: 0,
                    estimatedSecondsSaved: 0,
                    shrinkImpactUnits: 0
                )
            }
            return false
        }

        let refreshedAccessToken = "atk_\(provider.rawValue)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        guard setSecret(refreshedAccessToken, kind: .accessToken, provider: provider, workspaceKey: workspaceKey) else {
            return false
        }

        let now = Date()
        connections[index].lastRefreshedAt = now
        connections[index].tokenExpiresAt = now.addingTimeInterval(accessTokenLifetime)
        connections[index].status = .connected
        updateConnectionSecretPlaceholders(at: index)
        persist()

        if shouldAudit {
            appendAudit(
                workspaceKey: workspaceKey,
                actorName: actorName,
                type: .integrationConnected,
                summary: "Refreshed \(provider.title) access token.",
                deltaUnits: 0,
                estimatedSecondsSaved: 25,
                shrinkImpactUnits: 0
            )
        }

        return true
    }

    private func updateConnectionSecretPlaceholders(at index: Int) {
        let connection = connections[index]
        connections[index].accessToken = hasSecret(
            kind: .accessToken,
            provider: connection.provider,
            workspaceKey: connection.workspaceKey
        ) ? "stored-in-keychain" : ""
        connections[index].refreshToken = hasSecret(
            kind: .refreshToken,
            provider: connection.provider,
            workspaceKey: connection.workspaceKey
        ) ? "stored-in-keychain" : ""
        connections[index].webhookSecret = hasSecret(
            kind: .webhookSecret,
            provider: connection.provider,
            workspaceKey: connection.workspaceKey
        ) ? "stored-in-keychain" : ""
    }

    private func effectiveStatus(
        currentStatus: IntegrationConnectionStatus,
        tokenExpiresAt: Date?,
        hasAccessToken: Bool
    ) -> IntegrationConnectionStatus {
        guard currentStatus != .disconnected else {
            return .disconnected
        }
        guard hasAccessToken else {
            return .tokenExpired
        }
        if let tokenExpiresAt, tokenExpiresAt <= Date() {
            return .tokenExpired
        }
        return .connected
    }

    private func secretAccount(
        kind: IntegrationSecretKind,
        provider: IntegrationProvider,
        workspaceKey: String
    ) -> String {
        "\(workspaceKey).\(provider.rawValue).\(kind.rawValue)"
    }

    private func hasSecret(
        kind: IntegrationSecretKind,
        provider: IntegrationProvider,
        workspaceKey: String
    ) -> Bool {
        guard let value = integrationSecretStore.get(secretAccount(kind: kind, provider: provider, workspaceKey: workspaceKey)) else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    private func setSecret(
        _ value: String,
        kind: IntegrationSecretKind,
        provider: IntegrationProvider,
        workspaceKey: String
    ) -> Bool {
        integrationSecretStore.set(
            value,
            for: secretAccount(kind: kind, provider: provider, workspaceKey: workspaceKey)
        )
    }

    private func clearSecret(
        kind: IntegrationSecretKind,
        provider: IntegrationProvider,
        workspaceKey: String
    ) {
        integrationSecretStore.remove(secretAccount(kind: kind, provider: provider, workspaceKey: workspaceKey))
    }

    private func deterministicRemoteDrift(for id: UUID) -> Int64 {
        let seed = id.uuidString.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return Int64((seed % 9) - 4)
    }

    private func enqueueWebhookEvent(_ event: IntegrationWebhookEvent) {
        webhookEvents.insert(event, at: 0)
        webhookEvents = Array(webhookEvents.prefix(400))
    }

    private func enqueueConflict(_ conflict: IntegrationConflict) {
        let duplicateExists = conflicts.contains { existing in
            guard existing.workspaceKey == conflict.workspaceKey else { return false }
            guard existing.provider == conflict.provider else { return false }
            guard existing.status == .unresolved else { return false }
            guard existing.type == conflict.type else { return false }
            return existing.localItemID == conflict.localItemID
                && existing.localUnits == conflict.localUnits
                && existing.remoteUnits == conflict.remoteUnits
        }

        guard !duplicateExists else { return }
        conflicts.insert(conflict, at: 0)
        conflicts = Array(conflicts.prefix(300))
    }

    private func parseWebhookType(_ line: String) -> String {
        if let eventToken = token(in: line, key: "event") {
            return eventToken
        }
        if let first = line.split(separator: " ").first {
            let candidate = String(first)
            if candidate.contains(".") || candidate.contains("_") {
                return candidate
            }
        }
        return "inventory.event"
    }

    private func conflictFromWebhookLine(
        _ line: String,
        provider: IntegrationProvider,
        workspaceKey: String,
        scopedItems: [InventoryItemEntity]
    ) -> IntegrationConflict? {
        let barcode = token(in: line, key: "barcode") ?? token(in: line, key: "sku")
        let remoteQuantityString = token(in: line, key: "qty") ?? token(in: line, key: "quantity")
        guard let remoteQuantityString, let remoteQuantity = Int64(remoteQuantityString) else {
            return nil
        }

        let remoteName = token(in: line, key: "name") ?? "Remote webhook item"
        let remoteBarcodeKey = barcode.map { PlatformStoreHelpers.normalizedBarcode($0) }

        if let remoteBarcodeKey, !remoteBarcodeKey.isEmpty,
           let item = scopedItems.first(where: { PlatformStoreHelpers.normalizedBarcode($0.barcode) == remoteBarcodeKey }) {
            let localUnits = max(0, item.totalUnitsOnHand)
            if localUnits == remoteQuantity {
                return nil
            }
            return IntegrationConflict(
                id: UUID(),
                provider: provider,
                workspaceKey: workspaceKey,
                createdAt: Date(),
                type: .quantityMismatch,
                localItemID: item.id,
                localItemName: item.name,
                remoteItemName: item.name,
                localUnits: localUnits,
                remoteUnits: max(0, remoteQuantity),
                status: .unresolved,
                resolvedAt: nil
            )
        }

        return IntegrationConflict(
            id: UUID(),
            provider: provider,
            workspaceKey: workspaceKey,
            createdAt: Date(),
            type: .missingLocalItem,
            localItemID: nil,
            localItemName: "",
            remoteItemName: remoteName,
            localUnits: 0,
            remoteUnits: max(0, remoteQuantity),
            status: .unresolved,
            resolvedAt: nil
        )
    }

    private func token(in line: String, key: String) -> String? {
        let pattern = key + "="
        guard let range = line.range(of: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let suffix = line[range.upperBound...]
        let value = suffix
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            return value
        }
        return nil
    }

    private func applyRemoteValue(
        for conflict: IntegrationConflict,
        allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        dataController: InventoryDataController
    ) {
        let targetUnits = Swift.max(Int64(0), conflict.remoteUnits)
        if let localItemID = conflict.localItemID,
           let item = allItems.first(where: { $0.id == localItemID }) {
            if item.isLiquid {
                item.applyTotalGallons(Double(targetUnits))
            } else {
                item.applyTotalNonLiquidUnits(targetUnits)
            }
            item.assignWorkspaceIfNeeded(workspaceID)
            item.updatedAt = Date()
            dataController.save()
            return
        }

        if conflict.type == .missingLocalItem {
            let context = dataController.container.viewContext
            let item = InventoryItemEntity(context: context)
            item.id = UUID()
            item.name = conflict.remoteItemName.isEmpty ? "Remote Item" : conflict.remoteItemName
            item.quantity = targetUnits
            item.notes = "Created from integration conflict resolution."
            item.category = "Imported"
            item.location = ""
            item.unitsPerCase = 0
            item.looseUnits = 0
            item.eachesPerUnit = 0
            item.looseEaches = 0
            item.isLiquid = false
            item.gallonFraction = 0
            item.isPinned = false
            item.barcode = ""
            item.averageDailyUsage = 0
            item.leadTimeDays = 0
            item.safetyStockUnits = 0
            item.preferredSupplier = ""
            item.supplierSKU = ""
            item.minimumOrderQuantity = 0
            item.reorderCasePack = 0
            item.leadTimeVarianceDays = 0
            item.workspaceID = workspaceKey(for: workspaceID) == "all" ? "" : workspaceKey(for: workspaceID)
            item.recentDemandSamples = ""
            item.createdAt = Date()
            item.updatedAt = Date()
            item.applyTotalNonLiquidUnits(targetUnits)
            dataController.save()
        }
    }

    @discardableResult
    func createBackup(
        title: String,
        from allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        actorName: String
    ) -> InventoryBackupSnapshot {
        let workspaceKey = workspaceKey(for: workspaceID)
        let snapshot = backupService.makeSnapshot(
            title: title,
            from: allItems,
            workspaceID: workspaceID
        )

        backups.insert(snapshot, at: 0)
        backups = Array(backups.prefix(40))
        persist()

        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .backupCreated,
            summary: "Created backup '\(title)' with \(snapshot.itemCount) items.",
            deltaUnits: 0,
            estimatedSecondsSaved: 90,
            shrinkImpactUnits: 0
        )

        return snapshot
    }

    @discardableResult
    func restoreBackup(
        _ snapshot: InventoryBackupSnapshot,
        allItems: [InventoryItemEntity],
        context: NSManagedObjectContext,
        dataController: InventoryDataController,
        actorName: String
    ) -> Int {
        let workspaceKey = snapshot.workspaceKey
        let workspaceID = workspaceKey == "all" ? nil : UUID(uuidString: workspaceKey)

        _ = createGuardBackupIfNeeded(
            reason: "Restore backup",
            from: allItems,
            workspaceID: workspaceID,
            actorName: actorName,
            cooldownMinutes: 0
        )

        let restored = backupService.restore(
            snapshot: snapshot,
            existingItems: allItems,
            context: context
        )

        dataController.save()
        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .backupRestored,
            summary: "Restored backup '\(snapshot.title)' (\(restored) items).",
            deltaUnits: 0,
            estimatedSecondsSaved: 180,
            shrinkImpactUnits: 0
        )
        return restored
    }

    func exportCSV(
        from allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        actorName: String
    ) throws -> URL {
        let workspaceKey = workspaceID?.uuidString ?? "all"
        let scoped = PlatformStoreHelpers.scopeItems(allItems, workspaceID: workspaceID)
        let header = [
            "name",
            "barcode",
            "category",
            "location",
            "isLiquid",
            "quantity",
            "unitsPerCase",
            "looseUnits",
            "eachesPerUnit",
            "looseEaches",
            "averageDailyUsage",
            "leadTimeDays",
            "safetyStockUnits",
            "preferredSupplier",
            "supplierSKU",
            "minimumOrderQuantity",
            "reorderCasePack",
            "leadTimeVarianceDays",
            "notes"
        ]
        var lines: [String] = [header.joined(separator: ",")]
        for item in scoped {
            let row: [String] = [
                item.name,
                item.barcode,
                item.category,
                item.location,
                item.isLiquid ? "true" : "false",
                "\(item.quantity)",
                "\(item.unitsPerCase)",
                "\(item.looseUnits)",
                "\(item.eachesPerUnit)",
                "\(item.looseEaches)",
                String(format: "%.3f", item.averageDailyUsage),
                "\(item.leadTimeDays)",
                "\(item.safetyStockUnits)",
                item.preferredSupplier,
                item.supplierSKU,
                "\(item.minimumOrderQuantity)",
                "\(item.reorderCasePack)",
                "\(item.leadTimeVarianceDays)",
                item.notes
            ]
            lines.append(row.map(PlatformStoreHelpers.csvEscaped).joined(separator: ","))
        }

        let csv = lines.joined(separator: "\n")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "inventory_export_\(timestamp).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try csv.write(to: url, atomically: true, encoding: .utf8)

        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .csvExport,
            summary: "Exported CSV with \(scoped.count) items.",
            deltaUnits: 0,
            estimatedSecondsSaved: 120,
            shrinkImpactUnits: 0
        )
        return url
    }

    func exportInventoryLedgerCSV(
        workspaceID: UUID?,
        actorName: String,
        includeSynced: Bool = true,
        limit: Int = 2000
    ) throws -> URL {
        let workspaceKey = workspaceID?.uuidString ?? "all"
        let scopedEvents = inventoryEvents(
            for: workspaceID,
            limit: max(0, limit),
            includeSynced: includeSynced
        )

        let header = [
            "event_id",
            "workspace_key",
            "created_at",
            "actor_name",
            "event_type",
            "source",
            "reason",
            "item_id",
            "item_name",
            "item_category",
            "item_location",
            "delta_units",
            "resulting_units",
            "sync_status",
            "sync_attempt_count",
            "last_sync_at",
            "last_sync_error",
            "correlation_id"
        ]
        var lines: [String] = [header.joined(separator: ",")]
        lines.reserveCapacity(scopedEvents.count + 1)

        for event in scopedEvents {
            let row: [String] = [
                event.id.uuidString,
                event.workspaceKey,
                event.createdAt.ISO8601Format(),
                event.actorName,
                event.type.rawValue,
                event.source,
                event.reason,
                event.itemID?.uuidString ?? "",
                event.itemName,
                event.itemCategory,
                event.itemLocation,
                "\(event.deltaUnits)",
                event.resultingUnits.map { "\($0)" } ?? "",
                event.syncStatus.rawValue,
                "\(event.syncAttemptCount)",
                event.lastSyncAt?.ISO8601Format() ?? "",
                event.lastSyncError ?? "",
                event.correlationID
            ]
            lines.append(row.map(PlatformStoreHelpers.csvEscaped).joined(separator: ","))
        }

        let csv = lines.joined(separator: "\n")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "inventory_event_ledger_\(timestamp).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try csv.write(to: url, atomically: true, encoding: .utf8)

        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .csvExport,
            summary: "Exported inventory event ledger with \(scopedEvents.count) event(s).",
            deltaUnits: 0,
            estimatedSecondsSaved: max(20, scopedEvents.count),
            shrinkImpactUnits: 0
        )

        return url
    }

    func importCSV(
        _ text: String,
        allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        actorName: String,
        context: NSManagedObjectContext,
        dataController: InventoryDataController
    ) -> CSVImportSummary {
        let workspaceKey = workspaceID?.uuidString ?? "all"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CSVImportSummary(createdCount: 0, updatedCount: 0, skippedCount: 0)
        }

        let rows = PlatformStoreHelpers.parseCSVRows(trimmed)
        guard rows.count > 1 else {
            return CSVImportSummary(createdCount: 0, updatedCount: 0, skippedCount: rows.count)
        }

        _ = createGuardBackupIfNeeded(
            reason: "CSV import",
            from: allItems,
            workspaceID: workspaceID,
            actorName: actorName,
            cooldownMinutes: 15
        )

        let header = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let indexByField = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        var scopedItems = PlatformStoreHelpers.scopeItems(allItems, workspaceID: workspaceID)
        var byBarcode: [String: InventoryItemEntity] = [:]
        var byName: [String: InventoryItemEntity] = [:]
        for item in scopedItems {
            let normalizedBarcode = PlatformStoreHelpers.normalizedBarcode(item.barcode)
            if !normalizedBarcode.isEmpty {
                byBarcode[normalizedBarcode] = item
            }
            let nameKey = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !nameKey.isEmpty {
                byName[nameKey] = item
            }
        }

        var created = 0
        var updated = 0
        var skipped = 0

        for row in rows.dropFirst() {
            let name = PlatformStoreHelpers.csvValue("name", row: row, indexByField: indexByField)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                skipped += 1
                continue
            }

            let barcode = PlatformStoreHelpers.csvValue("barcode", row: row, indexByField: indexByField)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let category = PlatformStoreHelpers.csvValue("category", row: row, indexByField: indexByField)
            let location = PlatformStoreHelpers.csvValue("location", row: row, indexByField: indexByField)
            let notes = PlatformStoreHelpers.csvValue("notes", row: row, indexByField: indexByField)
            let isLiquid = PlatformStoreHelpers.boolFromString(PlatformStoreHelpers.csvValue("isliquid", row: row, indexByField: indexByField))

            let quantity = PlatformStoreHelpers.int64FromString(PlatformStoreHelpers.csvValue("quantity", row: row, indexByField: indexByField))
            let unitsPerCase = PlatformStoreHelpers.int64FromString(PlatformStoreHelpers.csvValue("unitspercase", row: row, indexByField: indexByField))
            let looseUnits = PlatformStoreHelpers.int64FromString(PlatformStoreHelpers.csvValue("looseunits", row: row, indexByField: indexByField))
            let eachesPerUnit = PlatformStoreHelpers.int64FromString(PlatformStoreHelpers.csvValue("eachesperunit", row: row, indexByField: indexByField))
            let looseEaches = PlatformStoreHelpers.int64FromString(PlatformStoreHelpers.csvValue("looseeaches", row: row, indexByField: indexByField))
            let averageDailyUsage = PlatformStoreHelpers.doubleFromString(PlatformStoreHelpers.csvValue("averagedailyusage", row: row, indexByField: indexByField))
            let leadTimeDays = PlatformStoreHelpers.int64FromString(PlatformStoreHelpers.csvValue("leadtimedays", row: row, indexByField: indexByField))
            let safetyStockUnits = PlatformStoreHelpers.int64FromString(PlatformStoreHelpers.csvValue("safetystockunits", row: row, indexByField: indexByField))
            let preferredSupplier = PlatformStoreHelpers.csvValue("preferredsupplier", row: row, indexByField: indexByField)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let supplierSKU = PlatformStoreHelpers.csvValue("suppliersku", row: row, indexByField: indexByField)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let minimumOrderQuantity = PlatformStoreHelpers.int64FromString(PlatformStoreHelpers.csvValue("minimumorderquantity", row: row, indexByField: indexByField))
            let reorderCasePack = PlatformStoreHelpers.int64FromString(PlatformStoreHelpers.csvValue("reordercasepack", row: row, indexByField: indexByField))
            let leadTimeVarianceDays = PlatformStoreHelpers.int64FromString(PlatformStoreHelpers.csvValue("leadtimevariancedays", row: row, indexByField: indexByField))

            let barcodeKey = PlatformStoreHelpers.normalizedBarcode(barcode)
            let nameKey = name.lowercased()
            let existing = (!barcodeKey.isEmpty ? byBarcode[barcodeKey] : nil) ?? byName[nameKey]

            let target: InventoryItemEntity
            if let existing {
                target = existing
                updated += 1
            } else {
                target = InventoryItemEntity(context: context)
                target.id = UUID()
                target.createdAt = Date()
                target.workspaceID = workspaceKey == "all" ? "" : workspaceKey
                created += 1
            }

            target.name = name
            target.barcode = barcode
            target.category = category
            target.location = location
            target.notes = notes
            target.isLiquid = isLiquid
            target.unitsPerCase = max(0, unitsPerCase)
            target.quantity = max(0, quantity)
            target.looseUnits = max(0, looseUnits)
            target.eachesPerUnit = max(0, eachesPerUnit)
            target.looseEaches = max(0, looseEaches)
            target.averageDailyUsage = max(0, averageDailyUsage)
            target.leadTimeDays = max(0, leadTimeDays)
            target.safetyStockUnits = max(0, safetyStockUnits)
            target.preferredSupplier = preferredSupplier
            target.supplierSKU = supplierSKU
            target.minimumOrderQuantity = max(0, minimumOrderQuantity)
            target.reorderCasePack = max(0, reorderCasePack)
            target.leadTimeVarianceDays = max(0, leadTimeVarianceDays)
            target.updatedAt = Date()
            target.assignWorkspaceIfNeeded(workspaceID)

            let refreshedBarcode = PlatformStoreHelpers.normalizedBarcode(target.barcode)
            if !refreshedBarcode.isEmpty {
                byBarcode[refreshedBarcode] = target
            }
            byName[nameKey] = target
        }

        dataController.save()
        scopedItems = PlatformStoreHelpers.scopeItems(allItems, workspaceID: workspaceID)
        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .csvImport,
            summary: "Imported CSV: \(created) created, \(updated) updated, \(skipped) skipped.",
            deltaUnits: Int64(scopedItems.count),
            estimatedSecondsSaved: max(120, (created + updated) * 25),
            shrinkImpactUnits: Int64(max(0, updated / 2))
        )
        return CSVImportSummary(createdCount: created, updatedCount: updated, skippedCount: skipped)
    }

    @discardableResult
    func applyReturn(
        item: InventoryItemEntity,
        units: Int64,
        reason: String,
        actorName: String,
        workspaceID: UUID?,
        dataController: InventoryDataController
    ) -> Bool {
        guard units > 0 else { return false }

        let backupItems = PlatformStoreHelpers.allItemsForBackup(from: dataController)
        _ = createGuardBackupIfNeeded(
            reason: "Manual return",
            from: backupItems,
            workspaceID: workspaceID,
            actorName: actorName,
            cooldownMinutes: 90
        )

        if item.isLiquid {
            item.applyTotalGallons(item.totalGallonsOnHand - Double(units))
        } else {
            item.applyTotalNonLiquidUnits(item.totalUnitsOnHand - units)
        }
        item.updatedAt = Date()
        item.assignWorkspaceIfNeeded(workspaceID)
        dataController.save()

        appendAudit(
            workspaceKey: workspaceID?.uuidString ?? "all",
            actorName: actorName,
            type: .return,
            summary: "Processed return for \(item.name): \(units) unit(s). Reason: \(reason).",
            deltaUnits: -units,
            estimatedSecondsSaved: 75,
            shrinkImpactUnits: units
        )
        recordInventoryMovement(
            item: item,
            deltaUnits: -units,
            actorName: actorName,
            workspaceID: workspaceID,
            type: .return,
            source: "ops-return",
            reason: reason
        )
        return true
    }

    @discardableResult
    func applyAdjustment(
        item: InventoryItemEntity,
        deltaUnits: Int64,
        reasonCode: InventoryAdjustmentReasonCode,
        reasonDetail: String,
        highRiskConfirmed: Bool = false,
        actorName: String,
        workspaceID: UUID?,
        dataController: InventoryDataController
    ) -> Bool {
        guard deltaUnits != 0 else { return false }
        guard !isHighRiskAdjustment(deltaUnits: deltaUnits) || highRiskConfirmed else { return false }
        let reason = adjustmentReasonSummary(reasonCode: reasonCode, detail: reasonDetail)

        let backupItems = PlatformStoreHelpers.allItemsForBackup(from: dataController)
        _ = createGuardBackupIfNeeded(
            reason: "Manual adjustment",
            from: backupItems,
            workspaceID: workspaceID,
            actorName: actorName,
            cooldownMinutes: 90
        )

        if item.isLiquid {
            item.applyTotalGallons(item.totalGallonsOnHand + Double(deltaUnits))
        } else {
            item.applyTotalNonLiquidUnits(item.totalUnitsOnHand + deltaUnits)
        }
        item.updatedAt = Date()
        item.assignWorkspaceIfNeeded(workspaceID)
        dataController.save()

        appendAudit(
            workspaceKey: workspaceID?.uuidString ?? "all",
            actorName: actorName,
            type: .adjustment,
            summary: "Adjusted \(item.name) by \(deltaUnits) unit(s). Reason: \(reason).",
            deltaUnits: deltaUnits,
            estimatedSecondsSaved: 60,
            shrinkImpactUnits: deltaUnits < 0 ? abs(deltaUnits) : 0
        )
        recordInventoryMovement(
            item: item,
            deltaUnits: deltaUnits,
            actorName: actorName,
            workspaceID: workspaceID,
            type: .adjustment,
            source: "ops-adjustment",
            reason: reason
        )
        return true
    }

    func logReceipt(
        item: InventoryItemEntity,
        units: Int64,
        actorName: String,
        workspaceID: UUID?,
        source: String = "manual-receive",
        reason: String = ""
    ) {
        guard units > 0 else { return }
        appendAudit(
            workspaceKey: workspaceID?.uuidString ?? "all",
            actorName: actorName,
            type: .receive,
            summary: "Received \(units) unit(s) for \(item.name).",
            deltaUnits: units,
            estimatedSecondsSaved: 45,
            shrinkImpactUnits: 0
        )
        recordInventoryMovement(
            item: item,
            deltaUnits: units,
            actorName: actorName,
            workspaceID: workspaceID,
            type: .receipt,
            source: source,
            reason: reason
        )
    }

    func logReceipt(
        itemName: String,
        units: Int64,
        actorName: String,
        workspaceID: UUID?
    ) {
        guard units > 0 else { return }
        appendAudit(
            workspaceKey: workspaceID?.uuidString ?? "all",
            actorName: actorName,
            type: .receive,
            summary: "Received \(units) unit(s) for \(itemName).",
            deltaUnits: units,
            estimatedSecondsSaved: 45,
            shrinkImpactUnits: 0
        )
        appendInventoryEvent(
            workspaceKey: workspaceID?.uuidString ?? "all",
            actorName: actorName,
            type: .receipt,
            source: "legacy-receive",
            reason: "",
            itemID: nil,
            itemName: itemName,
            itemCategory: "",
            itemLocation: "",
            deltaUnits: units,
            resultingUnits: nil,
            correlationID: UUID().uuidString
        )
    }

    func ownerImpactReport(
        for allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        windowDays: Int = 30
    ) -> OwnerImpactReport {
        analyticsService.ownerImpactReport(
            auditEvents: auditEvents,
            allItems: allItems,
            workspaceID: workspaceID,
            windowDays: windowDays
        )
    }

    func recordCountSession(
        type: CountSessionType,
        workspaceID: UUID?,
        actorName: String,
        startedAt: Date,
        finishedAt: Date = Date(),
        itemCount: Int,
        highVarianceCount: Int,
        blindModeEnabled: Bool,
        targetDurationMinutes: Int? = nil,
        zoneTitle: String? = nil,
        note: String? = nil
    ) {
        let normalizedItemCount = max(0, itemCount)
        guard normalizedItemCount > 0 else { return }

        let normalizedHighVariance = min(max(0, highVarianceCount), normalizedItemCount)
        let normalizedFinishedAt = max(startedAt, finishedAt)
        let normalizedTargetMinutes: Int? = {
            guard let targetDurationMinutes else { return nil }
            let normalized = max(1, targetDurationMinutes)
            return min(300, normalized)
        }()
        let trimmedZone = zoneTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedZone = (trimmedZone?.isEmpty == false) ? trimmedZone : nil
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = (trimmedNote?.isEmpty == false) ? trimmedNote : nil

        let record = CountSessionRecord(
            id: UUID(),
            workspaceKey: workspaceKey(for: workspaceID),
            type: type,
            startedAt: startedAt,
            finishedAt: normalizedFinishedAt,
            itemCount: normalizedItemCount,
            highVarianceCount: normalizedHighVariance,
            blindModeEnabled: blindModeEnabled,
            targetDurationMinutes: normalizedTargetMinutes,
            zoneTitle: normalizedZone,
            note: normalizedNote
        )

        countSessionHistory.insert(record, at: 0)
        countSessionHistory.sort(by: { $0.finishedAt > $1.finishedAt })
        countSessionHistory = Array(countSessionHistory.prefix(500))

        let baselineSecondsPerItem = blindModeEnabled ? 44.0 : 36.0
        let actualSecondsPerItem = record.durationSeconds / Double(max(1, normalizedItemCount))
        let estimatedSecondsSaved = max(
            0,
            Int((baselineSecondsPerItem - actualSecondsPerItem) * Double(normalizedItemCount))
        )
        let roundedMinutes = max(1, Int(record.durationMinutes.rounded()))
        let zoneFragment = normalizedZone.map { " in \($0)" } ?? ""
        let targetFragment: String
        if let normalizedTargetMinutes {
            targetFragment = " Target \(normalizedTargetMinutes)m \(record.metTarget == true ? "met" : "missed")."
        } else {
            targetFragment = ""
        }
        let summary = "\(type.title)\(zoneFragment): \(normalizedItemCount) item(s) in \(roundedMinutes)m at \(String(format: "%.1f", record.itemsPerMinute))/min.\(targetFragment)"
        appendAudit(
            workspaceKey: record.workspaceKey,
            actorName: actorName,
            type: .countSession,
            summary: summary,
            deltaUnits: 0,
            estimatedSecondsSaved: estimatedSecondsSaved,
            shrinkImpactUnits: Int64(normalizedHighVariance)
        )
    }

    func countSessions(
        for workspaceID: UUID?,
        windowDays: Int = 14,
        limit: Int = 80
    ) -> [CountSessionRecord] {
        analyticsService.countSessions(
            history: countSessionHistory,
            workspaceID: workspaceID,
            windowDays: windowDays,
            limit: limit
        )
    }

    func countProductivitySummary(
        workspaceID: UUID?,
        windowDays: Int = 14
    ) -> CountProductivitySummary {
        analyticsService.countProductivitySummary(
            history: countSessionHistory,
            workspaceID: workspaceID,
            windowDays: windowDays
        )
    }

    func valueTrackingSnapshot(
        workspaceID: UUID?,
        window: ValueTrackingWindow,
        referenceDate: Date = Date()
    ) -> ValueTrackingSnapshot {
        analyticsService.valueTrackingSnapshot(
            workspaceID: workspaceID,
            window: window,
            referenceDate: referenceDate,
            auditEvents: auditEvents,
            countSessionHistory: countSessionHistory
        )
    }

    func isHighRiskAdjustment(deltaUnits: Int64) -> Bool {
        abs(deltaUnits) >= highRiskAdjustmentThresholdUnits
    }

    func adjustmentReasonSummary(
        reasonCode: InventoryAdjustmentReasonCode,
        detail: String
    ) -> String {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetail.isEmpty else { return reasonCode.rawValue }
        return "\(reasonCode.rawValue): \(trimmedDetail)"
    }

    func recordExceptionResolution(
        workspaceID: UUID?,
        resolvedCount: Int = 1,
        source: String
    ) {
        let normalizedCount = max(1, resolvedCount)
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = PilotExceptionResolutionEvent(
            id: UUID(),
            workspaceKey: workspaceKey(for: workspaceID),
            createdAt: Date(),
            resolvedCount: normalizedCount,
            source: normalizedSource.isEmpty ? "exception-feed" : normalizedSource
        )
        pilotExceptionEvents.insert(event, at: 0)
        pilotExceptionEvents = Array(pilotExceptionEvents.prefix(2000))
        persist()
    }

    func pilotDailyMetrics(
        workspaceID: UUID?,
        day: Date = Date()
    ) -> PilotDailyMetrics {
        analyticsService.pilotDailyMetrics(
            workspaceID: workspaceID,
            day: day,
            countSessionHistory: countSessionHistory,
            inventoryEvents: inventoryEvents,
            pilotExceptionEvents: pilotExceptionEvents
        )
    }

    func exportPilotValidationCSV(
        workspaceID: UUID?,
        actorName: String,
        days: Int = 14
    ) throws -> URL {
        let normalizedDays = min(90, max(1, days))
        let workspaceKey = workspaceKey(for: workspaceID)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let header = [
            "date",
            "first_count_start",
            "last_count_finish",
            "count_session_runs",
            "items_counted",
            "exceptions_resolved",
            "adjustment_count",
            "adjustment_units_net"
        ]
        var lines: [String] = [header.joined(separator: ",")]
        lines.reserveCapacity(normalizedDays + 1)

        for offset in stride(from: normalizedDays - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let metrics = pilotDailyMetrics(workspaceID: workspaceID, day: day)
            let row: [String] = [
                formatter.string(from: day),
                metrics.firstCountStartedAt?.ISO8601Format() ?? "",
                metrics.lastCountFinishedAt?.ISO8601Format() ?? "",
                "\(metrics.countSessionRuns)",
                "\(metrics.itemsCounted)",
                "\(metrics.exceptionsResolved)",
                "\(metrics.adjustmentCount)",
                "\(metrics.netAdjustmentUnits)"
            ]
            lines.append(row.map(PlatformStoreHelpers.csvEscaped).joined(separator: ","))
        }

        let csv = lines.joined(separator: "\n")
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = timestampFormatter.string(from: Date())
        let filename = "pilot_validation_\(workspaceKey)_\(timestamp).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try csv.write(to: url, atomically: true, encoding: .utf8)

        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .csvExport,
            summary: "Exported pilot validation CSV for \(normalizedDays) day(s).",
            deltaUnits: 0,
            estimatedSecondsSaved: max(20, normalizedDays * 8),
            shrinkImpactUnits: 0
        )
        return url
    }

    func recordShiftRunCompletion(
        workspaceID: UUID?,
        actorName: String,
        countQueueSize: Int,
        exceptionCount: Int,
        replenishmentCount: Int
    ) {
        let snapshot = valueTrackingSnapshot(
            workspaceID: workspaceID,
            window: .shift
        )
        let summary = "Shift closed: queue \(countQueueSize), exceptions \(exceptionCount), replenishment \(replenishmentCount), saved \(snapshot.minutesSaved)m."
        appendAudit(
            workspaceKey: workspaceKey(for: workspaceID),
            actorName: actorName,
            type: .shiftRun,
            summary: summary,
            deltaUnits: 0,
            estimatedSecondsSaved: max(15, snapshot.minutesSaved * 60),
            shrinkImpactUnits: max(0, snapshot.shrinkRiskResolved)
        )
    }

    @discardableResult
    func createGuardBackupIfNeeded(
        reason: String,
        from allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        actorName: String,
        cooldownMinutes: Int = 90,
        minimumItemCount: Int = 1
    ) -> InventoryBackupSnapshot? {
        let workspaceKey = workspaceKey(for: workspaceID)
        let scopedCount = backupService.scopedItemCount(in: allItems, workspaceID: workspaceID)
        guard scopedCount >= max(0, minimumItemCount) else {
            return nil
        }

        let reasonToken = PlatformStoreHelpers.normalizedGuardBackupToken(reason)
        let key = PlatformStoreHelpers.guardBackupKey(prefix: guardBackupPrefix, workspaceKey: workspaceKey, reasonToken: reasonToken)
        let now = Date()
        let lastRun = defaults.double(forKey: key)
        if cooldownMinutes > 0, lastRun > 0 {
            let cooldown = TimeInterval(max(1, cooldownMinutes) * 60)
            if now.timeIntervalSince1970 - lastRun < cooldown {
                return nil
            }
        }

        let title = "Auto backup: \(reason)"
        let snapshot = createBackup(
            title: title,
            from: allItems,
            workspaceID: workspaceID,
            actorName: actorName
        )
        defaults.set(now.timeIntervalSince1970, forKey: key)
        return snapshot
    }

    func runBackupRestoreHealthCheck(
        from allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        actorName: String
    ) -> BackupRestoreHealthCheckResult {
        let timestampLabel = Date().formatted(date: .abbreviated, time: .shortened)
        let snapshot = createBackup(
            title: "Restore check \(timestampLabel)",
            from: allItems,
            workspaceID: workspaceID,
            actorName: actorName
        )

        let expectedItemCount = backupService.scopedItemCount(in: allItems, workspaceID: workspaceID)
        let snapshotFound = backups.contains { $0.id == snapshot.id && $0.workspaceKey == snapshot.workspaceKey }
        let payloadRoundTripValid = backupService.payloadRoundTripValid(snapshot)

        return BackupRestoreHealthCheckResult(
            checkedAt: Date(),
            snapshotTitle: snapshot.title,
            expectedItemCount: expectedItemCount,
            snapshotItemCount: snapshot.itemCount,
            snapshotFound: snapshotFound,
            payloadRoundTripValid: payloadRoundTripValid
        )
    }

    func backups(for workspaceID: UUID?) -> [InventoryBackupSnapshot] {
        let workspaceKey = workspaceID?.uuidString ?? "all"
        return backups.filter { $0.workspaceKey == workspaceKey }
    }

    func syncJobs(for workspaceID: UUID?) -> [IntegrationSyncJob] {
        let workspaceKey = workspaceID?.uuidString ?? "all"
        return syncJobs.filter { $0.workspaceKey == workspaceKey }
    }

    func syncRetryJobs(
        for workspaceID: UUID?,
        includeResolved: Bool = true,
        limit: Int = 60
    ) -> [IntegrationSyncRetryJob] {
        let workspaceKey = workspaceID?.uuidString ?? "all"
        return syncRetryJobs
            .filter { job in
                guard job.workspaceKey == workspaceKey else { return false }
                if includeResolved {
                    return true
                }
                return job.status == .queued
            }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .prefix(limit)
            .map { $0 }
    }

    @discardableResult
    func processDueSyncRetries(
        workspaceID: UUID?,
        actorName: String,
        allItems: [InventoryItemEntity],
        maxJobs: Int = 3
    ) -> Int {
        let workspaceKey = workspaceKey(for: workspaceID)
        let now = Date()
        let dueIDs = syncRetryJobs
            .filter { job in
                job.workspaceKey == workspaceKey
                    && job.status == .queued
                    && job.nextAttemptAt <= now
            }
            .sorted(by: { $0.nextAttemptAt < $1.nextAttemptAt })
            .prefix(max(0, maxJobs))
            .map(\.id)

        var processed = 0
        for id in dueIDs {
            if processRetryAttempt(
                retryID: id,
                workspaceID: workspaceID,
                actorName: actorName,
                allItems: allItems
            ) {
                processed += 1
            }
        }
        return processed
    }

    @discardableResult
    func retrySyncJobNow(
        _ retryID: UUID,
        workspaceID: UUID?,
        actorName: String,
        allItems: [InventoryItemEntity]
    ) -> Bool {
        processRetryAttempt(
            retryID: retryID,
            workspaceID: workspaceID,
            actorName: actorName,
            allItems: allItems
        )
    }

    @discardableResult
    func dismissSyncRetryJob(_ retryID: UUID) -> Bool {
        guard let index = syncRetryJobs.firstIndex(where: { $0.id == retryID }) else {
            return false
        }
        syncRetryJobs.remove(at: index)
        persist()
        return true
    }

    func auditEvents(for workspaceID: UUID?, limit: Int = 80) -> [PlatformAuditEvent] {
        let workspaceKey = workspaceID?.uuidString ?? "all"
        return auditEvents
            .filter { $0.workspaceKey == workspaceKey }
            .prefix(limit)
            .map { $0 }
    }

    func inventoryEvents(
        for workspaceID: UUID?,
        limit: Int = 120,
        includeSynced: Bool = true
    ) -> [InventoryLedgerEvent] {
        let workspaceKey = workspaceID?.uuidString ?? "all"
        return inventoryEvents
            .filter { event in
                guard event.workspaceKey == workspaceKey else { return false }
                if includeSynced {
                    return true
                }
                return event.syncStatus != .synced
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    func pendingInventoryEventCount(for workspaceID: UUID?) -> Int {
        let workspaceKey = workspaceID?.uuidString ?? "all"
        return inventoryEvents.filter { event in
            event.workspaceKey == workspaceKey && event.syncStatus != .synced
        }.count
    }

    func inventoryReconnectBrief(workspaceID: UUID?) -> InventoryReconnectBrief {
        let workspaceKey = workspaceKey(for: workspaceID)
        let workspaceEvents = inventoryEvents.filter { $0.workspaceKey == workspaceKey }
        let providerStates = Dictionary(uniqueKeysWithValues: IntegrationProvider.allCases.map { provider in
            (
                provider,
                integrationSecretState(for: provider, workspaceID: workspaceID)
            )
        })
        return PlatformStoreInsights.inventoryReconnectBrief(
            workspaceEvents: workspaceEvents,
            providerStates: providerStates
        )
    }

    @discardableResult
    func syncInventoryLedger(
        workspaceID: UUID?,
        actorName: String,
        allItems: [InventoryItemEntity],
        maxEvents: Int = 200
    ) -> InventoryLedgerSyncRun {
        let workspaceKey = workspaceKey(for: workspaceID)
        let eventLimit = max(1, maxEvents)
        let targetIndices = inventoryEvents.indices
            .filter { index in
                inventoryEvents[index].workspaceKey == workspaceKey
                    && inventoryEvents[index].syncStatus != .synced
            }
            .sorted { lhs, rhs in
                inventoryEvents[lhs].createdAt < inventoryEvents[rhs].createdAt
            }
            .prefix(eventLimit)

        let attempted = targetIndices.count
        guard attempted > 0 else {
            return InventoryLedgerSyncRun(
                attempted: 0,
                synced: 0,
                failed: 0,
                provider: nil,
                blockedByConnection: false,
                message: "No pending ledger events."
            )
        }

        var selectedProvider: IntegrationProvider?
        for provider in IntegrationProvider.allCases {
            if preparedConnectionForSync(
                provider: provider,
                workspaceID: workspaceID,
                actorName: actorName
            ) != nil {
                selectedProvider = provider
                break
            }
        }

        var syncSucceeded = false
        if let provider = selectedProvider {
            syncSucceeded = runConnectedSync(
                provider: provider,
                workspaceID: workspaceID,
                actorName: actorName,
                allItems: allItems
            )
        }

        let now = Date()
        let failureMessage: String = {
            if selectedProvider == nil {
                return "No connected provider. Connect QuickBooks or Shopify in Integration Hub."
            }
            if let provider = selectedProvider, !syncSucceeded {
                return "\(provider.title) sync failed. Review retry queue and token health."
            }
            return ""
        }()

        var synced = 0
        var failed = 0
        for index in targetIndices {
            inventoryEvents[index].syncAttemptCount += 1
            inventoryEvents[index].lastSyncAt = now
            if syncSucceeded {
                inventoryEvents[index].syncStatus = .synced
                inventoryEvents[index].lastSyncError = nil
                synced += 1
            } else {
                inventoryEvents[index].syncStatus = .failed
                inventoryEvents[index].lastSyncError = failureMessage
                failed += 1
            }
        }

        persist()
        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .sync,
            summary: syncSucceeded
                ? "Auto-sync cleared \(synced) inventory ledger event(s)."
                : "Auto-sync failed for \(attempted) inventory ledger event(s).",
            deltaUnits: 0,
            estimatedSecondsSaved: syncSucceeded ? synced * 3 : 10,
            shrinkImpactUnits: 0
        )

        let message: String
        if syncSucceeded {
            message = "Synced \(synced) inventory event(s)."
        } else if selectedProvider == nil {
            message = "No connected provider found. Connect one in Integration Hub."
        } else if let provider = selectedProvider {
            message = "\(provider.title) sync failed. Check retry queue."
        } else {
            message = "Ledger sync failed."
        }

        return InventoryLedgerSyncRun(
            attempted: attempted,
            synced: synced,
            failed: failed,
            provider: selectedProvider,
            blockedByConnection: !syncSucceeded,
            message: message
        )
    }

    func inventoryConfidenceOverview(
        for allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        weakestLimit: Int = 6
    ) -> InventoryConfidenceOverview {
        let scopedItems = PlatformStoreHelpers.scopeItems(allItems, workspaceID: workspaceID)
        guard !scopedItems.isEmpty else {
            return InventoryConfidenceOverview(
                itemCount: 0,
                averageScore: 0,
                strongCount: 0,
                watchCount: 0,
                weakCount: 0,
                criticalCount: 0,
                weakestItems: []
            )
        }

        let allSignals = inventoryConfidenceSignals(
            for: allItems,
            workspaceID: workspaceID,
            limit: scopedItems.count
        )
        let totalScore = allSignals.reduce(0) { $0 + $1.score }
        let average = allSignals.isEmpty ? 0 : Int((Double(totalScore) / Double(allSignals.count)).rounded())

        return InventoryConfidenceOverview(
            itemCount: scopedItems.count,
            averageScore: average,
            strongCount: allSignals.filter { $0.tier == .strong }.count,
            watchCount: allSignals.filter { $0.tier == .watch }.count,
            weakCount: allSignals.filter { $0.tier == .weak }.count,
            criticalCount: allSignals.filter { $0.tier == .critical }.count,
            weakestItems: Array(allSignals.prefix(max(0, weakestLimit)))
        )
    }

    func inventoryConfidenceSignals(
        for allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        limit: Int = 20
    ) -> [InventoryConfidenceSignal] {
        let scopedItems = PlatformStoreHelpers.scopeItems(allItems, workspaceID: workspaceID)
        guard !scopedItems.isEmpty else { return [] }

        let workspaceKey = workspaceKey(for: workspaceID)
        let workspaceEvents = inventoryEvents.filter { $0.workspaceKey == workspaceKey }
        return PlatformStoreInsights.inventoryConfidenceSignals(
            scopedItems: scopedItems,
            workspaceEvents: workspaceEvents,
            limit: limit
        )
    }

    @discardableResult
    func markInventoryEventsSynced(
        workspaceID: UUID?,
        actorName: String,
        maxCount: Int = 200
    ) -> Int {
        let workspaceKey = workspaceID?.uuidString ?? "all"
        let now = Date()
        var processed = 0
        let limit = max(1, maxCount)

        for index in inventoryEvents.indices {
            guard inventoryEvents[index].workspaceKey == workspaceKey else { continue }
            guard inventoryEvents[index].syncStatus != .synced else { continue }
            inventoryEvents[index].syncStatus = .synced
            inventoryEvents[index].lastSyncAt = now
            inventoryEvents[index].lastSyncError = nil
            inventoryEvents[index].syncAttemptCount += 1
            processed += 1
            if processed >= limit {
                break
            }
        }

        guard processed > 0 else { return 0 }
        persist()
        appendAudit(
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: .sync,
            summary: "Ledger sync marked \(processed) inventory event(s) as synced.",
            deltaUnits: 0,
            estimatedSecondsSaved: processed * 2,
            shrinkImpactUnits: 0
        )
        return processed
    }

    func recordInventoryMovement(
        item: InventoryItemEntity,
        deltaUnits: Int64,
        actorName: String,
        workspaceID: UUID?,
        type: InventoryEventType,
        source: String,
        reason: String = "",
        correlationID: String = UUID().uuidString
    ) {
        guard deltaUnits != 0 else { return }
        appendInventoryEvent(
            workspaceKey: workspaceID?.uuidString ?? "all",
            actorName: actorName,
            type: type,
            source: source,
            reason: reason,
            itemID: item.id,
            itemName: item.name,
            itemCategory: item.category,
            itemLocation: item.location,
            deltaUnits: deltaUnits,
            resultingUnits: item.totalUnitsOnHand,
            correlationID: correlationID
        )
    }

    func recordCountCorrection(
        item: InventoryItemEntity,
        previousUnits: Int64,
        newUnits: Int64,
        actorName: String,
        workspaceID: UUID?,
        source: String,
        reason: String = "",
        correlationID: String = UUID().uuidString
    ) {
        let delta = newUnits - previousUnits
        guard delta != 0 else { return }
        appendInventoryEvent(
            workspaceKey: workspaceID?.uuidString ?? "all",
            actorName: actorName,
            type: .countCorrection,
            source: source,
            reason: reason,
            itemID: item.id,
            itemName: item.name,
            itemCategory: item.category,
            itemLocation: item.location,
            deltaUnits: delta,
            resultingUnits: newUnits,
            correlationID: correlationID
        )
    }

    private func appendAudit(
        workspaceKey: String,
        actorName: String,
        type: PlatformAuditType,
        summary: String,
        deltaUnits: Int64,
        estimatedSecondsSaved: Int,
        shrinkImpactUnits: Int64
    ) {
        let event = PlatformAuditEvent(
            id: UUID(),
            workspaceKey: workspaceKey,
            actorName: actorName,
            type: type,
            createdAt: Date(),
            summary: summary,
            deltaUnits: deltaUnits,
            estimatedSecondsSaved: max(0, estimatedSecondsSaved),
            shrinkImpactUnits: shrinkImpactUnits
        )
        auditEvents.insert(event, at: 0)
        auditEvents = Array(auditEvents.prefix(400))
        persist()
    }

    private func appendInventoryEvent(
        workspaceKey: String,
        actorName: String,
        type: InventoryEventType,
        source: String,
        reason: String,
        itemID: UUID?,
        itemName: String,
        itemCategory: String,
        itemLocation: String,
        deltaUnits: Int64,
        resultingUnits: Int64?,
        correlationID: String
    ) {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = InventoryLedgerEvent(
            id: UUID(),
            workspaceKey: workspaceKey,
            actorName: actorName,
            createdAt: Date(),
            type: type,
            source: normalizedSource.isEmpty ? "manual" : normalizedSource,
            reason: normalizedReason,
            itemID: itemID,
            itemName: itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Item" : itemName,
            itemCategory: itemCategory,
            itemLocation: itemLocation,
            deltaUnits: deltaUnits,
            resultingUnits: resultingUnits,
            correlationID: correlationID,
            syncStatus: .pending,
            syncAttemptCount: 0,
            lastSyncAt: nil,
            lastSyncError: nil
        )
        inventoryEvents.insert(event, at: 0)
        inventoryEvents = Array(inventoryEvents.prefix(2000))
        persist()
    }

    private func sanitizedConnectionsForPersistence() -> [IntegrationConnection] {
        connections.map { connection in
            var scrubbed = connection
            scrubbed.accessToken = hasSecret(
                kind: .accessToken,
                provider: connection.provider,
                workspaceKey: connection.workspaceKey
            ) ? "stored-in-keychain" : ""
            scrubbed.refreshToken = hasSecret(
                kind: .refreshToken,
                provider: connection.provider,
                workspaceKey: connection.workspaceKey
            ) ? "stored-in-keychain" : ""
            scrubbed.webhookSecret = hasSecret(
                kind: .webhookSecret,
                provider: connection.provider,
                workspaceKey: connection.workspaceKey
            ) ? "stored-in-keychain" : ""
            return scrubbed
        }
    }

    private func migrateLegacyConnectionSecretsIfNeeded() -> Bool {
        var didChange = false
        let now = Date()

        for index in connections.indices {
            let provider = connections[index].provider
            let workspaceKey = connections[index].workspaceKey
            let legacyAccessToken = connections[index].accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let legacyRefreshToken = connections[index].refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let legacyWebhookSecret = connections[index].webhookSecret.trimmingCharacters(in: .whitespacesAndNewlines)

            if !legacyAccessToken.isEmpty && legacyAccessToken != "stored-in-keychain" {
                if !hasSecret(kind: .accessToken, provider: provider, workspaceKey: workspaceKey) {
                    _ = setSecret(legacyAccessToken, kind: .accessToken, provider: provider, workspaceKey: workspaceKey)
                }
                if connections[index].tokenExpiresAt == nil {
                    connections[index].tokenExpiresAt = now.addingTimeInterval(accessTokenLifetime)
                }
                connections[index].accessToken = ""
                didChange = true
            }

            if !legacyRefreshToken.isEmpty && legacyRefreshToken != "stored-in-keychain" {
                if !hasSecret(kind: .refreshToken, provider: provider, workspaceKey: workspaceKey) {
                    _ = setSecret(legacyRefreshToken, kind: .refreshToken, provider: provider, workspaceKey: workspaceKey)
                }
                connections[index].refreshToken = ""
                didChange = true
            }

            if !legacyWebhookSecret.isEmpty && legacyWebhookSecret != "stored-in-keychain" {
                if !hasSecret(kind: .webhookSecret, provider: provider, workspaceKey: workspaceKey) {
                    _ = setSecret(legacyWebhookSecret, kind: .webhookSecret, provider: provider, workspaceKey: workspaceKey)
                }
                connections[index].webhookSecret = ""
                didChange = true
            }
        }

        return didChange
    }

    private func normalizeConnectionStatuses() -> Bool {
        var didChange = false
        let now = Date()

        for index in connections.indices {
            let provider = connections[index].provider
            let workspaceKey = connections[index].workspaceKey
            let hasAccessToken = hasSecret(kind: .accessToken, provider: provider, workspaceKey: workspaceKey)
            if hasAccessToken && connections[index].tokenExpiresAt == nil {
                connections[index].tokenExpiresAt = now.addingTimeInterval(accessTokenLifetime)
                didChange = true
            }

            let normalizedStatus = effectiveStatus(
                currentStatus: connections[index].status,
                tokenExpiresAt: connections[index].tokenExpiresAt,
                hasAccessToken: hasAccessToken
            )
            if connections[index].status != normalizedStatus {
                connections[index].status = normalizedStatus
                didChange = true
            }

            let previousAccess = connections[index].accessToken
            let previousRefresh = connections[index].refreshToken
            let previousWebhook = connections[index].webhookSecret
            updateConnectionSecretPlaceholders(at: index)
            if previousAccess != connections[index].accessToken
                || previousRefresh != connections[index].refreshToken
                || previousWebhook != connections[index].webhookSecret {
                didChange = true
            }
        }

        return didChange
    }

    private func persist() {
        let keys = PlatformStorePersistenceKeys(
            syncJobsKey: syncJobsKey,
            syncRetryJobsKey: syncRetryJobsKey,
            auditEventsKey: auditEventsKey,
            inventoryEventsKey: inventoryEventsKey,
            countSessionsKey: countSessionsKey,
            pilotExceptionEventsKey: pilotExceptionEventsKey,
            backupsKey: backupsKey,
            connectionsKey: connectionsKey,
            webhookEventsKey: webhookEventsKey,
            conflictsKey: conflictsKey
        )
        let state = PlatformStorePersistenceState(
            syncJobs: syncJobs,
            syncRetryJobs: syncRetryJobs,
            auditEvents: auditEvents,
            inventoryEvents: inventoryEvents,
            countSessionHistory: countSessionHistory,
            pilotExceptionEvents: pilotExceptionEvents,
            backups: backups,
            connections: sanitizedConnectionsForPersistence(),
            webhookEvents: webhookEvents,
            conflicts: conflicts
        )
        pendingPersistWorkItem?.cancel()

        let defaults = self.defaults
        let workItem = DispatchWorkItem { [keys, state, defaults] in
            PlatformStorePersistenceCodec.persist(
                defaults: defaults,
                keys: keys,
                state: state
            )
        }
        pendingPersistWorkItem = workItem
        persistQueue.asyncAfter(deadline: .now() + persistDebounceInterval, execute: workItem)
    }

    private func load() {
        let keys = PlatformStorePersistenceKeys(
            syncJobsKey: syncJobsKey,
            syncRetryJobsKey: syncRetryJobsKey,
            auditEventsKey: auditEventsKey,
            inventoryEventsKey: inventoryEventsKey,
            countSessionsKey: countSessionsKey,
            pilotExceptionEventsKey: pilotExceptionEventsKey,
            backupsKey: backupsKey,
            connectionsKey: connectionsKey,
            webhookEventsKey: webhookEventsKey,
            conflictsKey: conflictsKey
        )
        let decodedState = PlatformStorePersistenceCodec.load(defaults: defaults, keys: keys)
        var shouldPersistAfterLoad = false

        syncJobs = decodedState.syncJobs
        syncRetryJobs = decodedState.syncRetryJobs
        auditEvents = decodedState.auditEvents
        inventoryEvents = decodedState.inventoryEvents
        countSessionHistory = decodedState.countSessionHistory
        pilotExceptionEvents = decodedState.pilotExceptionEvents
        backups = decodedState.backups
        connections = decodedState.connections
        webhookEvents = decodedState.webhookEvents
        conflicts = decodedState.conflicts

        if migrateLegacyConnectionSecretsIfNeeded() {
            shouldPersistAfterLoad = true
        }
        if normalizeConnectionStatuses() {
            shouldPersistAfterLoad = true
        }

        if shouldPersistAfterLoad {
            persist()
        }
    }

}
