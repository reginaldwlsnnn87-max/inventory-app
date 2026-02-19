import Foundation
import CoreData
import Combine
import Security

enum IntegrationProvider: String, Codable, CaseIterable, Identifiable {
    case quickBooks
    case shopify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickBooks:
            return "QuickBooks"
        case .shopify:
            return "Shopify"
        }
    }

    var systemImage: String {
        switch self {
        case .quickBooks:
            return "building.columns"
        case .shopify:
            return "bag"
        }
    }
}

enum IntegrationSyncStatus: String, Codable {
    case success
    case failed
}

struct IntegrationSyncJob: Identifiable, Codable, Hashable {
    let id: UUID
    let provider: IntegrationProvider
    let workspaceKey: String
    let startedAt: Date
    let finishedAt: Date
    let pulledRecords: Int
    let pushedRecords: Int
    let status: IntegrationSyncStatus
    let message: String
}

enum IntegrationSyncRetryStatus: String, Codable {
    case queued
    case resolved
    case abandoned

    var title: String {
        switch self {
        case .queued:
            return "Queued"
        case .resolved:
            return "Resolved"
        case .abandoned:
            return "Abandoned"
        }
    }
}

struct IntegrationSyncRetryJob: Identifiable, Codable, Hashable {
    let id: UUID
    let provider: IntegrationProvider
    let workspaceKey: String
    let createdAt: Date
    var updatedAt: Date
    var attemptCount: Int
    var maxAttempts: Int
    var nextAttemptAt: Date
    var status: IntegrationSyncRetryStatus
    var lastError: String
}

enum IntegrationConnectionStatus: String, Codable {
    case disconnected
    case connected
    case tokenExpired

    var title: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connected:
            return "Connected"
        case .tokenExpired:
            return "Token Expired"
        }
    }
}

struct IntegrationConnection: Identifiable, Codable, Hashable {
    let id: UUID
    let provider: IntegrationProvider
    let workspaceKey: String
    var accountLabel: String
    var accessToken: String
    var refreshToken: String
    var webhookSecret: String
    var connectedAt: Date
    var lastSyncAt: Date?
    var tokenExpiresAt: Date?
    var lastRefreshedAt: Date?
    var status: IntegrationConnectionStatus
}

struct IntegrationSecretState {
    let status: IntegrationConnectionStatus
    let hasAccessToken: Bool
    let hasRefreshToken: Bool
    let hasWebhookSecret: Bool
    let tokenExpiresAt: Date?
    let lastRefreshedAt: Date?
}

enum IntegrationWebhookStatus: String, Codable {
    case pending
    case applied
    case ignored
    case failed

    var title: String {
        switch self {
        case .pending:
            return "Pending"
        case .applied:
            return "Applied"
        case .ignored:
            return "Ignored"
        case .failed:
            return "Failed"
        }
    }
}

struct IntegrationWebhookEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let provider: IntegrationProvider
    let workspaceKey: String
    let receivedAt: Date
    let eventType: String
    let externalID: String
    let payloadPreview: String
    var status: IntegrationWebhookStatus
    var note: String
}

enum IntegrationConflictType: String, Codable {
    case quantityMismatch
    case metadataMismatch
    case missingLocalItem
    case missingRemoteItem

    var title: String {
        switch self {
        case .quantityMismatch:
            return "Quantity Mismatch"
        case .metadataMismatch:
            return "Metadata Mismatch"
        case .missingLocalItem:
            return "Missing Local Item"
        case .missingRemoteItem:
            return "Missing Remote Item"
        }
    }
}

enum IntegrationConflictStatus: String, Codable {
    case unresolved
    case keepLocal
    case acceptRemote
}

enum IntegrationConflictResolution {
    case keepLocal
    case acceptRemote
}

struct IntegrationConflict: Identifiable, Codable, Hashable {
    let id: UUID
    let provider: IntegrationProvider
    let workspaceKey: String
    let createdAt: Date
    let type: IntegrationConflictType
    let localItemID: UUID?
    let localItemName: String
    let remoteItemName: String
    let localUnits: Int64
    let remoteUnits: Int64
    var status: IntegrationConflictStatus
    var resolvedAt: Date?
}

enum PlatformAuditType: String, Codable, CaseIterable {
    case receive
    case `return`
    case adjustment
    case countSession
    case shiftRun
    case csvImport
    case csvExport
    case sync
    case backupCreated
    case backupRestored
    case integrationConnected
    case integrationDisconnected
    case webhookIngested
    case webhookApplied
    case conflictResolved

    var title: String {
        switch self {
        case .receive:
            return "Receive"
        case .return:
            return "Return"
        case .adjustment:
            return "Adjustment"
        case .countSession:
            return "Count Session"
        case .shiftRun:
            return "Shift Run"
        case .csvImport:
            return "CSV Import"
        case .csvExport:
            return "CSV Export"
        case .sync:
            return "Sync"
        case .backupCreated:
            return "Backup"
        case .backupRestored:
            return "Restore"
        case .integrationConnected:
            return "Connected"
        case .integrationDisconnected:
            return "Disconnected"
        case .webhookIngested:
            return "Webhook Ingested"
        case .webhookApplied:
            return "Webhook Applied"
        case .conflictResolved:
            return "Conflict Resolved"
        }
    }

    var systemImage: String {
        switch self {
        case .receive:
            return "tray.and.arrow.down"
        case .return:
            return "arrow.uturn.backward"
        case .adjustment:
            return "slider.horizontal.3"
        case .countSession:
            return "checklist"
        case .shiftRun:
            return "play.circle.fill"
        case .csvImport:
            return "square.and.arrow.down"
        case .csvExport:
            return "square.and.arrow.up"
        case .sync:
            return "arrow.triangle.2.circlepath"
        case .backupCreated:
            return "externaldrive.badge.plus"
        case .backupRestored:
            return "clock.arrow.circlepath"
        case .integrationConnected:
            return "checkmark.shield"
        case .integrationDisconnected:
            return "xmark.shield"
        case .webhookIngested:
            return "tray.and.arrow.down"
        case .webhookApplied:
            return "checkmark.circle"
        case .conflictResolved:
            return "arrow.left.arrow.right.circle"
        }
    }
}

struct PlatformAuditEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let workspaceKey: String
    let actorName: String
    let type: PlatformAuditType
    let createdAt: Date
    let summary: String
    let deltaUnits: Int64
    let estimatedSecondsSaved: Int
    let shrinkImpactUnits: Int64
}

enum InventoryEventType: String, Codable, CaseIterable {
    case receipt
    case adjustment
    case `return`
    case countCorrection

    var title: String {
        switch self {
        case .receipt:
            return "Receipt"
        case .adjustment:
            return "Adjustment"
        case .return:
            return "Return"
        case .countCorrection:
            return "Count Correction"
        }
    }

    var systemImage: String {
        switch self {
        case .receipt:
            return "tray.and.arrow.down.fill"
        case .adjustment:
            return "slider.horizontal.3"
        case .return:
            return "arrow.uturn.backward"
        case .countCorrection:
            return "checkmark.seal"
        }
    }
}

enum InventoryEventSyncStatus: String, Codable {
    case pending
    case synced
    case failed
}

struct InventoryLedgerEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let workspaceKey: String
    let actorName: String
    let createdAt: Date
    let type: InventoryEventType
    let source: String
    let reason: String
    let itemID: UUID?
    let itemName: String
    let itemCategory: String
    let itemLocation: String
    let deltaUnits: Int64
    let resultingUnits: Int64?
    let correlationID: String
    var syncStatus: InventoryEventSyncStatus
    var syncAttemptCount: Int
    var lastSyncAt: Date?
    var lastSyncError: String?
}

enum InventoryConfidenceTier: String, CaseIterable {
    case strong
    case watch
    case weak
    case critical

    var title: String {
        switch self {
        case .strong:
            return "Strong"
        case .watch:
            return "Watch"
        case .weak:
            return "Weak"
        case .critical:
            return "Critical"
        }
    }
}

struct InventoryConfidenceSignal: Identifiable, Hashable {
    let id: UUID
    let itemName: String
    let score: Int
    let tier: InventoryConfidenceTier
    let reasons: [String]
    let recommendation: String
    let lastTouchedAt: Date
    let correctionsLast30Days: Int
    let failedSyncEventsLast30Days: Int
}

struct InventoryConfidenceOverview: Hashable {
    let itemCount: Int
    let averageScore: Int
    let strongCount: Int
    let watchCount: Int
    let weakCount: Int
    let criticalCount: Int
    let weakestItems: [InventoryConfidenceSignal]
}

enum InventoryReconnectAction: String {
    case openIntegrationHub
    case refreshTokens
    case runLedgerSync
    case exportLedger
}

struct InventoryReconnectStep: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let action: InventoryReconnectAction
    let priority: Int
}

struct InventoryReconnectSourceLoad: Identifiable, Hashable {
    let id: String
    let source: String
    let count: Int
}

struct InventoryReconnectBrief: Hashable {
    let pendingCount: Int
    let failedCount: Int
    let unsyncedCount: Int
    let unsyncedUnits: Int64
    let oldestPendingAt: Date?
    let oldestFailedAt: Date?
    let sourceLoad: [InventoryReconnectSourceLoad]
    let connectionIssues: [String]
    let steps: [InventoryReconnectStep]
}

struct InventoryLedgerSyncRun: Hashable {
    let attempted: Int
    let synced: Int
    let failed: Int
    let provider: IntegrationProvider?
    let blockedByConnection: Bool
    let message: String
}

struct InventoryBackupItem: Codable, Hashable {
    let id: UUID
    let name: String
    let quantity: Int64
    let notes: String
    let category: String
    let location: String
    let unitsPerCase: Int64
    let looseUnits: Int64
    let eachesPerUnit: Int64
    let looseEaches: Int64
    let isLiquid: Bool
    let gallonFraction: Double
    let isPinned: Bool
    let barcode: String
    let averageDailyUsage: Double
    let leadTimeDays: Int64
    let safetyStockUnits: Int64
    let preferredSupplier: String
    let supplierSKU: String
    let minimumOrderQuantity: Int64
    let reorderCasePack: Int64
    let leadTimeVarianceDays: Int64
    let workspaceID: String
    let recentDemandSamples: String
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case quantity
        case notes
        case category
        case location
        case unitsPerCase
        case looseUnits
        case eachesPerUnit
        case looseEaches
        case isLiquid
        case gallonFraction
        case isPinned
        case barcode
        case averageDailyUsage
        case leadTimeDays
        case safetyStockUnits
        case preferredSupplier
        case supplierSKU
        case minimumOrderQuantity
        case reorderCasePack
        case leadTimeVarianceDays
        case workspaceID
        case recentDemandSamples
        case createdAt
        case updatedAt
    }

    init(item: InventoryItemEntity) {
        id = item.id
        name = item.name
        quantity = item.quantity
        notes = item.notes
        category = item.category
        location = item.location
        unitsPerCase = item.unitsPerCase
        looseUnits = item.looseUnits
        eachesPerUnit = item.eachesPerUnit
        looseEaches = item.looseEaches
        isLiquid = item.isLiquid
        gallonFraction = item.gallonFraction
        isPinned = item.isPinned
        barcode = item.barcode
        averageDailyUsage = item.averageDailyUsage
        leadTimeDays = item.leadTimeDays
        safetyStockUnits = item.safetyStockUnits
        preferredSupplier = item.preferredSupplier
        supplierSKU = item.supplierSKU
        minimumOrderQuantity = item.minimumOrderQuantity
        reorderCasePack = item.reorderCasePack
        leadTimeVarianceDays = item.leadTimeVarianceDays
        workspaceID = item.workspaceID
        recentDemandSamples = item.recentDemandSamples
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        quantity = try container.decode(Int64.self, forKey: .quantity)
        notes = try container.decode(String.self, forKey: .notes)
        category = try container.decode(String.self, forKey: .category)
        location = try container.decode(String.self, forKey: .location)
        unitsPerCase = try container.decode(Int64.self, forKey: .unitsPerCase)
        looseUnits = try container.decode(Int64.self, forKey: .looseUnits)
        eachesPerUnit = try container.decode(Int64.self, forKey: .eachesPerUnit)
        looseEaches = try container.decode(Int64.self, forKey: .looseEaches)
        isLiquid = try container.decode(Bool.self, forKey: .isLiquid)
        gallonFraction = try container.decode(Double.self, forKey: .gallonFraction)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        barcode = try container.decode(String.self, forKey: .barcode)
        averageDailyUsage = try container.decode(Double.self, forKey: .averageDailyUsage)
        leadTimeDays = try container.decode(Int64.self, forKey: .leadTimeDays)
        safetyStockUnits = try container.decode(Int64.self, forKey: .safetyStockUnits)
        preferredSupplier = try container.decodeIfPresent(String.self, forKey: .preferredSupplier) ?? ""
        supplierSKU = try container.decodeIfPresent(String.self, forKey: .supplierSKU) ?? ""
        minimumOrderQuantity = try container.decodeIfPresent(Int64.self, forKey: .minimumOrderQuantity) ?? 0
        reorderCasePack = try container.decodeIfPresent(Int64.self, forKey: .reorderCasePack) ?? 0
        leadTimeVarianceDays = try container.decodeIfPresent(Int64.self, forKey: .leadTimeVarianceDays) ?? 0
        workspaceID = try container.decode(String.self, forKey: .workspaceID)
        recentDemandSamples = try container.decode(String.self, forKey: .recentDemandSamples)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct InventoryBackupSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    let workspaceKey: String
    let title: String
    let createdAt: Date
    let itemCount: Int
    let items: [InventoryBackupItem]
}

struct CSVImportSummary {
    let createdCount: Int
    let updatedCount: Int
    let skippedCount: Int

    var description: String {
        "Import complete: \(createdCount) created, \(updatedCount) updated, \(skippedCount) skipped."
    }
}

struct OwnerImpactReport {
    let windowDays: Int
    let totalEvents: Int
    let unitsReceived: Int64
    let unitsReturned: Int64
    let netAdjustments: Int64
    let estimatedMinutesSaved: Int
    let shrinkPreventedUnits: Int64
    let shrinkRiskRate: Double
}

enum CountSessionType: String, Codable, CaseIterable {
    case stockCount
    case zoneMission

    var title: String {
        switch self {
        case .stockCount:
            return "Stock Count"
        case .zoneMission:
            return "Zone Mission"
        }
    }
}

struct CountSessionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let workspaceKey: String
    let type: CountSessionType
    let startedAt: Date
    let finishedAt: Date
    let itemCount: Int
    let highVarianceCount: Int
    let blindModeEnabled: Bool
    let targetDurationMinutes: Int?
    let zoneTitle: String?
    let note: String?

    var durationSeconds: TimeInterval {
        max(1, finishedAt.timeIntervalSince(startedAt))
    }

    var durationMinutes: Double {
        durationSeconds / 60
    }

    var itemsPerMinute: Double {
        guard durationMinutes > 0 else { return 0 }
        return Double(itemCount) / durationMinutes
    }

    var metTarget: Bool? {
        guard let targetDurationMinutes, targetDurationMinutes > 0 else { return nil }
        return durationMinutes <= Double(targetDurationMinutes)
    }
}

struct CountProductivitySummary: Hashable {
    let windowDays: Int
    let sessionCount: Int
    let totalItemsCounted: Int
    let highVarianceItems: Int
    let averageItemsPerMinute: Double
    let bestItemsPerMinute: Double
    let averageDurationMinutes: Double
    let blindModeRate: Double
    let targetTrackedSessions: Int
    let targetHitRate: Double
    let latestSessionFinishedAt: Date?
}

enum ValueTrackingWindow: String, CaseIterable, Identifiable {
    case shift
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shift:
            return "This Shift"
        case .week:
            return "Last 7 Days"
        }
    }
}

struct ValueTrackingSnapshot: Hashable {
    let window: ValueTrackingWindow
    let startsAt: Date
    let endsAt: Date
    let minutesSaved: Int
    let countsCompleted: Int
    let shrinkRiskResolved: Int64
    let countSessionRuns: Int
}

enum InventoryAdjustmentReasonCode: String, CaseIterable, Codable, Identifiable {
    case countCorrection = "Count Correction"
    case receivingMismatch = "Receiving Mismatch"
    case transferMismatch = "Transfer Mismatch"
    case spoilageWaste = "Spoilage / Waste"
    case theftLoss = "Theft / Loss"
    case damagedProduct = "Damaged Product"
    case other = "Other"

    var id: String { rawValue }
}

struct PilotExceptionResolutionEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let workspaceKey: String
    let createdAt: Date
    let resolvedCount: Int
    let source: String
}

struct PilotDailyMetrics: Hashable {
    let dayStart: Date
    let dayEnd: Date
    let firstCountStartedAt: Date?
    let lastCountFinishedAt: Date?
    let countSessionRuns: Int
    let itemsCounted: Int
    let exceptionsResolved: Int
    let adjustmentCount: Int
    let netAdjustmentUnits: Int64
}

struct BackupRestoreHealthCheckResult: Hashable {
    let checkedAt: Date
    let snapshotTitle: String
    let expectedItemCount: Int
    let snapshotItemCount: Int
    let snapshotFound: Bool
    let payloadRoundTripValid: Bool

    var passed: Bool {
        snapshotFound
            && payloadRoundTripValid
            && expectedItemCount == snapshotItemCount
    }
}

