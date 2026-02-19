import Foundation

enum PlatformStoreInsights {
    static func inventoryReconnectBrief(
        workspaceEvents: [InventoryLedgerEvent],
        providerStates: [IntegrationProvider: IntegrationSecretState]
    ) -> InventoryReconnectBrief {
        let unsyncedEvents = workspaceEvents.filter { $0.syncStatus != .synced }
        let pendingEvents = unsyncedEvents.filter { $0.syncStatus == .pending }
        let failedEvents = unsyncedEvents.filter { $0.syncStatus == .failed }
        let unsyncedUnits = unsyncedEvents.reduce(Int64(0)) { partial, event in
            partial + abs(event.deltaUnits)
        }

        let sourceGroups = Dictionary(grouping: unsyncedEvents) { event -> String in
            let trimmed = event.source.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "manual" : trimmed
        }
        let sourceLoad = sourceGroups
            .map { source, events in
                InventoryReconnectSourceLoad(
                    id: source,
                    source: source,
                    count: events.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending
            }
            .prefix(5)
            .map { $0 }

        var connectionIssues: [String] = []
        var tokenExpiredCount = 0
        var connectedCount = 0
        if !unsyncedEvents.isEmpty {
            for provider in IntegrationProvider.allCases {
                let state = providerStates[provider] ?? IntegrationSecretState(
                    status: .disconnected,
                    hasAccessToken: false,
                    hasRefreshToken: false,
                    hasWebhookSecret: false,
                    tokenExpiresAt: nil,
                    lastRefreshedAt: nil
                )
                switch state.status {
                case .connected:
                    connectedCount += 1
                case .tokenExpired:
                    tokenExpiredCount += 1
                    connectionIssues.append("\(provider.title) token expired.")
                case .disconnected:
                    connectionIssues.append("\(provider.title) not connected.")
                }
            }
        }

        var steps: [InventoryReconnectStep] = []
        if failedEvents.count > 0 && tokenExpiredCount > 0 {
            steps.append(
                InventoryReconnectStep(
                    id: "refresh-token",
                    title: "Refresh provider tokens",
                    detail: "One or more integrations expired. Refresh credentials in Integration Hub, then rerun ledger sync.",
                    action: .refreshTokens,
                    priority: 1
                )
            )
        }
        if unsyncedEvents.count > 0 && connectedCount == 0 {
            steps.append(
                InventoryReconnectStep(
                    id: "connect-provider",
                    title: "Connect at least one provider",
                    detail: "No live integration is connected for this workspace. Add QuickBooks or Shopify before syncing pending inventory events.",
                    action: .openIntegrationHub,
                    priority: 0
                )
            )
        }
        if unsyncedEvents.count > 0 {
            steps.append(
                InventoryReconnectStep(
                    id: "run-ledger-sync",
                    title: "Run offline ledger sync",
                    detail: "\(unsyncedEvents.count) event(s) are waiting. Run a sync pass to clear pending/failure backlog.",
                    action: .runLedgerSync,
                    priority: connectedCount > 0 ? 0 : 2
                )
            )
        }
        if failedEvents.count > 0 {
            steps.append(
                InventoryReconnectStep(
                    id: "export-ledger-failures",
                    title: "Export failed event trail",
                    detail: "Share the ledger CSV with owners before close so failed events are auditable during cleanup.",
                    action: .exportLedger,
                    priority: 2
                )
            )
        }

        let sortedSteps = steps.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return InventoryReconnectBrief(
            pendingCount: pendingEvents.count,
            failedCount: failedEvents.count,
            unsyncedCount: unsyncedEvents.count,
            unsyncedUnits: unsyncedUnits,
            oldestPendingAt: pendingEvents.map(\.createdAt).min(),
            oldestFailedAt: failedEvents.map(\.createdAt).min(),
            sourceLoad: sourceLoad,
            connectionIssues: connectionIssues,
            steps: sortedSteps
        )
    }

    static func inventoryConfidenceSignals(
        scopedItems: [InventoryItemEntity],
        workspaceEvents: [InventoryLedgerEvent],
        limit: Int = 20
    ) -> [InventoryConfidenceSignal] {
        guard !scopedItems.isEmpty else { return [] }

        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
        let groupedEvents = Dictionary(grouping: workspaceEvents.filter { event in
            event.createdAt >= cutoff
                && event.itemID != nil
        }) { event in
            event.itemID!
        }

        var output: [InventoryConfidenceSignal] = []
        output.reserveCapacity(scopedItems.count)

        for item in scopedItems {
            let itemEvents = groupedEvents[item.id] ?? []
            let correctionCount = itemEvents.filter { $0.type == .countCorrection }.count
            let failedSyncCount = itemEvents.filter { $0.syncStatus == .failed }.count
            let returnCount = itemEvents.filter { $0.type == .return }.count

            var score = 100
            var reasons: [String] = []
            var recommendation = "Maintain current count rhythm."

            if item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                score -= 12
                reasons.append("Missing shelf location.")
                recommendation = "Assign a location to reduce count time and misplaced stock."
            }

            if item.barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                score -= 8
                reasons.append("Missing barcode.")
                if recommendation == "Maintain current count rhythm." {
                    recommendation = "Add barcode so scanning replaces manual lookups."
                }
            }

            let demand = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            if demand <= 0 || item.leadTimeDays <= 0 {
                score -= 18
                reasons.append("Missing demand or lead-time input.")
                recommendation = "Set daily usage and lead time to improve reorder and count confidence."
            }

            let stalenessDays = Calendar.current.dateComponents([.day], from: item.updatedAt, to: Date()).day ?? 0
            if stalenessDays >= 14 {
                score -= 22
                reasons.append("Count is stale (\(stalenessDays) days).")
                recommendation = "Run a cycle count for this SKU this shift."
            } else if stalenessDays >= 7 {
                score -= 12
                reasons.append("Count is aging (\(stalenessDays) days).")
                if recommendation == "Maintain current count rhythm." {
                    recommendation = "Recount this SKU before close to keep on-hand reliable."
                }
            }

            if correctionCount >= 3 {
                score -= min(24, correctionCount * 6)
                reasons.append("Frequent count corrections (\(correctionCount)).")
                recommendation = "Investigate receiving/count process drift and tighten SOP."
            }

            if failedSyncCount > 0 {
                score -= min(20, failedSyncCount * 5)
                reasons.append("Ledger sync failures (\(failedSyncCount)).")
                recommendation = "Reconnect integrations and clear failed ledger events."
            }

            if returnCount >= 2 {
                score -= min(12, returnCount * 3)
                reasons.append("High return activity (\(returnCount)).")
                if recommendation == "Maintain current count rhythm." {
                    recommendation = "Audit return reasons for this SKU and adjust handling rules."
                }
            }

            if reasons.isEmpty {
                score = min(100, score + 3)
            }

            let clampedScore = max(0, min(100, score))
            output.append(
                InventoryConfidenceSignal(
                    id: item.id,
                    itemName: item.name,
                    score: clampedScore,
                    tier: PlatformStoreHelpers.confidenceTier(for: clampedScore),
                    reasons: Array(reasons.prefix(3)),
                    recommendation: recommendation,
                    lastTouchedAt: item.updatedAt,
                    correctionsLast30Days: correctionCount,
                    failedSyncEventsLast30Days: failedSyncCount
                )
            )
        }

        output.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            if lhs.failedSyncEventsLast30Days != rhs.failedSyncEventsLast30Days {
                return lhs.failedSyncEventsLast30Days > rhs.failedSyncEventsLast30Days
            }
            if lhs.correctionsLast30Days != rhs.correctionsLast30Days {
                return lhs.correctionsLast30Days > rhs.correctionsLast30Days
            }
            return lhs.itemName.localizedCaseInsensitiveCompare(rhs.itemName) == .orderedAscending
        }

        return Array(output.prefix(max(0, limit)))
    }
}
