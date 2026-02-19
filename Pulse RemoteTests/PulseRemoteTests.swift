import XCTest
@testable import inventory_app

final class InventoryAppTests: XCTestCase {
    @MainActor
    private static var retainedStores: [PlatformStore] = []

    func testSanity() {
        XCTAssertTrue(true)
    }

    @MainActor
    func testCountProductivitySummaryCalculatesMetrics() {
        let (store, defaults, suiteName) = makePlatformStore()
        defer { cleanPlatformDefaults(defaults, suiteName: suiteName) }

        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000111")
        let now = Date()
        let firstStart = now.addingTimeInterval(-3_600)
        let firstEnd = firstStart.addingTimeInterval(300)
        let secondStart = now.addingTimeInterval(-1_800)
        let secondEnd = secondStart.addingTimeInterval(300)

        store.recordCountSession(
            type: .stockCount,
            workspaceID: workspaceID,
            actorName: "Tester",
            startedAt: firstStart,
            finishedAt: firstEnd,
            itemCount: 25,
            highVarianceCount: 4,
            blindModeEnabled: true,
            targetDurationMinutes: 6
        )
        store.recordCountSession(
            type: .zoneMission,
            workspaceID: workspaceID,
            actorName: "Tester",
            startedAt: secondStart,
            finishedAt: secondEnd,
            itemCount: 30,
            highVarianceCount: 3,
            blindModeEnabled: false,
            targetDurationMinutes: 4
        )

        let summary = store.countProductivitySummary(workspaceID: workspaceID, windowDays: 3650)

        XCTAssertEqual(summary.sessionCount, 2)
        XCTAssertEqual(summary.totalItemsCounted, 55)
        XCTAssertEqual(summary.highVarianceItems, 7)
        XCTAssertEqual(summary.averageDurationMinutes, 5, accuracy: 0.001)
        XCTAssertEqual(summary.averageItemsPerMinute, 5.5, accuracy: 0.001)
        XCTAssertEqual(summary.bestItemsPerMinute, 6, accuracy: 0.001)
        XCTAssertEqual(summary.blindModeRate, 0.5, accuracy: 0.001)
        XCTAssertEqual(summary.targetTrackedSessions, 2)
        XCTAssertEqual(summary.targetHitRate, 0.5, accuracy: 0.001)
        XCTAssertEqual(summary.latestSessionFinishedAt, secondEnd)
    }

    @MainActor
    func testCountProductivitySummaryFiltersOldSessions() {
        let (store, defaults, suiteName) = makePlatformStore()
        defer { cleanPlatformDefaults(defaults, suiteName: suiteName) }

        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000222")
        let now = Date()
        let oldStart = Calendar.current.date(byAdding: .day, value: -40, to: now) ?? now
        let oldEnd = oldStart.addingTimeInterval(600)
        let recentStart = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
        let recentEnd = recentStart.addingTimeInterval(240)

        store.recordCountSession(
            type: .stockCount,
            workspaceID: workspaceID,
            actorName: "Tester",
            startedAt: oldStart,
            finishedAt: oldEnd,
            itemCount: 100,
            highVarianceCount: 12,
            blindModeEnabled: true,
            targetDurationMinutes: 15
        )
        store.recordCountSession(
            type: .zoneMission,
            workspaceID: workspaceID,
            actorName: "Tester",
            startedAt: recentStart,
            finishedAt: recentEnd,
            itemCount: 24,
            highVarianceCount: 2,
            blindModeEnabled: false
        )

        let summary = store.countProductivitySummary(workspaceID: workspaceID, windowDays: 14)
        let recentSessions = store.countSessions(for: workspaceID, windowDays: 14, limit: 10)

        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.totalItemsCounted, 24)
        XCTAssertEqual(summary.highVarianceItems, 2)
        XCTAssertEqual(summary.targetTrackedSessions, 0)
        XCTAssertEqual(summary.targetHitRate, 0, accuracy: 0.001)
        XCTAssertEqual(recentSessions.count, 1)
        XCTAssertEqual(recentSessions.first?.type, .zoneMission)
    }

    @MainActor
    func testAutomationGeneratesZoneAssignedStaleTasks() {
        let suiteName = "inventory.tests.automation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected suite defaults")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000333")
        let store = AutomationStore(defaults: defaults)
        store.activateWorkspace(workspaceID)

        let signals = AutomationSignals(
            role: .owner,
            itemCount: 20,
            staleItemCount: 9,
            staleZoneAssignments: [
                AutomationZoneAssignment(zoneKey: "aisle 1", zoneLabel: "Aisle 1", staleItemCount: 5),
                AutomationZoneAssignment(zoneKey: "cooler a", zoneLabel: "Cooler A", staleItemCount: 3),
                AutomationZoneAssignment(zoneKey: AutomationStore.unassignedZoneKey, zoneLabel: "No Location", staleItemCount: 1)
            ],
            stockoutRiskCount: 0,
            urgentReplenishmentCount: 0,
            autoDraftCandidateCount: 0,
            autoDraftSuggestedUnits: 0,
            missingLocationCount: 0,
            missingDemandInputCount: 0,
            missingBarcodeCount: 0,
            pendingLedgerEventCount: 0,
            failedLedgerEventCount: 0,
            lowConfidenceItemCount: 0,
            countTargetTrackedSessions: 0,
            countTargetHitRate: 1
        )

        store.runAutomationCycle(using: signals, workspaceID: workspaceID, force: true)
        let zoneTasks = store.openTasks.filter { $0.ruleID.hasPrefix("stale-count-zone-") }

        XCTAssertEqual(zoneTasks.count, 3)
        XCTAssertTrue(zoneTasks.contains(where: { $0.assignedZone == "Aisle 1" }))
        XCTAssertTrue(zoneTasks.contains(where: { $0.assignedZone == "Cooler A" }))
        XCTAssertTrue(zoneTasks.contains(where: { $0.assignedZone == AutomationStore.unassignedZoneKey }))
    }

    @MainActor
    func testAutomationStaleTasksAreLimitedToTopThreeZones() {
        let suiteName = "inventory.tests.automation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected suite defaults")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000444")
        let store = AutomationStore(defaults: defaults)
        store.activateWorkspace(workspaceID)

        let signals = AutomationSignals(
            role: .owner,
            itemCount: 40,
            staleItemCount: 14,
            staleZoneAssignments: [
                AutomationZoneAssignment(zoneKey: "zone-a", zoneLabel: "Zone A", staleItemCount: 5),
                AutomationZoneAssignment(zoneKey: "zone-b", zoneLabel: "Zone B", staleItemCount: 4),
                AutomationZoneAssignment(zoneKey: "zone-c", zoneLabel: "Zone C", staleItemCount: 3),
                AutomationZoneAssignment(zoneKey: "zone-d", zoneLabel: "Zone D", staleItemCount: 2)
            ],
            stockoutRiskCount: 0,
            urgentReplenishmentCount: 0,
            autoDraftCandidateCount: 0,
            autoDraftSuggestedUnits: 0,
            missingLocationCount: 0,
            missingDemandInputCount: 0,
            missingBarcodeCount: 0,
            pendingLedgerEventCount: 0,
            failedLedgerEventCount: 0,
            lowConfidenceItemCount: 0,
            countTargetTrackedSessions: 0,
            countTargetHitRate: 1
        )

        store.runAutomationCycle(using: signals, workspaceID: workspaceID, force: true)
        let zoneTasks = store.openTasks.filter { $0.ruleID.hasPrefix("stale-count-zone-") }

        XCTAssertEqual(zoneTasks.count, 3)
        XCTAssertFalse(zoneTasks.contains(where: { $0.assignedZone == "Zone D" }))
    }

    func testCycleCountPlannerPrioritizesCriticalRiskAndSummarizesZone() {
        let now = Date(timeIntervalSince1970: 1_736_905_600) // Jan 9, 2025
        let criticalID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let balancedID = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        let routineID = UUID(uuidString: "00000000-0000-0000-0000-000000000903")!

        let inputs: [CountPlanInput] = [
            CountPlanInput(
                id: criticalID,
                itemName: "Critical Milk",
                locationLabel: "Cooler A",
                onHandUnits: 0,
                averageDailyUsage: 10,
                leadTimeDays: 2,
                lastCountedAt: now.addingTimeInterval(-23 * 24 * 60 * 60),
                missingBarcode: true,
                missingPlanningInputs: false,
                recentCorrectionCount: 2
            ),
            CountPlanInput(
                id: balancedID,
                itemName: "Balanced Chips",
                locationLabel: "Aisle 1",
                onHandUnits: 12,
                averageDailyUsage: 2,
                leadTimeDays: 3,
                lastCountedAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
                missingBarcode: false,
                missingPlanningInputs: false,
                recentCorrectionCount: 0
            ),
            CountPlanInput(
                id: routineID,
                itemName: "Routine Cups",
                locationLabel: "Backroom",
                onHandUnits: 25,
                averageDailyUsage: 1,
                leadTimeDays: 2,
                lastCountedAt: now.addingTimeInterval(-1 * 24 * 60 * 60),
                missingBarcode: false,
                missingPlanningInputs: false,
                recentCorrectionCount: 0
            )
        ]

        let plan = CycleCountPlannerEngine.buildPlan(
            inputs: inputs,
            mode: .balanced,
            now: now,
            includeRoutine: true
        )
        let summary = CycleCountPlannerEngine.summarize(candidates: plan)

        XCTAssertEqual(plan.first?.id, criticalID)
        XCTAssertEqual(plan.first?.band, .critical)
        XCTAssertEqual(summary.criticalCount, 1)
        XCTAssertEqual(summary.candidateCount, 3)
        XCTAssertEqual(summary.recommendedZoneLabel, "Cooler A")
    }

    func testCycleCountPlannerRespectsModeLimitAndRoutineFilter() {
        let now = Date(timeIntervalSince1970: 1_736_905_600) // Jan 9, 2025
        var inputs: [CountPlanInput] = []

        for index in 0..<20 {
            inputs.append(
                CountPlanInput(
                    id: UUID(),
                    itemName: "Item \(index)",
                    locationLabel: "Zone \(index % 3)",
                    onHandUnits: index % 2 == 0 ? 0 : 4,
                    averageDailyUsage: 3,
                    leadTimeDays: 2,
                    lastCountedAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
                    missingBarcode: false,
                    missingPlanningInputs: false,
                    recentCorrectionCount: 1
                )
            )
        }

        inputs.append(
            CountPlanInput(
                id: UUID(),
                itemName: "Routine Item",
                locationLabel: "Backroom",
                onHandUnits: 100,
                averageDailyUsage: 0,
                leadTimeDays: 0,
                lastCountedAt: now,
                missingBarcode: false,
                missingPlanningInputs: true,
                recentCorrectionCount: 0
            )
        )

        let plan = CycleCountPlannerEngine.buildPlan(
            inputs: inputs,
            mode: .express,
            now: now,
            includeRoutine: false
        )

        XCTAssertEqual(plan.count, CountPlanMode.express.itemLimit)
        XCTAssertFalse(plan.contains(where: { $0.band == .low }))
    }

    @MainActor
    func testValueTrackingSnapshotAggregatesShiftAndWeek() {
        let (store, defaults, suiteName) = makePlatformStore()
        defer { cleanPlatformDefaults(defaults, suiteName: suiteName) }

        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000777")
        let now = Date()

        let recentStart = now.addingTimeInterval(-2 * 60 * 60)
        let recentEnd = recentStart.addingTimeInterval(300)
        store.recordCountSession(
            type: .stockCount,
            workspaceID: workspaceID,
            actorName: "Tester",
            startedAt: recentStart,
            finishedAt: recentEnd,
            itemCount: 30,
            highVarianceCount: 4,
            blindModeEnabled: true
        )

        let olderStart = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let olderEnd = olderStart.addingTimeInterval(600)
        store.recordCountSession(
            type: .zoneMission,
            workspaceID: workspaceID,
            actorName: "Tester",
            startedAt: olderStart,
            finishedAt: olderEnd,
            itemCount: 20,
            highVarianceCount: 5,
            blindModeEnabled: false
        )

        let referenceDate = Date()
        let shift = store.valueTrackingSnapshot(
            workspaceID: workspaceID,
            window: .shift,
            referenceDate: referenceDate
        )
        let week = store.valueTrackingSnapshot(
            workspaceID: workspaceID,
            window: .week,
            referenceDate: referenceDate
        )

        XCTAssertEqual(shift.countsCompleted, 30)
        XCTAssertEqual(shift.shrinkRiskResolved, 4)
        XCTAssertGreaterThanOrEqual(shift.minutesSaved, 17)
        XCTAssertEqual(shift.countSessionRuns, 1)

        XCTAssertEqual(week.countsCompleted, 50)
        XCTAssertEqual(week.shrinkRiskResolved, 9)
        XCTAssertGreaterThanOrEqual(week.minutesSaved, shift.minutesSaved)
        XCTAssertEqual(week.countSessionRuns, 2)
    }

    @MainActor
    func testGuardBackupCooldownPreventsDuplicateSnapshots() {
        let (store, defaults, suiteName) = makePlatformStore()
        defer { cleanPlatformDefaults(defaults, suiteName: suiteName) }

        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000778")
        let first = store.createGuardBackupIfNeeded(
            reason: "CSV import",
            from: [],
            workspaceID: workspaceID,
            actorName: "Tester",
            cooldownMinutes: 60,
            minimumItemCount: 0
        )
        let second = store.createGuardBackupIfNeeded(
            reason: "CSV import",
            from: [],
            workspaceID: workspaceID,
            actorName: "Tester",
            cooldownMinutes: 60,
            minimumItemCount: 0
        )

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(store.backups(for: workspaceID).count, 1)
    }

    @MainActor
    func testAutomationPaceRecoveryPrefersReplenishmentWhenRiskElevated() {
        let suiteName = "inventory.tests.automation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected suite defaults")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000779")
        let store = AutomationStore(defaults: defaults)
        store.activateWorkspace(workspaceID)

        let signals = AutomationSignals(
            role: .manager,
            itemCount: 30,
            staleItemCount: 0,
            staleZoneAssignments: [],
            stockoutRiskCount: 6,
            urgentReplenishmentCount: 3,
            autoDraftCandidateCount: 0,
            autoDraftSuggestedUnits: 0,
            missingLocationCount: 0,
            missingDemandInputCount: 0,
            missingBarcodeCount: 0,
            pendingLedgerEventCount: 0,
            failedLedgerEventCount: 0,
            lowConfidenceItemCount: 0,
            countTargetTrackedSessions: 4,
            countTargetHitRate: 0.4
        )

        store.runAutomationCycle(using: signals, workspaceID: workspaceID, force: true)
        let paceTask = store.openTasks.first(where: { $0.ruleID == "count-pace-recovery" })

        XCTAssertEqual(paceTask?.action, .openReplenishment)
    }

    @MainActor
    func testPilotDailyMetricsAndCSVExport() throws {
        let (store, defaults, suiteName) = makePlatformStore()
        defer { cleanPlatformDefaults(defaults, suiteName: suiteName) }

        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000880")
        let now = Date()
        let start = now.addingTimeInterval(-900)
        let finish = start.addingTimeInterval(600)

        store.recordCountSession(
            type: .stockCount,
            workspaceID: workspaceID,
            actorName: "Tester",
            startedAt: start,
            finishedAt: finish,
            itemCount: 18,
            highVarianceCount: 2,
            blindModeEnabled: true
        )
        store.recordExceptionResolution(
            workspaceID: workspaceID,
            resolvedCount: 3,
            source: "unit-test"
        )

        let metrics = store.pilotDailyMetrics(workspaceID: workspaceID, day: now)
        XCTAssertEqual(metrics.countSessionRuns, 1)
        XCTAssertEqual(metrics.itemsCounted, 18)
        XCTAssertEqual(metrics.exceptionsResolved, 3)

        let csvURL = try store.exportPilotValidationCSV(
            workspaceID: workspaceID,
            actorName: "Tester",
            days: 2
        )
        let csvText = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csvText.contains("exceptions_resolved"))
        XCTAssertTrue(csvText.contains(",3,"))
    }

    @MainActor
    func testBackupRestoreHealthCheckPasses() {
        let (store, defaults, suiteName) = makePlatformStore()
        defer { cleanPlatformDefaults(defaults, suiteName: suiteName) }

        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000881")
        let result = store.runBackupRestoreHealthCheck(
            from: [],
            workspaceID: workspaceID,
            actorName: "Tester"
        )

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.payloadRoundTripValid)
        XCTAssertEqual(result.expectedItemCount, 0)
        XCTAssertEqual(result.snapshotItemCount, 0)
        XCTAssertEqual(store.backups(for: workspaceID).count, 1)
    }

    @MainActor
    private func makePlatformStore() -> (PlatformStore, UserDefaults, String) {
        let suiteName = "inventory.tests.platform.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create test defaults suite")
        }
        cleanPlatformDefaults(defaults, suiteName: suiteName)
        let store = PlatformStore(defaults: defaults)
        Self.retainedStores.append(store)
        return (store, defaults, suiteName)
    }

    private func cleanPlatformDefaults(_ defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
