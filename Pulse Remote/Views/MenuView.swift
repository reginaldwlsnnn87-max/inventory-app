import SwiftUI

struct MenuView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var guidanceStore: GuidanceStore
    @AppStorage(Theme.modeStorageKey) private var themeModeRawValue = ThemeMode.vibrant.rawValue
    @State private var showingInfo: String?
    @State private var newWorkspaceName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        commandDeckCard
                            .inventoryStaggered(index: 0)
                        profileCard
                            .inventoryStaggered(index: 1)
                        workspaceCard
                            .inventoryStaggered(index: 2)
                        appearanceCard
                            .inventoryStaggered(index: 3)
                        menuSection(
                            title: "Workspace",
                            systemImage: "briefcase.fill",
                            module: .workspace,
                            sectionIndex: 4,
                            rows: [
                                MenuRow(title: "Run Shift", systemImage: "play.circle.fill", badge: "NEW", destination: .runShift, module: .counts),
                                MenuRow(title: "Workflows", systemImage: "square.stack.3d.up", destination: .workflows, module: .workspace),
                                MenuRow(title: "Daily Ops Brief", systemImage: "checklist.checked", badge: "NEW", destination: .dailyOpsBrief, module: .intelligence),
                                MenuRow(title: "Automation Inbox", systemImage: "tray.full", badge: "NEW", destination: .automationInbox, module: .automation),
                                MenuRow(title: "Integration Hub", systemImage: "arrow.triangle.2.circlepath", badge: "NEW", destination: .integrationHub, module: .automation),
                                MenuRow(title: "Trust Center", systemImage: "checkmark.shield", badge: "NEW", destination: .trustCenter, module: .trust),
                                MenuRow(title: "Ops Intelligence", systemImage: "waveform.path.ecg.rectangle", badge: "NEW", destination: .opsIntelligence, module: .intelligence),
                                MenuRow(title: "Zone Mission", systemImage: "map.fill", badge: "NEW", destination: .zoneMission, module: .counts),
                                MenuRow(title: "Cycle Count Planner", systemImage: "target", badge: "NEW", destination: .cyclePlanner, module: .counts),
                                MenuRow(title: "KPI Dashboard", systemImage: "chart.bar.doc.horizontal", badge: "NEW", destination: .kpiDashboard, module: .reports),
                                MenuRow(title: "Starter Templates", systemImage: "wand.and.sparkles", badge: "NEW", destination: .starterTemplates, module: .catalog),
                                MenuRow(title: "Exception Feed", systemImage: "exclamationmark.bubble", badge: "NEW", destination: .exceptions, module: .shrink),
                                MenuRow(title: "Replenishment Planner", systemImage: "chart.line.uptrend.xyaxis", badge: "NEW", destination: .replenishment, module: .replenishment),
                                MenuRow(title: "Calculations Lab", systemImage: "function", badge: "NEW", destination: .calculations, module: .reports),
                                MenuRow(title: "User Profile", systemImage: "person.crop.circle", module: .workspace),
                                MenuRow(title: "Company Details", systemImage: "briefcase", module: .workspace),
                                MenuRow(title: "Addresses", systemImage: "mappin.and.ellipse", badge: "NEW", module: .workspace)
                            ]
                        )
                        menuSection(
                            title: "Reports",
                            systemImage: "chart.bar.xaxis",
                            module: .reports,
                            sectionIndex: 5,
                            rows: [
                                MenuRow(title: "Reports", systemImage: "chart.pie", module: .reports),
                                MenuRow(title: "Bulk Import", systemImage: "tray.and.arrow.down", module: .catalog),
                                MenuRow(title: "Custom Fields", systemImage: "list.bullet.rectangle", module: .catalog)
                            ]
                        )
                        menuSection(
                            title: "Labels",
                            systemImage: "tag.fill",
                            module: .catalog,
                            sectionIndex: 6,
                            rows: [
                                MenuRow(title: "Create Labels", systemImage: "barcode", module: .catalog),
                                MenuRow(title: "Manage Tags", systemImage: "tag", module: .catalog),
                                MenuRow(title: "Sync Inventory", systemImage: "arrow.triangle.2.circlepath", module: .automation)
                            ]
                        )
                        menuSection(
                            title: "Support",
                            systemImage: "lifepreserver.fill",
                            module: .support,
                            sectionIndex: 7,
                            rows: [
                                MenuRow(title: "Guided Help", systemImage: "questionmark.bubble", badge: "NEW", action: .guidedHelp, module: .support),
                                MenuRow(title: "Product News", systemImage: "megaphone", badge: "NEW", module: .support),
                                MenuRow(title: "Help & Support", systemImage: "questionmark.circle", module: .support),
                                MenuRow(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right", action: .signOut, module: .support)
                            ]
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(Theme.accent)
            .alert("Coming soon", isPresented: .init(
                get: { showingInfo != nil },
                set: { if !$0 { showingInfo = nil } }
            )) {
                Button("OK", role: .cancel) {
                    showingInfo = nil
                }
            } message: {
                Text(showingInfo ?? "")
            }
        }
    }

    private var commandDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Command Deck")
                        .font(Theme.titleFont())
                        .foregroundStyle(Theme.textPrimary)
                    Text("One place to run operations, automate counts, and keep shrink under control.")
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(spacing: 8) {
                    InventoryModuleBadge(module: .automation, symbol: "sparkles.rectangle.stack.fill", size: 42)
                    Text("LIVE")
                        .font(Theme.font(10, weight: .bold))
                        .foregroundStyle(Theme.accentDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.accentSoft.opacity(0.6))
                        )
                }
            }
        }
        .padding(16)
        .inventoryCard(cornerRadius: 18, emphasis: 0.72)
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            ZStack {
                InventoryModuleBadge(module: .workspace, symbol: "person.fill", size: 48)
                Text(initials(authStore.displayName))
                    .font(Theme.font(12, weight: .bold))
                    .foregroundStyle(Theme.moduleVisual(.workspace).deepTint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(authStore.displayName)
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(authStore.email)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.62)
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspace Access")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                if authStore.memberships.isEmpty {
                    Text("No workspace memberships found.")
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Picker("Workspace", selection: workspaceSelection) {
                        ForEach(authStore.memberships) { membership in
                            Text("\(membership.workspaceName) • \(membership.role.title)")
                                .tag(membership.workspaceID)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Current role")
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(authStore.currentRole.title)
                        .font(Theme.font(12, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                }

                if authStore.canManageWorkspace {
                    TextField("", text: $newWorkspaceName, prompt: Theme.inputPrompt("New workspace name"))
                        .inventoryTextInputField(horizontalPadding: 12, verticalPadding: 10)

                    Button("Create Workspace") {
                        createWorkspace()
                    }
                    .inventoryPrimaryAction()
                    .disabled(newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: 0.36)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.52)
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Theme")
                        .font(Theme.font(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }

                Picker("Theme", selection: themeModeSelection) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(themeSummary(for: selectedThemeMode))
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: 0.36)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.52)
    }

    private var selectedThemeMode: ThemeMode {
        ThemeMode(rawValue: themeModeRawValue) ?? .vibrant
    }

    private var themeModeSelection: Binding<ThemeMode> {
        Binding(
            get: { selectedThemeMode },
            set: { themeModeRawValue = $0.rawValue }
        )
    }

    private func menuSection(
        title: String,
        systemImage: String,
        module: InventoryModule,
        sectionIndex: Int,
        rows: [MenuRow]
    ) -> some View {
        let moduleVisual = Theme.moduleVisual(module)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(moduleVisual.tint)
                Text(title)
                    .font(Theme.sectionFont())
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    menuRow(row)

                    if row.id != rows.last?.id {
                        Divider()
                            .background(Theme.subtleBorder)
                            .padding(.leading, 58)
                    }
                }
            }
            .inventoryCard(cornerRadius: 16, emphasis: 0.34)
        }
        .inventoryStaggered(index: sectionIndex)
    }

    @ViewBuilder
    private func menuRow(_ row: MenuRow) -> some View {
        if let destination = row.destination {
            NavigationLink {
                destinationView(destination)
            } label: {
                menuRowLabel(row)
            }
            .inventoryInteractiveRow()
        } else {
            Button {
                handleRowAction(row)
            } label: {
                menuRowLabel(row)
            }
            .inventoryInteractiveRow()
        }
    }

    private func menuRowLabel(_ row: MenuRow) -> some View {
        let moduleVisual = Theme.moduleVisual(row.module)
        return HStack(spacing: 12) {
            InventoryModuleBadge(module: row.module, symbol: row.systemImage, size: 34)
            Text(row.title)
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let badge = row.badge {
                Text(badge)
                    .font(Theme.font(10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Theme.moduleChipGradient(row.module))
                    )
                    .foregroundStyle(moduleVisual.deepTint)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }

    private func themeSummary(for mode: ThemeMode) -> String {
        switch mode {
        case .classic:
            return "Balanced teal palette with soft contrast and low visual noise."
        case .modern:
            return "Bold contrast with cooler blue gradients for focused workflows."
        case .vibrant:
            return "High-energy coral and plum blend with richer depth and visual punch."
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: MenuDestination) -> some View {
        switch destination {
        case .runShift:
            RunShiftView()
        case .dailyOpsBrief:
            DailyOpsBriefView()
        case .automationInbox:
            AutomationInboxView()
        case .integrationHub:
            IntegrationHubView()
        case .trustCenter:
            TrustCenterView()
        case .opsIntelligence:
            OpsIntelligenceView()
        case .zoneMission:
            ZoneMissionView()
        case .cyclePlanner:
            CycleCountPlannerView()
        case .kpiDashboard:
            KPIDashboardView()
        case .starterTemplates:
            StarterTemplatesView()
        case .workflows:
            WorkflowsView()
        case .exceptions:
            ExceptionFeedView()
        case .replenishment:
            ReplenishmentPlannerView()
        case .calculations:
            InventoryCalculationsView()
        }
    }

    private var workspaceSelection: Binding<UUID> {
        Binding(
            get: { authStore.activeWorkspaceID ?? authStore.memberships.first?.workspaceID ?? UUID() },
            set: { authStore.switchWorkspace(to: $0) }
        )
    }

    private func createWorkspace() {
        do {
            try authStore.createWorkspace(name: newWorkspaceName, role: .owner)
            newWorkspaceName = ""
            Haptics.success()
        } catch {
            showingInfo = (error as? LocalizedError)?.errorDescription ?? "Unable to create workspace."
        }
    }

    private func handleRowAction(_ row: MenuRow) {
        switch row.action {
        case .guidedHelp:
            guidanceStore.openGuideCenter()
            dismiss()
        case .signOut:
            authStore.signOut()
            dismiss()
        case .none:
            showingInfo = "\(row.title) will be available soon."
        }
    }

    private func initials(_ name: String) -> String {
        let tokens = name
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        if tokens.isEmpty {
            return "U"
        }
        return tokens.joined()
    }
}

private struct MenuRow: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    var badge: String? = nil
    var destination: MenuDestination? = nil
    var action: MenuRowAction? = nil
    var module: InventoryModule = .workspace
}

private enum MenuRowAction {
    case guidedHelp
    case signOut
}

private enum MenuDestination {
    case runShift
    case dailyOpsBrief
    case automationInbox
    case integrationHub
    case trustCenter
    case opsIntelligence
    case zoneMission
    case cyclePlanner
    case kpiDashboard
    case starterTemplates
    case workflows
    case exceptions
    case replenishment
    case calculations
}
