import SwiftUI
import CoreData

struct IntegrationHubView: View {
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

    @State private var csvText = ""
    @State private var lastMessage: String?
    @State private var exportURL: URL?
    @State private var webhookPayloadText = ""
    @State private var selectedWebhookProvider: IntegrationProvider = .quickBooks
    @State private var editingProvider: IntegrationProvider?
    @State private var accountLabel = ""
    @State private var accessToken = ""
    @State private var refreshToken = ""
    @State private var webhookSecret = ""
    @State private var hasSavedAccessToken = false
    @State private var hasSavedRefreshToken = false
    @State private var hasSavedWebhookSecret = false
    @State private var knownTokenExpiry: Date?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    providerCard
                    ledgerReconnectCard
                    syncRetryCard
                    webhookIngestCard
                    webhookInboxCard
                    conflictCenterCard
                    csvExportCard
                    csvImportCard
                    syncHistoryCard
                }
                .padding(16)
            }
        }
        .navigationTitle("Integration Hub")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .sheet(item: $editingProvider) { provider in
            NavigationStack {
                connectionEditor(provider)
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Integration Status", isPresented: .init(
            get: { lastMessage != nil },
            set: { if !$0 { lastMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                lastMessage = nil
            }
        } message: {
            Text(lastMessage ?? "")
        }
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var syncJobs: [IntegrationSyncJob] {
        platformStore.syncJobs(for: authStore.activeWorkspaceID)
    }

    private var syncRetries: [IntegrationSyncRetryJob] {
        platformStore.syncRetryJobs(for: authStore.activeWorkspaceID, includeResolved: true, limit: 40)
    }

    private var ledgerBrief: InventoryReconnectBrief {
        platformStore.inventoryReconnectBrief(workspaceID: authStore.activeWorkspaceID)
    }

    private var queuedSyncRetries: [IntegrationSyncRetryJob] {
        syncRetries.filter { $0.status == .queued }
    }

    private var unresolvedConflicts: [IntegrationConflict] {
        platformStore.unresolvedConflicts(for: authStore.activeWorkspaceID, limit: 40)
    }

    private var webhookInboxEvents: [IntegrationWebhookEvent] {
        platformStore.webhookEvents(for: authStore.activeWorkspaceID, limit: 40)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect external systems, process webhooks, and resolve sync conflicts safely.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("This phase adds connection state, webhook ingestion, and guided conflict resolution so integrations can run with audit-ready controls.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }

    private var providerCard: some View {
        sectionCard(title: "Provider Connections") {
            ForEach(IntegrationProvider.allCases) { provider in
                providerRow(provider)
            }
        }
    }

    @ViewBuilder
    private var ledgerReconnectCard: some View {
        sectionCard(title: "Offline Ledger Reconnect") {
            HStack(spacing: 10) {
                metricChip("Pending", value: "\(ledgerBrief.pendingCount)", tint: .orange)
                metricChip("Failed", value: "\(ledgerBrief.failedCount)", tint: .red)
                metricChip("Units", value: "\(ledgerBrief.unsyncedUnits)", tint: Theme.accentDeep)
            }

            HStack(spacing: 10) {
                Button("Run Auto Sync") {
                    runLedgerAutoSync()
                }
                .buttonStyle(.borderedProminent)
                .disabled(ledgerBrief.unsyncedCount == 0)
                .opacity(ledgerBrief.unsyncedCount == 0 ? 0.55 : 1)

                Spacer()

                Text("Unsynced events: \(ledgerBrief.unsyncedCount)")
                    .font(Theme.font(10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            if !ledgerBrief.connectionIssues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection blockers")
                        .font(Theme.font(10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(Array(ledgerBrief.connectionIssues.prefix(2)), id: \.self) { issue in
                        Text("• \(issue)")
                            .font(Theme.font(10, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func providerRow(_ provider: IntegrationProvider) -> some View {
        let connection = platformStore.connection(for: provider, workspaceID: authStore.activeWorkspaceID)
        let secretState = platformStore.integrationSecretState(for: provider, workspaceID: authStore.activeWorkspaceID)
        let status = secretState.status
        let isConnected = status == .connected
        let canSync = isConnected && secretState.hasAccessToken
        let statusForeground: Color = {
            switch status {
            case .connected:
                return Theme.accentDeep
            case .tokenExpired:
                return .orange
            case .disconnected:
                return Theme.textTertiary
            }
        }()
        let statusBackground: Color = {
            switch status {
            case .connected:
                return Theme.accentSoft.opacity(0.7)
            case .tokenExpired:
                return Color.orange.opacity(0.22)
            case .disconnected:
                return Theme.subtleBorder.opacity(0.7)
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: provider.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.title)
                        .font(Theme.font(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(connectionSummary(connection: connection, secretState: secretState))
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(status.title)
                    .font(Theme.font(9, weight: .bold))
                    .foregroundStyle(statusForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(statusBackground)
                    )
            }

            if let healthLine = tokenHealthLine(secretState) {
                Text(healthLine)
                    .font(Theme.font(10, weight: .medium))
                    .foregroundStyle(status == .tokenExpired ? Color.orange : Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button(connection == nil ? "Connect" : "Manage") {
                    openConnectionEditor(for: provider)
                }
                .buttonStyle(.bordered)

                Button("Sync Now") {
                    let synced = platformStore.runConnectedSync(
                        provider: provider,
                        workspaceID: authStore.activeWorkspaceID,
                        actorName: authStore.displayName,
                        allItems: Array(items)
                    )
                    if synced {
                        Haptics.success()
                    } else {
                        lastMessage = "Sync blocked. Refresh token or reconnect \(provider.title)."
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSync)
                .opacity(canSync ? 1 : 0.55)

                if connection != nil {
                    Button("Refresh Token") {
                        refreshConnection(for: provider)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!secretState.hasRefreshToken)
                    .opacity(secretState.hasRefreshToken ? 1 : 0.55)
                }
            }
        }
        .padding(12)
        .inventoryCard(cornerRadius: 12, emphasis: 0.24)
    }

    @ViewBuilder
    private var syncRetryCard: some View {
        sectionCard(title: "Sync Retry Queue") {
            HStack(spacing: 10) {
                Text("Queued: \(queuedSyncRetries.count)")
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("Run Due Retries") {
                    processDueRetries()
                }
                .buttonStyle(.borderedProminent)
                .disabled(queuedSyncRetries.isEmpty)
                .opacity(queuedSyncRetries.isEmpty ? 0.55 : 1)
            }

            if syncRetries.isEmpty {
                Text("No retries queued.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(syncRetries.prefix(10)) { retry in
                    let statusColor: Color = {
                        switch retry.status {
                        case .queued:
                            return .orange
                        case .resolved:
                            return Theme.accentDeep
                        case .abandoned:
                            return Theme.textTertiary
                        }
                    }()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: retry.provider.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text(retry.provider.title)
                                .font(Theme.font(12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(retry.status.title.uppercased())
                                .font(Theme.font(9, weight: .bold))
                                .foregroundStyle(statusColor)
                        }

                        Text(retryDetailText(retry))
                            .font(Theme.font(11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)

                        if let note = optionalTrimmed(retry.lastError) {
                            Text(note)
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }

                        HStack(spacing: 10) {
                            if retry.status == .queued {
                                Button("Retry Now") {
                                    retryNow(retry)
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Button(retry.status == .queued ? "Dismiss" : "Remove") {
                                dismissRetry(retry)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(10)
                    .inventoryCard(cornerRadius: 12, emphasis: 0.2)
                }
            }
        }
    }

    private var webhookIngestCard: some View {
        sectionCard(title: "Webhook Ingest") {
            Picker("Provider", selection: $selectedWebhookProvider) {
                ForEach(IntegrationProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.cardBackground.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.subtleBorder, lineWidth: 1)
                    )

                TextEditor(text: $webhookPayloadText)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(8)
                    .frame(minHeight: 120)

                if webhookPayloadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("event=inventory.updated barcode=012345 qty=24")
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                }
            }
            .frame(minHeight: 120)

            HStack(spacing: 10) {
                Button("Ingest Payload") {
                    ingestWebhookPayload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(webhookPayloadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Clear") {
                    webhookPayloadText = ""
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var webhookInboxCard: some View {
        sectionCard(title: "Webhook Inbox") {
            if webhookInboxEvents.isEmpty {
                Text("No webhook events queued.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(webhookInboxEvents.prefix(10)) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: event.provider.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text(event.eventType)
                                .font(Theme.font(12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(event.status.title.uppercased())
                                .font(Theme.font(9, weight: .bold))
                                .foregroundStyle(event.status == .pending ? .orange : Theme.textTertiary)
                        }

                        Text(event.payloadPreview)
                            .font(Theme.font(11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)

                        if let note = optionalTrimmed(event.note) {
                            Text(note)
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }

                        if event.status == .pending {
                            HStack(spacing: 10) {
                                Button("Apply") {
                                    _ = platformStore.applyWebhookEvent(
                                        event.id,
                                        workspaceID: authStore.activeWorkspaceID,
                                        actorName: authStore.displayName
                                    )
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Ignore") {
                                    _ = platformStore.ignoreWebhookEvent(event.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(10)
                    .inventoryCard(cornerRadius: 12, emphasis: 0.2)
                }
            }
        }
    }

    @ViewBuilder
    private var conflictCenterCard: some View {
        sectionCard(title: "Conflict Center") {
            if unresolvedConflicts.isEmpty {
                Text("No unresolved sync conflicts.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(unresolvedConflicts.prefix(12)) { conflict in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: conflict.provider.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text(conflict.type.title)
                                .font(Theme.font(12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(conflict.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }

                        Text(conflictSummary(conflict))
                            .font(Theme.font(11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 10) {
                            Button("Keep Local") {
                                resolve(conflict, using: .keepLocal)
                            }
                            .buttonStyle(.bordered)

                            Button("Accept Remote") {
                                resolve(conflict, using: .acceptRemote)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(10)
                    .inventoryCard(cornerRadius: 12, emphasis: 0.2)
                }
            }
        }
    }

    private var csvExportCard: some View {
        sectionCard(title: "CSV Export") {
            HStack(spacing: 10) {
                Button("Export Current Workspace CSV") {
                    exportCSV()
                }
                .buttonStyle(.borderedProminent)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("Exports core inventory fields for backup, external analysis, or upload to accounting/ecommerce systems.")
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var csvImportCard: some View {
        sectionCard(title: "CSV Import") {
            Text("Paste CSV with headers: `name, barcode, category, location, isLiquid, quantity, unitsPerCase, looseUnits, eachesPerUnit, looseEaches, averageDailyUsage, leadTimeDays, safetyStockUnits, preferredSupplier, supplierSKU, minimumOrderQuantity, reorderCasePack, leadTimeVarianceDays, notes`")
                .font(Theme.font(10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.cardBackground.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.subtleBorder, lineWidth: 1)
                    )

                TextEditor(text: $csvText)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(8)
                    .frame(minHeight: 130)

                if csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("name,barcode,category,location,isLiquid,quantity,...")
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                }
            }
            .frame(minHeight: 130)

            HStack(spacing: 10) {
                Button("Import CSV") {
                    importCSV()
                }
                .buttonStyle(.borderedProminent)
                .disabled(csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Clear") {
                    csvText = ""
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var syncHistoryCard: some View {
        sectionCard(title: "Recent Sync History") {
            if syncJobs.isEmpty {
                Text("No sync jobs yet.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(syncJobs.prefix(8)) { job in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: job.provider.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.message)
                                .font(Theme.font(12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Pushed \(job.pushedRecords), Pulled \(job.pulledRecords) • \(job.finishedAt.formatted(date: .omitted, time: .shortened))")
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Circle()
                            .fill(job.status == .success ? Theme.accent : Color.orange)
                            .frame(width: 8, height: 8)
                    }
                    .padding(10)
                    .inventoryCard(cornerRadius: 12, emphasis: 0.2)
                }
            }
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

    private func metricChip(_ title: String, value: String, tint: Color) -> some View {
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

    @ViewBuilder
    private func connectionEditor(_ provider: IntegrationProvider) -> some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 14) {
                    sectionCard(title: "\(provider.title) Connection") {
                        TextField("", text: $accountLabel, prompt: Theme.inputPrompt("Account label"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .inventoryTextInputField()

                        SecureField(
                            "",
                            text: $accessToken,
                            prompt: Theme.inputPrompt(
                                hasSavedAccessToken
                                    ? "Access token (leave blank to keep current)"
                                    : "Access token"
                            )
                        )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .inventoryTextInputField()

                        SecureField(
                            "",
                            text: $refreshToken,
                            prompt: Theme.inputPrompt(
                                hasSavedRefreshToken
                                    ? "Refresh token (leave blank to keep current)"
                                    : "Refresh token (optional)"
                            )
                        )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .inventoryTextInputField()

                        SecureField(
                            "",
                            text: $webhookSecret,
                            prompt: Theme.inputPrompt(
                                hasSavedWebhookSecret
                                    ? "Webhook secret (leave blank to keep current)"
                                    : "Webhook secret (optional)"
                            )
                        )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .inventoryTextInputField()

                        if hasSavedAccessToken || hasSavedRefreshToken || hasSavedWebhookSecret {
                            Text("Secrets already saved in Keychain. Leave blank to keep current values.")
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let knownTokenExpiry {
                            Text("Current access token expires \(knownTokenExpiry.formatted(date: .abbreviated, time: .shortened)).")
                                .font(Theme.font(10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text("Secrets are stored in iOS Keychain for this offline-first phase.")
                            .font(Theme.font(10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Manage Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    editingProvider = nil
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveConnection(for: provider)
                }
                .disabled(
                    accountLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || (
                        accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !hasSavedAccessToken
                    )
                )
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Disconnect") {
                    disconnectConnection(for: provider)
                }
                .foregroundStyle(.orange)
            }
        }
    }

    private func connectionSummary(
        connection: IntegrationConnection?,
        secretState: IntegrationSecretState
    ) -> String {
        guard let connection else {
            return "No credentials saved."
        }
        if secretState.status == .tokenExpired {
            return "\(connection.accountLabel) • Token refresh required"
        }
        if let lastSyncAt = connection.lastSyncAt {
            return "\(connection.accountLabel) • Last sync \(lastSyncAt.formatted(date: .omitted, time: .shortened))"
        }
        return "\(connection.accountLabel) • Ready to sync"
    }

    private func tokenHealthLine(_ secretState: IntegrationSecretState) -> String? {
        guard secretState.hasAccessToken else {
            return "No access token found."
        }
        if let expiresAt = secretState.tokenExpiresAt {
            if expiresAt <= Date() {
                return "Access token expired."
            }
            return "Access token expires \(expiresAt.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Access token is active."
    }

    private func retryDetailText(_ retry: IntegrationSyncRetryJob) -> String {
        switch retry.status {
        case .queued:
            return "Attempt \(retry.attemptCount)/\(retry.maxAttempts) • Next try \(retry.nextAttemptAt.formatted(date: .omitted, time: .shortened))"
        case .resolved:
            return "Recovered after \(retry.attemptCount) attempt(s)."
        case .abandoned:
            return "Stopped after \(retry.attemptCount) attempt(s)."
        }
    }

    private func conflictSummary(_ conflict: IntegrationConflict) -> String {
        switch conflict.type {
        case .quantityMismatch:
            let itemName = conflict.localItemName.isEmpty ? conflict.remoteItemName : conflict.localItemName
            return "\(itemName): local \(conflict.localUnits) vs remote \(conflict.remoteUnits)."
        case .missingLocalItem:
            return "Remote item '\(conflict.remoteItemName)' not found locally (remote qty \(conflict.remoteUnits))."
        case .missingRemoteItem:
            return "Local item '\(conflict.localItemName)' not found remotely."
        case .metadataMismatch:
            return "Metadata differs between local and remote records for '\(conflict.localItemName)'."
        }
    }

    private func openConnectionEditor(for provider: IntegrationProvider) {
        let existing = platformStore.connection(for: provider, workspaceID: authStore.activeWorkspaceID)
        let secretState = platformStore.integrationSecretState(for: provider, workspaceID: authStore.activeWorkspaceID)
        accountLabel = existing?.accountLabel ?? ""
        accessToken = ""
        refreshToken = ""
        webhookSecret = ""
        hasSavedAccessToken = secretState.hasAccessToken
        hasSavedRefreshToken = secretState.hasRefreshToken
        hasSavedWebhookSecret = secretState.hasWebhookSecret
        knownTokenExpiry = secretState.tokenExpiresAt
        editingProvider = provider
    }

    private func saveConnection(for provider: IntegrationProvider) {
        let saved = platformStore.saveConnection(
            provider: provider,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            accountLabel: accountLabel,
            accessToken: accessToken,
            refreshToken: refreshToken,
            webhookSecret: webhookSecret
        )
        if saved {
            Haptics.success()
            lastMessage = "\(provider.title) connected."
            editingProvider = nil
            hasSavedAccessToken = false
            hasSavedRefreshToken = false
            hasSavedWebhookSecret = false
            knownTokenExpiry = nil
        } else {
            lastMessage = "Account label and a valid access token are required."
        }
    }

    private func disconnectConnection(for provider: IntegrationProvider) {
        platformStore.disconnectConnection(
            provider: provider,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName
        )
        lastMessage = "\(provider.title) disconnected."
        hasSavedAccessToken = false
        hasSavedRefreshToken = false
        hasSavedWebhookSecret = false
        knownTokenExpiry = nil
        editingProvider = nil
    }

    private func refreshConnection(for provider: IntegrationProvider) {
        let refreshed = platformStore.refreshConnectionToken(
            provider: provider,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName
        )
        if refreshed {
            Haptics.success()
            let state = platformStore.integrationSecretState(for: provider, workspaceID: authStore.activeWorkspaceID)
            knownTokenExpiry = state.tokenExpiresAt
            lastMessage = "\(provider.title) token refreshed."
        } else {
            lastMessage = "Refresh failed. Save a refresh token in Manage Connection."
        }
    }

    private func processDueRetries() {
        let processed = platformStore.processDueSyncRetries(
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            allItems: Array(items),
            maxJobs: 3
        )
        if processed > 0 {
            Haptics.success()
            lastMessage = "Processed \(processed) due sync retr\(processed == 1 ? "y" : "ies")."
        } else {
            lastMessage = "No due retries right now."
        }
    }

    private func runLedgerAutoSync() {
        let run = platformStore.syncInventoryLedger(
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            allItems: Array(items),
            maxEvents: 200
        )
        if run.synced > 0 {
            Haptics.success()
        }
        lastMessage = run.message
    }

    private func retryNow(_ retry: IntegrationSyncRetryJob) {
        let processed = platformStore.retrySyncJobNow(
            retry.id,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            allItems: Array(items)
        )
        if processed {
            Haptics.success()
            lastMessage = "Retry attempt submitted for \(retry.provider.title)."
        } else {
            lastMessage = "Retry could not be processed."
        }
    }

    private func dismissRetry(_ retry: IntegrationSyncRetryJob) {
        if platformStore.dismissSyncRetryJob(retry.id) {
            lastMessage = "Retry record removed."
        }
    }

    private func ingestWebhookPayload() {
        let created = platformStore.ingestWebhookPayload(
            webhookPayloadText,
            provider: selectedWebhookProvider,
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            allItems: Array(items)
        )
        if created > 0 {
            webhookPayloadText = ""
            Haptics.success()
            lastMessage = "Ingested \(created) webhook event(s)."
        }
    }

    private func resolve(_ conflict: IntegrationConflict, using resolution: IntegrationConflictResolution) {
        let resolved = platformStore.resolveConflict(
            conflict.id,
            resolution: resolution,
            allItems: Array(items),
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            dataController: dataController
        )
        if resolved {
            Haptics.success()
        }
    }

    private func optionalTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func exportCSV() {
        do {
            exportURL = try platformStore.exportCSV(
                from: Array(items),
                workspaceID: authStore.activeWorkspaceID,
                actorName: authStore.displayName
            )
            lastMessage = "CSV export is ready to share."
            Haptics.success()
        } catch {
            lastMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importCSV() {
        let summary = platformStore.importCSV(
            csvText,
            allItems: Array(items),
            workspaceID: authStore.activeWorkspaceID,
            actorName: authStore.displayName,
            context: context,
            dataController: dataController
        )
        lastMessage = summary.description
        if summary.createdCount + summary.updatedCount > 0 {
            Haptics.success()
        }
    }
}
