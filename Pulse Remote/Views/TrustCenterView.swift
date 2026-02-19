import SwiftUI
import CoreData

struct TrustCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var platformStore: PlatformStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.updatedAt, ascending: false)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var restoreCandidate: InventoryBackupSnapshot?
    @State private var message: String?
    @State private var ledgerExportURL: URL?
    @State private var backupHealthResult: BackupRestoreHealthCheckResult?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    backupCard
                    auditCard
                    inventoryLedgerCard
                    reconnectBriefCard
                    confidenceCard
                    permissionCard
                }
                .padding(16)
            }
        }
        .navigationTitle("Trust Center")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .alert("Trust Center", isPresented: .init(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {
                message = nil
            }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: .init(
                get: { restoreCandidate != nil },
                set: { if !$0 { restoreCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let snapshot = restoreCandidate {
                    restore(snapshot)
                }
                restoreCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                restoreCandidate = nil
            }
        } message: {
            Text("Current workspace inventory will be replaced by this snapshot.")
        }
    }

    private var workspaceBackups: [InventoryBackupSnapshot] {
        platformStore.backups(for: authStore.activeWorkspaceID)
    }

    private var workspaceAudits: [PlatformAuditEvent] {
        platformStore.auditEvents(for: authStore.activeWorkspaceID, limit: 40)
    }

    private var workspaceInventoryEvents: [InventoryLedgerEvent] {
        platformStore.inventoryEvents(for: authStore.activeWorkspaceID, limit: 40, includeSynced: true)
    }

    private var pendingInventoryEventCount: Int {
        platformStore.pendingInventoryEventCount(for: authStore.activeWorkspaceID)
    }

    private var reconnectBrief: InventoryReconnectBrief {
        platformStore.inventoryReconnectBrief(workspaceID: authStore.activeWorkspaceID)
    }

    private var confidenceOverview: InventoryConfidenceOverview {
        platformStore.inventoryConfidenceOverview(
            for: Array(items),
            workspaceID: authStore.activeWorkspaceID,
            weakestLimit: 6
        )
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Protect your inventory with backups, audit trails, and controlled recovery.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Imports and sync actions create auditable events. Use snapshots to recover quickly when human error happens.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }

    private var backupCard: some View {
        sectionCard(title: "Backups + Recovery") {
            HStack(spacing: 10) {
                Button("Create Manual Backup") {
                    createBackup()
                }
                .buttonStyle(.borderedProminent)

                Button("Run Restore Check") {
                    runBackupRestoreCheck()
                }
                .buttonStyle(.bordered)
                .disabled(!authStore.canManageCatalog)
                .opacity(authStore.canManageCatalog ? 1 : 0.55)

                Text("\(workspaceBackups.count) snapshot(s)")
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            if workspaceBackups.isEmpty {
                Text("No backups yet. Create one before major imports or bulk adjustments.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(workspaceBackups.prefix(8)) { snapshot in
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.title)
                                .font(Theme.font(12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(snapshot.itemCount) items • \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button("Restore") {
                            guard authStore.canManageWorkspace else {
                                message = "Only workspace owners can run a full restore."
                                return
                            }
                            restoreCandidate = snapshot
                        }
                        .buttonStyle(.bordered)
                        .disabled(!authStore.canManageWorkspace)
                        .opacity(authStore.canManageWorkspace ? 1 : 0.55)
                    }
                    .padding(10)
                    .inventoryCard(cornerRadius: 12, emphasis: 0.2)
                }
            }

            if let backupHealthResult {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Restore Check \(backupHealthResult.passed ? "Passed" : "Needs Review")")
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(backupHealthResult.passed ? Theme.accentDeep : .orange)
                    Text("Snapshot: \(backupHealthResult.snapshotTitle)")
                        .font(Theme.font(10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Items expected \(backupHealthResult.expectedItemCount), snapshot \(backupHealthResult.snapshotItemCount)")
                        .font(Theme.font(10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Payload validation: \(backupHealthResult.payloadRoundTripValid ? "OK" : "Failed")")
                        .font(Theme.font(10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .inventoryCard(cornerRadius: 12, emphasis: 0.2)
            }
        }
    }

    @ViewBuilder
    private var auditCard: some View {
        sectionCard(title: "Audit Trail") {
            if workspaceAudits.isEmpty {
                Text("No audit events yet.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(workspaceAudits.prefix(12)) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: event.type.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.type.title)
                                .font(Theme.font(12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(event.summary)
                                .font(Theme.font(11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text("\(event.actorName) • \(event.createdAt.formatted(date: .omitted, time: .shortened))")
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .inventoryCard(cornerRadius: 12, emphasis: 0.2)
                }
            }
        }
    }

    @ViewBuilder
    private var inventoryLedgerCard: some View {
        sectionCard(title: "Offline Event Ledger") {
            HStack(spacing: 10) {
                Text("Pending sync: \(pendingInventoryEventCount)")
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("Mark Synced") {
                    let synced = platformStore.markInventoryEventsSynced(
                        workspaceID: authStore.activeWorkspaceID,
                        actorName: authStore.displayName,
                        maxCount: 200
                    )
                    if synced == 0 {
                        message = "No pending inventory events to sync."
                    } else {
                        message = "Marked \(synced) inventory event(s) as synced."
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pendingInventoryEventCount == 0)
                .opacity(pendingInventoryEventCount == 0 ? 0.55 : 1)

                Button("Export CSV") {
                    do {
                        let url = try platformStore.exportInventoryLedgerCSV(
                            workspaceID: authStore.activeWorkspaceID,
                            actorName: authStore.displayName,
                            includeSynced: true
                        )
                        ledgerExportURL = url
                        message = "Ledger exported."
                    } catch {
                        message = "Ledger export failed."
                    }
                }
                .buttonStyle(.bordered)
            }

            if let ledgerExportURL {
                ShareLink(item: ledgerExportURL) {
                    Label("Share latest ledger export", systemImage: "square.and.arrow.up")
                        .font(Theme.font(11, weight: .semibold))
                }
            }

            if workspaceInventoryEvents.isEmpty {
                Text("No inventory movement events captured yet.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(workspaceInventoryEvents.prefix(12)) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: event.type.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(event.type.title)
                                    .font(Theme.font(11, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(event.syncStatus.rawValue.uppercased())
                                    .font(Theme.font(8, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(syncStatusColor(event.syncStatus).opacity(0.18))
                                    )
                                    .foregroundStyle(syncStatusColor(event.syncStatus))
                            }
                            Text(eventSummaryText(event))
                                .font(Theme.font(11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text("\(event.actorName) • \(event.createdAt.formatted(date: .omitted, time: .shortened)) • \(event.source)")
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }

                        Spacer()
                    }
                    .padding(10)
                    .inventoryCard(cornerRadius: 12, emphasis: 0.2)
                }
            }
        }
    }

    @ViewBuilder
    private var reconnectBriefCard: some View {
        sectionCard(title: "Reconnect Shift Brief") {
            HStack(spacing: 10) {
                reconnectMetricChip("Pending", value: "\(reconnectBrief.pendingCount)", tint: .orange)
                reconnectMetricChip("Failed", value: "\(reconnectBrief.failedCount)", tint: .red)
                reconnectMetricChip("Units", value: "\(reconnectBrief.unsyncedUnits)", tint: Theme.accentDeep)
            }

            HStack(spacing: 10) {
                Button("Run Auto Sync") {
                    runLedgerAutoSync()
                }
                .buttonStyle(.borderedProminent)
                .disabled(reconnectBrief.unsyncedCount == 0)
                .opacity(reconnectBrief.unsyncedCount == 0 ? 0.55 : 1)

                Spacer()

                Text("Unsynced events: \(reconnectBrief.unsyncedCount)")
                    .font(Theme.font(10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            if reconnectBrief.steps.isEmpty {
                Text("No reconnect actions needed right now.")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(reconnectBrief.steps.prefix(3)) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .font(Theme.font(11, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(step.detail)
                            .font(Theme.font(10, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .inventoryCard(cornerRadius: 12, emphasis: 0.2)
                }
            }

            if !reconnectBrief.sourceLoad.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top unsynced sources")
                        .font(Theme.font(10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(reconnectBrief.sourceLoad.prefix(3)) { load in
                        HStack {
                            Text(load.source)
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(load.count)")
                                .font(Theme.font(10, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var confidenceCard: some View {
        sectionCard(title: "Inventory Confidence Engine") {
            if confidenceOverview.itemCount == 0 {
                Text("Add inventory activity to generate confidence scoring.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    reconnectMetricChip("Avg Score", value: "\(confidenceOverview.averageScore)", tint: Theme.accent)
                    reconnectMetricChip("Critical", value: "\(confidenceOverview.criticalCount)", tint: .red)
                    reconnectMetricChip("Weak", value: "\(confidenceOverview.weakCount)", tint: .orange)
                }

                ForEach(confidenceOverview.weakestItems) { signal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(signal.itemName)
                                .font(Theme.font(11, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(signal.score)")
                                .font(Theme.font(10, weight: .bold))
                                .foregroundStyle(confidenceTierColor(signal.tier))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(confidenceTierColor(signal.tier).opacity(0.18))
                                )
                        }

                        if let reason = signal.reasons.first {
                            Text(reason)
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Text(signal.recommendation)
                            .font(Theme.font(10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .inventoryCard(cornerRadius: 12, emphasis: 0.2)
                }
            }
        }
    }

    private var permissionCard: some View {
        sectionCard(title: "Role Guardrails") {
            capabilityRow("Manage catalog", enabled: authStore.canManageCatalog)
            capabilityRow("Delete items", enabled: authStore.canDeleteItems)
            capabilityRow("Create workspace backups", enabled: authStore.canManageCatalog)
            capabilityRow("Restore full workspace", enabled: authStore.canManageWorkspace)
            Text("Current role: \(authStore.currentRole.title)")
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.accentDeep)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func capabilityRow(_ title: String, enabled: Bool) -> some View {
        HStack {
            Image(systemName: enabled ? "checkmark.shield.fill" : "lock.fill")
                .foregroundStyle(enabled ? Theme.accent : Theme.textTertiary)
            Text(title)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(enabled ? "Enabled" : "Restricted")
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(enabled ? Theme.accentDeep : Theme.textTertiary)
        }
    }

    private func reconnectMetricChip(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(15, weight: .semibold))
                .foregroundStyle(tint)
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

    private func eventSummaryText(_ event: InventoryLedgerEvent) -> String {
        let item = event.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown item" : event.itemName
        let deltaLabel = event.deltaUnits >= 0 ? "+\(event.deltaUnits)" : "\(event.deltaUnits)"
        if let resulting = event.resultingUnits {
            return "\(item) • \(deltaLabel) units • on hand \(resulting)"
        }
        return "\(item) • \(deltaLabel) units"
    }

    private func syncStatusColor(_ status: InventoryEventSyncStatus) -> Color {
        switch status {
        case .pending:
            return .orange
        case .synced:
            return Theme.accentDeep
        case .failed:
            return .red
        }
    }

    private func confidenceTierColor(_ tier: InventoryConfidenceTier) -> Color {
        switch tier {
        case .strong:
            return .green
        case .watch:
            return Theme.accentDeep
        case .weak:
            return .orange
        case .critical:
            return .red
        }
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

    private func createBackup() {
        guard authStore.canManageCatalog else {
            message = "Only owners and managers can create backups."
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        let title = "Manual backup \(formatter.string(from: Date()))"
        _ = platformStore.createBackup(
            title: title,
            from: Array(items),
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName
        )
        Haptics.success()
        message = "Backup created."
    }

    private func runBackupRestoreCheck() {
        guard authStore.canManageCatalog else {
            message = "Only owners and managers can run restore checks."
            return
        }
        let result = platformStore.runBackupRestoreHealthCheck(
            from: Array(items),
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName
        )
        backupHealthResult = result
        if result.passed {
            Haptics.success()
            message = "Backup + restore check passed."
        } else {
            message = "Backup + restore check needs review."
        }
    }

    private func restore(_ snapshot: InventoryBackupSnapshot) {
        let restored = platformStore.restoreBackup(
            snapshot,
            allItems: Array(items),
            context: context,
            dataController: dataController,
            actorName: authStore.displayName
        )
        Haptics.success()
        message = "Restore complete. \(restored) item(s) recovered."
    }

    private func runLedgerAutoSync() {
        let run = platformStore.syncInventoryLedger(
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            allItems: Array(items),
            maxEvents: 200
        )
        message = run.message
        if run.synced > 0 {
            Haptics.success()
        }
    }
}
