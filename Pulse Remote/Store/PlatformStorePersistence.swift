import Foundation

struct PlatformStorePersistenceKeys {
    let syncJobsKey: String
    let syncRetryJobsKey: String
    let auditEventsKey: String
    let inventoryEventsKey: String
    let countSessionsKey: String
    let pilotExceptionEventsKey: String
    let backupsKey: String
    let connectionsKey: String
    let webhookEventsKey: String
    let conflictsKey: String
}

struct PlatformStorePersistenceState {
    let syncJobs: [IntegrationSyncJob]
    let syncRetryJobs: [IntegrationSyncRetryJob]
    let auditEvents: [PlatformAuditEvent]
    let inventoryEvents: [InventoryLedgerEvent]
    let countSessionHistory: [CountSessionRecord]
    let pilotExceptionEvents: [PilotExceptionResolutionEvent]
    let backups: [InventoryBackupSnapshot]
    let connections: [IntegrationConnection]
    let webhookEvents: [IntegrationWebhookEvent]
    let conflicts: [IntegrationConflict]
}

enum PlatformStorePersistenceCodec {
    static func persist(
        defaults: UserDefaults,
        keys: PlatformStorePersistenceKeys,
        state: PlatformStorePersistenceState
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        if let jobsData = try? encoder.encode(state.syncJobs) {
            defaults.set(jobsData, forKey: keys.syncJobsKey)
        }
        if let retryData = try? encoder.encode(state.syncRetryJobs) {
            defaults.set(retryData, forKey: keys.syncRetryJobsKey)
        }
        if let auditsData = try? encoder.encode(state.auditEvents) {
            defaults.set(auditsData, forKey: keys.auditEventsKey)
        }
        if let inventoryEventsData = try? encoder.encode(state.inventoryEvents) {
            defaults.set(inventoryEventsData, forKey: keys.inventoryEventsKey)
        }
        if let countSessionsData = try? encoder.encode(state.countSessionHistory) {
            defaults.set(countSessionsData, forKey: keys.countSessionsKey)
        }
        if let pilotExceptionData = try? encoder.encode(state.pilotExceptionEvents) {
            defaults.set(pilotExceptionData, forKey: keys.pilotExceptionEventsKey)
        }
        if let backupData = try? encoder.encode(state.backups) {
            defaults.set(backupData, forKey: keys.backupsKey)
        }
        if let connectionData = try? encoder.encode(state.connections) {
            defaults.set(connectionData, forKey: keys.connectionsKey)
        }
        if let webhookData = try? encoder.encode(state.webhookEvents) {
            defaults.set(webhookData, forKey: keys.webhookEventsKey)
        }
        if let conflictData = try? encoder.encode(state.conflicts) {
            defaults.set(conflictData, forKey: keys.conflictsKey)
        }
    }

    static func load(
        defaults: UserDefaults,
        keys: PlatformStorePersistenceKeys
    ) -> PlatformStorePersistenceState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        func decodeArray<T: Decodable>(_ key: String, as type: T.Type) -> T? {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }

        let syncJobs = (decodeArray(keys.syncJobsKey, as: [IntegrationSyncJob].self) ?? [])
            .sorted(by: { $0.finishedAt > $1.finishedAt })
        let syncRetryJobs = (decodeArray(keys.syncRetryJobsKey, as: [IntegrationSyncRetryJob].self) ?? [])
            .sorted(by: { $0.updatedAt > $1.updatedAt })
        let auditEvents = (decodeArray(keys.auditEventsKey, as: [PlatformAuditEvent].self) ?? [])
            .sorted(by: { $0.createdAt > $1.createdAt })
        let inventoryEvents = (decodeArray(keys.inventoryEventsKey, as: [InventoryLedgerEvent].self) ?? [])
            .sorted(by: { $0.createdAt > $1.createdAt })
        let countSessionHistory = (decodeArray(keys.countSessionsKey, as: [CountSessionRecord].self) ?? [])
            .sorted(by: { $0.finishedAt > $1.finishedAt })
        let pilotExceptionEvents = (decodeArray(keys.pilotExceptionEventsKey, as: [PilotExceptionResolutionEvent].self) ?? [])
            .sorted(by: { $0.createdAt > $1.createdAt })
        let backups = (decodeArray(keys.backupsKey, as: [InventoryBackupSnapshot].self) ?? [])
            .sorted(by: { $0.createdAt > $1.createdAt })
        let connections = (decodeArray(keys.connectionsKey, as: [IntegrationConnection].self) ?? [])
            .sorted(by: { $0.connectedAt > $1.connectedAt })
        let webhookEvents = (decodeArray(keys.webhookEventsKey, as: [IntegrationWebhookEvent].self) ?? [])
            .sorted(by: { $0.receivedAt > $1.receivedAt })
        let conflicts = (decodeArray(keys.conflictsKey, as: [IntegrationConflict].self) ?? [])
            .sorted(by: { $0.createdAt > $1.createdAt })

        return PlatformStorePersistenceState(
            syncJobs: syncJobs,
            syncRetryJobs: syncRetryJobs,
            auditEvents: auditEvents,
            inventoryEvents: inventoryEvents,
            countSessionHistory: countSessionHistory,
            pilotExceptionEvents: pilotExceptionEvents,
            backups: backups,
            connections: connections,
            webhookEvents: webhookEvents,
            conflicts: conflicts
        )
    }
}
