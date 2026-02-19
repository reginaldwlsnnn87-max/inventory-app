import SwiftUI

struct QuickActionsView: View {
    let onAction: (QuickAction) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        quickLaunchHero
                            .inventoryStaggered(index: 0)
                        sectionCard(
                            title: "Start Shift in 3 Taps",
                            subtitle: "High-impact workflows to begin the day faster",
                            systemImage: "bolt.badge.clock.fill",
                            module: .counts,
                            sectionIndex: 1,
                            rows: [
                                ActionRowData(
                                    title: "Run Shift Workflow",
                                    subtitle: "Open the single-screen shift flow",
                                    systemImage: "play.circle.fill",
                                    module: .counts,
                                    action: {
                                        onAction(.runShift)
                                    }
                                ),
                                ActionRowData(
                                    title: "Run Daily Brief",
                                    subtitle: "Open today’s priority queue first",
                                    systemImage: "checklist.checked",
                                    module: .intelligence,
                                    action: {
                                        onAction(.dailyOpsBrief)
                                    }
                                ),
                                ActionRowData(
                                    title: "Fix Exceptions",
                                    subtitle: "Clear critical stock risks and stale counts",
                                    systemImage: "exclamationmark.bubble",
                                    module: .shrink,
                                    action: {
                                        onAction(.exceptions)
                                    }
                                ),
                                ActionRowData(
                                    title: "Count by Zone",
                                    subtitle: "Launch a guided location count mission",
                                    systemImage: "map.fill",
                                    module: .counts,
                                    action: {
                                        onAction(.zoneMission)
                                    }
                                ),
                                ActionRowData(
                                    title: "Cycle Count Planner",
                                    subtitle: "Queue highest-risk SKUs and finish counts faster",
                                    systemImage: "target",
                                    module: .counts,
                                    action: {
                                        onAction(.cyclePlanner)
                                    }
                                ),
                                ActionRowData(
                                    title: "Plan Replenishment",
                                    subtitle: "Prioritize urgent SKUs and suggested orders",
                                    systemImage: "chart.line.uptrend.xyaxis",
                                    module: .replenishment,
                                    action: {
                                        onAction(.replenishment)
                                    }
                                )
                            ]
                        )

                        sectionCard(
                            title: "Quick Quantity",
                            subtitle: "Count and adjust without losing your place",
                            systemImage: "plusminus.circle.fill",
                            module: .counts,
                            sectionIndex: 2,
                            rows: [
                                ActionRowData(
                                    title: "Stock In / Out",
                                    subtitle: "Tap an item, then use the quick buttons",
                                    systemImage: "plusminus",
                                    module: .counts,
                                    action: { onAction(.stockInOut) }
                                ),
                                ActionRowData(
                                    title: "Set Amount",
                                    subtitle: "Choose an item and set its exact count",
                                    systemImage: "pencil",
                                    module: .counts,
                                    action: {
                                        onAction(.setAmount)
                                    }
                                )
                            ]
                        )

                        sectionCard(
                            title: "Quick Add",
                            subtitle: "Capture new catalog items in seconds",
                            systemImage: "plus.circle.fill",
                            module: .catalog,
                            sectionIndex: 3,
                            rows: [
                                ActionRowData(
                                    title: "Add Item",
                                    subtitle: "Full item details",
                                    systemImage: "plus.circle",
                                    module: .catalog,
                                    action: {
                                        onAction(.addItem)
                                    }
                                ),
                                ActionRowData(
                                    title: "Quick Add",
                                    subtitle: "Faster add with essentials",
                                    systemImage: "bolt.fill",
                                    module: .catalog,
                                    action: {
                                        onAction(.quickAdd)
                                    }
                                )
                            ]
                        )

                        sectionCard(
                            title: "Smart Tools",
                            subtitle: "Automations and insights that reduce manual work",
                            systemImage: "sparkles.rectangle.stack.fill",
                            module: .automation,
                            sectionIndex: 4,
                            rows: [
                                ActionRowData(
                                    title: "Starter Templates",
                                    subtitle: "Seed your workspace with business-specific starter SKUs",
                                    systemImage: "wand.and.sparkles",
                                    module: .catalog,
                                    action: {
                                        onAction(.starterTemplates)
                                    }
                                ),
                                ActionRowData(
                                    title: "Daily Ops Brief",
                                    subtitle: "Get a one-screen action plan for today",
                                    systemImage: "checklist.checked",
                                    module: .intelligence,
                                    action: {
                                        onAction(.dailyOpsBrief)
                                    }
                                ),
                                ActionRowData(
                                    title: "Automation Inbox",
                                    subtitle: "Run autopilot tasks for counts and shrink control",
                                    systemImage: "tray.full",
                                    module: .automation,
                                    action: {
                                        onAction(.automationInbox)
                                    }
                                ),
                                ActionRowData(
                                    title: "Integration Hub",
                                    subtitle: "Run QuickBooks/Shopify sync jobs and CSV data flows",
                                    systemImage: "arrow.triangle.2.circlepath",
                                    module: .automation,
                                    action: {
                                        onAction(.integrationHub)
                                    }
                                ),
                                ActionRowData(
                                    title: "Trust Center",
                                    subtitle: "Create backups, view audit trail, and recover safely",
                                    systemImage: "checkmark.shield",
                                    module: .trust,
                                    action: {
                                        onAction(.trustCenter)
                                    }
                                ),
                                ActionRowData(
                                    title: "Ops Intelligence",
                                    subtitle: "Run returns/adjustments and track owner impact",
                                    systemImage: "waveform.path.ecg.rectangle",
                                    module: .intelligence,
                                    action: {
                                        onAction(.opsIntelligence)
                                    }
                                ),
                                ActionRowData(
                                    title: "KPI Dashboard",
                                    subtitle: "Track stockout risk, coverage, and dead stock in one view",
                                    systemImage: "chart.bar.doc.horizontal",
                                    module: .reports,
                                    action: {
                                        onAction(.kpiDashboard)
                                    }
                                ),
                                ActionRowData(
                                    title: "Zone Mission",
                                    subtitle: "Run fast location-based counts with progress and variance review",
                                    systemImage: "map.fill",
                                    module: .counts,
                                    action: {
                                        onAction(.zoneMission)
                                    }
                                ),
                                ActionRowData(
                                    title: "Guided Help",
                                    subtitle: "Step-by-step tours for key workflows",
                                    systemImage: "questionmark.bubble",
                                    module: .support,
                                    action: {
                                        onAction(.guidedHelp)
                                    }
                                ),
                                ActionRowData(
                                    title: "Exception Feed",
                                    subtitle: "See only urgent issues and resolve them fast",
                                    systemImage: "exclamationmark.bubble",
                                    module: .shrink,
                                    accessibilityID: "quickactions.row.exceptionFeed",
                                    action: {
                                        onAction(.exceptions)
                                    }
                                ),
                                ActionRowData(
                                    title: "Replenishment Planner",
                                    subtitle: "Prioritize urgent SKUs and copy an order plan",
                                    systemImage: "chart.line.uptrend.xyaxis",
                                    module: .replenishment,
                                    action: {
                                        onAction(.replenishment)
                                    }
                                ),
                                ActionRowData(
                                    title: "Calculations Lab",
                                    subtitle: "Practice reorder point, EOQ, and turnover live",
                                    systemImage: "function",
                                    module: .reports,
                                    action: {
                                        onAction(.calculations)
                                    }
                                ),
                                ActionRowData(
                                    title: "Scan Barcode",
                                    subtitle: "Find or create items by barcode",
                                    systemImage: "barcode.viewfinder",
                                    module: .catalog,
                                    action: {
                                        onAction(.barcodeScan)
                                    }
                                ),
                                ActionRowData(
                                    title: "Shelf Scan",
                                    subtitle: "Capture a shelf photo and confirm counts",
                                    systemImage: "camera.viewfinder",
                                    module: .counts,
                                    action: {
                                        onAction(.shelfScan)
                                    }
                                ),
                                ActionRowData(
                                    title: "Add Note",
                                    subtitle: "Attach a quick reminder to an item",
                                    systemImage: "note.text",
                                    module: .workspace,
                                    action: {
                                        onAction(.addNote)
                                    }
                                )
                            ]
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onAction(.close) }
                }
            }
            .tint(Theme.accent)
        }
    }

    private var quickLaunchHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick Launch")
                        .font(Theme.titleFont())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Tap once to run count flows, fix exceptions, and keep shelves healthy.")
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                InventoryModuleBadge(module: .automation, symbol: "scope", size: 40)
            }
        }
        .padding(16)
        .inventoryCard(cornerRadius: 20, emphasis: 0.7)
    }

    private func sectionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        module: InventoryModule,
        sectionIndex: Int,
        rows: [ActionRowData]
    ) -> some View {
        let moduleVisual = Theme.moduleVisual(module)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(moduleVisual.tint)
                    Text(title)
                        .font(Theme.sectionFont())
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(subtitle)
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { rowIndex, row in
                    Button(action: row.action) {
                        actionRow(row)
                    }
                    .inventoryInteractiveRow()
                    .accessibilityIdentifier(row.resolvedAccessibilityID)
                    .inventoryStaggered(index: rowIndex, baseDelay: 0.028, initialYOffset: 10)

                    if row.id != rows.last?.id {
                        Divider()
                            .background(Theme.subtleBorder)
                            .padding(.leading, 58)
                    }
                }
            }
            .inventoryCard(cornerRadius: 18, emphasis: 0.4)
        }
        .inventoryStaggered(index: sectionIndex)
    }

    private func actionRow(_ row: ActionRowData) -> some View {
        let moduleVisual = Theme.moduleVisual(row.module)
        return HStack(spacing: 12) {
            InventoryModuleBadge(module: row.module, symbol: row.systemImage, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(row.subtitle)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(moduleVisual.deepTint.opacity(0.75))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

private struct ActionRowData: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let module: InventoryModule
    let accessibilityID: String?
    let action: () -> Void

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        module: InventoryModule,
        accessibilityID: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.module = module
        self.accessibilityID = accessibilityID
        self.action = action
    }

    var resolvedAccessibilityID: String {
        if let accessibilityID {
            return accessibilityID
        }
        let normalized = title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "quickactions.row.\(normalized)"
    }
}

enum QuickAction {
    case runShift
    case stockInOut
    case setAmount
    case addItem
    case quickAdd
    case cyclePlanner
    case starterTemplates
    case dailyOpsBrief
    case automationInbox
    case integrationHub
    case trustCenter
    case opsIntelligence
    case kpiDashboard
    case zoneMission
    case guidedHelp
    case exceptions
    case replenishment
    case calculations
    case shelfScan
    case barcodeScan
    case addNote
    case close
}
