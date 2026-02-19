import SwiftUI
import CoreData

private enum AutomationInboxFilter: String, CaseIterable, Identifiable {
    case open
    case snoozed
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open:
            return "Open"
        case .snoozed:
            return "Snoozed"
        case .done:
            return "Done"
        }
    }
}

struct AutomationInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var guidanceStore: GuidanceStore
    @EnvironmentObject private var automationStore: AutomationStore
    @EnvironmentObject private var purchaseOrderStore: PurchaseOrderStore
    @EnvironmentObject private var platformStore: PlatformStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.updatedAt, ascending: false)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var filter: AutomationInboxFilter = .open
    @State private var isPresentingZoneMission = false
    @State private var zoneMissionAssignment: String?
    @State private var isPresentingReplenishment = false
    @State private var isPresentingKPIDashboard = false
    @State private var isPresentingExceptionFeed = false
    @State private var isPresentingDailyOpsBrief = false
    @State private var isPresentingIntegrationHub = false
    @State private var isPresentingTrustCenter = false
    @State private var actionMessage: String?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    controlsCard
                    filterCard
                    tasksCard
                }
                .padding(16)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Automation Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $isPresentingZoneMission) {
            NavigationStack {
                ZoneMissionView(preferredZone: zoneMissionAssignment)
            }
        }
        .sheet(isPresented: $isPresentingReplenishment) {
            NavigationStack {
                ReplenishmentPlannerView()
            }
        }
        .sheet(isPresented: $isPresentingKPIDashboard) {
            NavigationStack {
                KPIDashboardView()
            }
        }
        .sheet(isPresented: $isPresentingExceptionFeed) {
            NavigationStack {
                ExceptionFeedView()
            }
        }
        .sheet(isPresented: $isPresentingDailyOpsBrief) {
            NavigationStack {
                DailyOpsBriefView()
            }
        }
        .sheet(isPresented: $isPresentingIntegrationHub) {
            NavigationStack {
                IntegrationHubView()
            }
        }
        .sheet(isPresented: $isPresentingTrustCenter) {
            NavigationStack {
                TrustCenterView()
            }
        }
        .alert("Automation Action", isPresented: .init(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                actionMessage = nil
            }
        } message: {
            Text(actionMessage ?? "")
        }
        .onAppear {
            refreshAutomation(force: true)
        }
        .onChange(of: authStore.activeWorkspaceID) { _, _ in
            refreshAutomation(force: true)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: context
            )
        ) { _ in
            refreshAutomation()
        }
        .onChange(of: isPresentingZoneMission) { _, isPresented in
            if !isPresented {
                zoneMissionAssignment = nil
            }
        }
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var automationSignals: AutomationSignals {
        let staleCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let staleItems = workspaceItems.filter { $0.updatedAt < staleCutoff }
        let staleItemCount = staleItems.count
        var staleZoneBuckets: [String: (label: String, count: Int)] = [:]
        for item in staleItems {
            let trimmedLocation = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let zoneKey: String
            let zoneLabel: String
            if trimmedLocation.isEmpty {
                zoneKey = AutomationStore.unassignedZoneKey
                zoneLabel = "No Location"
            } else {
                zoneKey = trimmedLocation.lowercased()
                zoneLabel = trimmedLocation
            }
            var existing = staleZoneBuckets[zoneKey] ?? (label: zoneLabel, count: 0)
            existing.count += 1
            staleZoneBuckets[zoneKey] = existing
        }
        let staleZoneAssignments = staleZoneBuckets.map { key, bucket in
            AutomationZoneAssignment(
                zoneKey: key,
                zoneLabel: bucket.label,
                staleItemCount: bucket.count
            )
        }.sorted { lhs, rhs in
            if lhs.staleItemCount != rhs.staleItemCount {
                return lhs.staleItemCount > rhs.staleItemCount
            }
            return lhs.zoneLabel.localizedCaseInsensitiveCompare(rhs.zoneLabel) == .orderedAscending
        }
        let missingLocationCount = workspaceItems.filter {
            $0.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let missingBarcodeCount = workspaceItems.filter {
            $0.barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        var stockoutRiskCount = 0
        var urgentReplenishmentCount = 0
        var autoDraftCandidateCount = 0
        var autoDraftSuggestedUnits: Int64 = 0
        var missingDemandInputCount = 0
        let reconnectBrief = platformStore.inventoryReconnectBrief(workspaceID: authStore.activeWorkspaceID)
        let countSummary = platformStore.countProductivitySummary(
            workspaceID: authStore.activeWorkspaceID,
            windowDays: 14
        )
        let confidenceOverview = platformStore.inventoryConfidenceOverview(
            for: workspaceItems,
            workspaceID: authStore.activeWorkspaceID,
            weakestLimit: workspaceItems.count
        )
        let lowConfidenceItemCount = confidenceOverview.criticalCount + confidenceOverview.weakCount

        for item in workspaceItems {
            let forecast = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let leadTimeDays = max(0, Double(item.leadTimeDays))
            let onHand = max(0, Int64(item.totalUnitsOnHand))
            let onHandUnits = Double(onHand)
            let safetyStock = max(0, item.safetyStockUnits)

            guard forecast > 0, leadTimeDays > 0 else {
                missingDemandInputCount += 1
                continue
            }

            let daysOfCover = onHandUnits / forecast
            let riskThreshold = max(1, leadTimeDays)
            if onHandUnits == 0 || daysOfCover <= riskThreshold {
                stockoutRiskCount += 1
            }

            let urgentThreshold = max(1, leadTimeDays * 0.5)
            if onHandUnits == 0 || daysOfCover <= urgentThreshold {
                urgentReplenishmentCount += 1
            }

            let reorderPoint = Int64((forecast * leadTimeDays).rounded(.up)) + safetyStock
            let baseSuggestedUnits = max(0, reorderPoint - onHand)
            let suggestedUnits = item.adjustedSuggestedOrderUnits(from: baseSuggestedUnits)
            if suggestedUnits > 0 && (onHandUnits == 0 || daysOfCover <= max(1, leadTimeDays)) {
                autoDraftCandidateCount += 1
                autoDraftSuggestedUnits += suggestedUnits
            }
        }

        return AutomationSignals(
            role: authStore.currentRole,
            itemCount: workspaceItems.count,
            staleItemCount: staleItemCount,
            staleZoneAssignments: staleZoneAssignments,
            stockoutRiskCount: stockoutRiskCount,
            urgentReplenishmentCount: urgentReplenishmentCount,
            autoDraftCandidateCount: autoDraftCandidateCount,
            autoDraftSuggestedUnits: autoDraftSuggestedUnits,
            missingLocationCount: missingLocationCount,
            missingDemandInputCount: missingDemandInputCount,
            missingBarcodeCount: missingBarcodeCount,
            pendingLedgerEventCount: reconnectBrief.pendingCount,
            failedLedgerEventCount: reconnectBrief.failedCount,
            lowConfidenceItemCount: lowConfidenceItemCount,
            countTargetTrackedSessions: countSummary.targetTrackedSessions,
            countTargetHitRate: countSummary.targetHitRate
        )
    }

    private var visibleTasks: [AutomationTask] {
        switch filter {
        case .open:
            return automationStore.openTasks
        case .snoozed:
            return automationStore.snoozedTasks
        case .done:
            return automationStore.completedTasks
        }
    }

    private var autoDraftLines: [PurchaseOrderLine] {
        let lines = workspaceItems.compactMap { item -> PurchaseOrderLine? in
            let forecast = max(item.averageDailyUsage, item.movingAverageDailyDemand ?? 0)
            let leadTimeDays = max(0, Double(item.leadTimeDays))
            let onHandUnits = max(0, Int64(item.totalUnitsOnHand))
            let safetyStock = max(0, item.safetyStockUnits)

            guard forecast > 0, leadTimeDays > 0 else { return nil }

            let reorderPoint = Int64((forecast * leadTimeDays).rounded(.up)) + safetyStock
            let baseSuggestedUnits = max(0, reorderPoint - onHandUnits)
            let suggestedUnits = item.adjustedSuggestedOrderUnits(from: baseSuggestedUnits)
            guard suggestedUnits > 0 else { return nil }

            let daysOfCover = Double(onHandUnits) / forecast
            guard onHandUnits == 0 || daysOfCover <= max(1, leadTimeDays) else {
                return nil
            }

            let preferredSupplier = item.normalizedPreferredSupplier
            let supplierSKU = item.normalizedSupplierSKU
            return PurchaseOrderLine(
                itemID: item.id,
                itemName: item.name,
                category: item.category,
                suggestedUnits: suggestedUnits,
                reorderPoint: reorderPoint,
                onHandUnits: onHandUnits,
                leadTimeDays: Int64(max(0, Int(leadTimeDays.rounded()))),
                forecastDailyDemand: forecast,
                preferredSupplier: preferredSupplier.isEmpty ? nil : preferredSupplier,
                supplierSKU: supplierSKU.isEmpty ? nil : supplierSKU,
                minimumOrderQuantity: item.minimumOrderQuantity > 0 ? item.minimumOrderQuantity : nil,
                reorderCasePack: item.reorderCasePack > 0 ? item.reorderCasePack : nil,
                leadTimeVarianceDays: item.leadTimeVarianceDays > 0 ? item.leadTimeVarianceDays : nil
            )
        }

        return lines.sorted { lhs, rhs in
            if lhs.suggestedUnits != rhs.suggestedUnits {
                return lhs.suggestedUnits > rhs.suggestedUnits
            }
            return lhs.itemName.localizedCaseInsensitiveCompare(rhs.itemName) == .orderedAscending
        }
    }

    private var autopilotBinding: Binding<Bool> {
        Binding(
            get: { automationStore.isAutopilotEnabled },
            set: { value in
                automationStore.setAutopilotEnabled(value, workspaceID: authStore.activeWorkspaceID)
                if value {
                    refreshAutomation(force: true)
                }
            }
        )
    }

    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { automationStore.isRemindersEnabled },
            set: { value in
                automationStore.setRemindersEnabled(value, workspaceID: authStore.activeWorkspaceID)
            }
        )
    }

    private var reminderWindowBinding: Binding<AutomationReminderWindow> {
        Binding(
            get: { automationStore.reminderWindow },
            set: { value in
                automationStore.setReminderWindow(value, workspaceID: authStore.activeWorkspaceID)
            }
        )
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Autopilot for counts, replenishment, and shrink follow-up.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Tasks below are generated from local inventory signals and updated automatically for this workspace.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }

    private var controlsCard: some View {
        sectionCard(title: "Automation Controls") {
            Toggle("Autopilot Enabled", isOn: autopilotBinding)
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)

            Toggle("Task Reminders", isOn: remindersBinding)
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accentDeep)

            if automationStore.isRemindersEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Reminder Window", selection: reminderWindowBinding) {
                        ForEach(AutomationReminderWindow.allCases) { window in
                            Text(window.title).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(automationStore.reminderWindow.description)
                        .font(Theme.font(10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if !automationStore.isReminderAuthorizationGranted && automationStore.isRemindersEnabled {
                Text("Notifications are not authorized on this device yet.")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                metricChip("Open", value: "\(automationStore.openTasks.count)")
                metricChip("Snoozed", value: "\(automationStore.snoozedTasks.count)")
                metricChip("Done", value: "\(automationStore.completedTasks.count)")
            }

            HStack {
                Button("Run Automation Now") {
                    refreshAutomation(force: true)
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                if let lastRunAt = automationStore.lastRunAt {
                    Text("Last run \(lastRunAt.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.font(10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private var filterCard: some View {
        sectionCard(title: "Queue") {
            Picker("Filter", selection: $filter) {
                ForEach(AutomationInboxFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var tasksCard: some View {
        sectionCard(title: "Tasks") {
            if visibleTasks.isEmpty {
                Text("No tasks in this queue.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            } else {
                ForEach(visibleTasks) { task in
                    taskRow(task)
                }
            }
        }
    }

    private func taskRow(_ task: AutomationTask) -> some View {
        let isDone = task.status == .done

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if isDone {
                        automationStore.reopenTask(task.id)
                    } else {
                        automationStore.markTaskDone(task.id)
                    }
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isDone ? Theme.accent : Theme.textTertiary)
                }
                .buttonStyle(.plain)

                Text(task.title)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if let assignedZone = task.assignedZone, !assignedZone.isEmpty {
                    Text("Zone: \(zoneLabel(for: assignedZone))")
                        .font(Theme.font(9, weight: .bold))
                        .foregroundStyle(Theme.accentDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.accentSoft.opacity(0.4))
                        )
                }

                Spacer()

                Text(task.priority.title.uppercased())
                    .font(Theme.font(9, weight: .bold))
                    .foregroundStyle(priorityTint(task.priority))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(priorityTint(task.priority).opacity(0.16))
                    )
            }

            Text(task.detail)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            HStack {
                Text("Est: \(task.estimateMinutes)m")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)

                Spacer()

                if task.status == .open {
                    Button("Snooze") {
                        automationStore.snoozeTask(task.id)
                    }
                    .buttonStyle(.bordered)
                }

                Button(task.action.title) {
                    openTaskAction(task)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
        .opacity(isDone ? 0.72 : 1)
    }

    private func priorityTint(_ priority: AutomationTaskPriority) -> Color {
        switch priority {
        case .critical:
            return .orange
        case .high:
            return Theme.accentDeep
        case .normal:
            return Theme.textSecondary
        }
    }

    private func metricChip(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 2)

            VStack(spacing: 10) {
                content()
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: 0.24)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private func refreshAutomation(force: Bool = false) {
        automationStore.runAutomationCycle(
            using: automationSignals,
            workspaceID: authStore.activeWorkspaceID,
            force: force
        )
    }

    private func openTaskAction(_ task: AutomationTask) {
        switch task.action {
        case .openAutomationInbox:
            break
        case .openZoneMission:
            guidanceStore.markFlowEngaged(.zoneMission)
            zoneMissionAssignment = task.assignedZone
            isPresentingZoneMission = true
        case .openReplenishment:
            guidanceStore.markFlowEngaged(.replenishment)
            isPresentingReplenishment = true
        case .createAutoDraftPO:
            createAutoDraftPurchaseOrder(from: task)
        case .openKPIDashboard:
            isPresentingKPIDashboard = true
        case .openExceptionFeed:
            isPresentingExceptionFeed = true
        case .openDailyOpsBrief:
            isPresentingDailyOpsBrief = true
        case .openGuidedHelp:
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guidanceStore.openGuideCenter()
            }
        case .openIntegrationHub:
            isPresentingIntegrationHub = true
        case .openTrustCenter:
            isPresentingTrustCenter = true
        }
    }

    private func createAutoDraftPurchaseOrder(from task: AutomationTask) {
        guard authStore.canManagePurchasing else {
            actionMessage = "Only owners and managers can create purchase orders."
            return
        }

        let lines = autoDraftLines
        guard !lines.isEmpty else {
            actionMessage = "No qualifying low-stock items are ready for an auto draft PO."
            return
        }

        let totalUnits = lines.reduce(Int64(0)) { $0 + $1.suggestedUnits }
        let notes = "Generated from Automation Inbox on \(Date().formatted(date: .abbreviated, time: .shortened))."
        let drafts = purchaseOrderStore.createDraftsGroupedBySupplier(
            lines: lines,
            workspaceID: authStore.activeWorkspaceID,
            source: "automation-auto-draft",
            notes: notes
        )
        guard !drafts.isEmpty else {
            actionMessage = "Unable to create an auto draft PO right now."
            return
        }

        automationStore.markTaskDone(task.id)
        Haptics.success()
        if drafts.count == 1, let draft = drafts.first {
            actionMessage = "Created \(draft.reference) with \(lines.count) items and \(totalUnits) suggested units."
        } else {
            let totalItems = drafts.reduce(0) { $0 + $1.itemCount }
            let batchedUnits = drafts.reduce(Int64(0)) { $0 + $1.totalSuggestedUnits }
            actionMessage = "Created \(drafts.count) supplier drafts with \(totalItems) items and \(batchedUnits) suggested units."
        }
        refreshAutomation(force: true)
    }

    private func zoneLabel(for zoneKey: String) -> String {
        if zoneKey == AutomationStore.unassignedZoneKey {
            return "No Location"
        }
        return zoneKey
    }
}
