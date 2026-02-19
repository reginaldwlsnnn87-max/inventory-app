import Foundation

struct InventoryAnalyticsService {
    func ownerImpactReport(
        auditEvents: [PlatformAuditEvent],
        allItems: [InventoryItemEntity],
        workspaceID: UUID?,
        windowDays: Int,
        now: Date = Date()
    ) -> OwnerImpactReport {
        let workspaceKey = workspaceKey(for: workspaceID)
        let normalizedWindowDays = max(1, windowDays)
        let cutoff = Calendar.current.date(byAdding: .day, value: -normalizedWindowDays, to: now) ?? Date.distantPast
        let scopedEvents = auditEvents.filter {
            $0.workspaceKey == workspaceKey && $0.createdAt >= cutoff
        }

        var unitsReceived: Int64 = 0
        var unitsReturned: Int64 = 0
        var netAdjustments: Int64 = 0
        var savedSeconds = 0
        var shrinkPrevented: Int64 = 0

        for event in scopedEvents {
            savedSeconds += event.estimatedSecondsSaved
            shrinkPrevented += max(0, event.shrinkImpactUnits)
            switch event.type {
            case .receive:
                unitsReceived += max(0, event.deltaUnits)
            case .return:
                unitsReturned += abs(event.deltaUnits)
            case .adjustment:
                netAdjustments += event.deltaUnits
            case .countSession,
                 .shiftRun,
                 .csvImport,
                 .csvExport,
                 .sync,
                 .backupCreated,
                 .backupRestored,
                 .integrationConnected,
                 .integrationDisconnected,
                 .webhookIngested,
                 .webhookApplied,
                 .conflictResolved:
                break
            }
        }

        let scopedItems = scopeItems(allItems, workspaceID: workspaceID)
        let riskItems = scopedItems.filter { item in
            let forecast = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let lead = max(0, Double(item.leadTimeDays))
            let onHand = Double(max(0, Int64(item.totalUnitsOnHand)))
            guard forecast > 0, lead > 0 else { return false }
            let daysOfCover = onHand / forecast
            return onHand == 0 || daysOfCover <= max(1, lead)
        }

        let riskRate = scopedItems.isEmpty
            ? 0
            : Double(riskItems.count) / Double(scopedItems.count)

        return OwnerImpactReport(
            windowDays: normalizedWindowDays,
            totalEvents: scopedEvents.count,
            unitsReceived: unitsReceived,
            unitsReturned: unitsReturned,
            netAdjustments: netAdjustments,
            estimatedMinutesSaved: savedSeconds / 60,
            shrinkPreventedUnits: shrinkPrevented,
            shrinkRiskRate: riskRate
        )
    }

    func countSessions(
        history: [CountSessionRecord],
        workspaceID: UUID?,
        windowDays: Int,
        limit: Int,
        now: Date = Date()
    ) -> [CountSessionRecord] {
        let normalizedWindowDays = max(1, windowDays)
        let workspaceKey = workspaceKey(for: workspaceID)
        let cutoff = Calendar.current.date(byAdding: .day, value: -normalizedWindowDays, to: now) ?? Date.distantPast
        return history
            .filter { $0.workspaceKey == workspaceKey && $0.finishedAt >= cutoff }
            .sorted(by: { $0.finishedAt > $1.finishedAt })
            .prefix(max(0, limit))
            .map { $0 }
    }

    func countProductivitySummary(
        history: [CountSessionRecord],
        workspaceID: UUID?,
        windowDays: Int,
        now: Date = Date()
    ) -> CountProductivitySummary {
        let normalizedWindowDays = max(1, windowDays)
        let sessions = countSessions(
            history: history,
            workspaceID: workspaceID,
            windowDays: normalizedWindowDays,
            limit: 800,
            now: now
        )
        guard !sessions.isEmpty else {
            return CountProductivitySummary(
                windowDays: normalizedWindowDays,
                sessionCount: 0,
                totalItemsCounted: 0,
                highVarianceItems: 0,
                averageItemsPerMinute: 0,
                bestItemsPerMinute: 0,
                averageDurationMinutes: 0,
                blindModeRate: 0,
                targetTrackedSessions: 0,
                targetHitRate: 0,
                latestSessionFinishedAt: nil
            )
        }

        let totalItems = sessions.reduce(0) { $0 + $1.itemCount }
        let highVariance = sessions.reduce(0) { $0 + $1.highVarianceCount }
        let totalSpeed = sessions.reduce(0.0) { $0 + $1.itemsPerMinute }
        let totalDurationMinutes = sessions.reduce(0.0) { $0 + $1.durationMinutes }
        let blindModeCount = sessions.filter(\.blindModeEnabled).count
        let targetedSessions = sessions.filter { ($0.targetDurationMinutes ?? 0) > 0 }
        let targetHitCount = targetedSessions.filter { $0.metTarget == true }.count
        let targetHitRate = targetedSessions.isEmpty
            ? 0
            : Double(targetHitCount) / Double(targetedSessions.count)

        return CountProductivitySummary(
            windowDays: normalizedWindowDays,
            sessionCount: sessions.count,
            totalItemsCounted: totalItems,
            highVarianceItems: highVariance,
            averageItemsPerMinute: totalSpeed / Double(sessions.count),
            bestItemsPerMinute: sessions.map(\.itemsPerMinute).max() ?? 0,
            averageDurationMinutes: totalDurationMinutes / Double(sessions.count),
            blindModeRate: Double(blindModeCount) / Double(sessions.count),
            targetTrackedSessions: targetedSessions.count,
            targetHitRate: targetHitRate,
            latestSessionFinishedAt: sessions.first?.finishedAt
        )
    }

    func valueTrackingSnapshot(
        workspaceID: UUID?,
        window: ValueTrackingWindow,
        referenceDate: Date,
        auditEvents: [PlatformAuditEvent],
        countSessionHistory: [CountSessionRecord]
    ) -> ValueTrackingSnapshot {
        let workspaceKey = workspaceKey(for: workspaceID)
        let range = valueTrackingRange(for: window, referenceDate: referenceDate)

        let scopedAuditEvents = auditEvents.filter { event in
            event.workspaceKey == workspaceKey
                && event.createdAt >= range.start
                && event.createdAt <= range.end
        }
        let scopedCountSessions = countSessionHistory.filter { session in
            session.workspaceKey == workspaceKey
                && session.finishedAt >= range.start
                && session.finishedAt <= range.end
        }

        let sessionSavedSeconds = scopedCountSessions.reduce(0) { partial, session in
            let baselineSecondsPerItem = session.blindModeEnabled ? 44.0 : 36.0
            let actualSecondsPerItem = session.durationSeconds / Double(max(1, session.itemCount))
            let saved = max(0, Int((baselineSecondsPerItem - actualSecondsPerItem) * Double(max(1, session.itemCount))))
            return partial + saved
        }
        let nonCountAuditEvents = scopedAuditEvents.filter { $0.type != .countSession }
        let nonCountSavedSeconds = nonCountAuditEvents.reduce(0) { partial, event in
            partial + max(0, event.estimatedSecondsSaved)
        }
        let countsCompleted = scopedCountSessions.reduce(0) { partial, session in
            partial + max(0, session.itemCount)
        }
        let sessionShrinkResolved = scopedCountSessions.reduce(Int64(0)) { partial, session in
            partial + Int64(max(0, session.highVarianceCount))
        }
        let nonCountShrinkResolved = nonCountAuditEvents.reduce(Int64(0)) { partial, event in
            partial + max(0, event.shrinkImpactUnits)
        }

        return ValueTrackingSnapshot(
            window: window,
            startsAt: range.start,
            endsAt: range.end,
            minutesSaved: (sessionSavedSeconds + nonCountSavedSeconds) / 60,
            countsCompleted: countsCompleted,
            shrinkRiskResolved: sessionShrinkResolved + nonCountShrinkResolved,
            countSessionRuns: scopedCountSessions.count
        )
    }

    func pilotDailyMetrics(
        workspaceID: UUID?,
        day: Date,
        countSessionHistory: [CountSessionRecord],
        inventoryEvents: [InventoryLedgerEvent],
        pilotExceptionEvents: [PilotExceptionResolutionEvent]
    ) -> PilotDailyMetrics {
        let workspaceKey = workspaceKey(for: workspaceID)
        let range = dayRange(for: day)

        let sessions = countSessionHistory.filter { session in
            session.workspaceKey == workspaceKey
                && session.finishedAt >= range.start
                && session.finishedAt < range.endExclusive
        }

        let adjustments = inventoryEvents.filter { event in
            event.workspaceKey == workspaceKey
                && event.type == .adjustment
                && event.createdAt >= range.start
                && event.createdAt < range.endExclusive
        }

        let resolvedExceptions = pilotExceptionEvents.filter { event in
            event.workspaceKey == workspaceKey
                && event.createdAt >= range.start
                && event.createdAt < range.endExclusive
        }

        return PilotDailyMetrics(
            dayStart: range.start,
            dayEnd: range.endExclusive,
            firstCountStartedAt: sessions.map(\.startedAt).min(),
            lastCountFinishedAt: sessions.map(\.finishedAt).max(),
            countSessionRuns: sessions.count,
            itemsCounted: sessions.reduce(0) { $0 + max(0, $1.itemCount) },
            exceptionsResolved: resolvedExceptions.reduce(0) { $0 + max(0, $1.resolvedCount) },
            adjustmentCount: adjustments.count,
            netAdjustmentUnits: adjustments.reduce(Int64(0)) { $0 + $1.deltaUnits }
        )
    }

    private func workspaceKey(for workspaceID: UUID?) -> String {
        workspaceID?.uuidString ?? "all"
    }

    private func scopeItems(_ items: [InventoryItemEntity], workspaceID: UUID?) -> [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(workspaceID) }
    }

    private func valueTrackingRange(
        for window: ValueTrackingWindow,
        referenceDate: Date
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        switch window {
        case .shift:
            return (
                start: referenceDate.addingTimeInterval(-8 * 60 * 60),
                end: referenceDate
            )
        case .week:
            let startOfToday = calendar.startOfDay(for: referenceDate)
            let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            return (start: start, end: referenceDate)
        }
    }

    private func dayRange(for referenceDate: Date) -> (start: Date, endExclusive: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        return (start: start, endExclusive: end)
    }
}
