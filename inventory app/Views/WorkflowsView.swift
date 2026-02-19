import SwiftUI

struct WorkflowsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingInfo: String?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Workflows")
                        .font(Theme.titleFont())
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 4)

                    ForEach(workflowCards) { card in
                        workflowCard(card)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Workflows")
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

    private func workflowCard(_ card: WorkflowCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            workflowHeader(card)

            if !card.actions.isEmpty {
                Divider()
                    .background(Theme.subtleBorder)
                ForEach(card.actions) { action in
                    workflowActionRow(action)
                }
            }
        }
        .padding(16)
        .inventoryCard(cornerRadius: 18, emphasis: card.badge == nil ? 0.24 : 0.52)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func workflowHeader(_ card: WorkflowCard) -> some View {
        if let destination = card.destination {
            NavigationLink {
                destinationView(destination)
            } label: {
                headerContent(card)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                showingInfo = "\(card.title) will be available soon."
            } label: {
                headerContent(card)
            }
            .buttonStyle(.plain)
        }
    }

    private func headerContent(_ card: WorkflowCard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(card.title)
                        .font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let badge = card.badge {
                        Text(badge)
                            .font(Theme.font(10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Theme.accentSoft.opacity(0.58))
                            )
                            .foregroundStyle(Theme.accentDeep)
                    }
                }
                Text(card.description)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private func workflowActionRow(_ action: WorkflowAction) -> some View {
        if let destination = action.destination {
            NavigationLink {
                destinationView(destination)
            } label: {
                actionRowContent(action)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                showingInfo = "\(action.title) will be available soon."
            } label: {
                actionRowContent(action)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionRowContent(_ action: WorkflowAction) -> some View {
        HStack {
            Text(action.title)
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let badge = action.badge {
                Text(badge)
                    .font(Theme.font(10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Theme.accentSoft.opacity(0.58))
                    )
                    .foregroundStyle(Theme.accentDeep)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func destinationView(_ destination: WorkflowDestination) -> some View {
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
        case .starterTemplates:
            StarterTemplatesView()
        case .kpiDashboard:
            KPIDashboardView()
        case .exceptions:
            ExceptionFeedView()
        case .replenishment:
            ReplenishmentPlannerView()
        case .stockCounts:
            StockCountsView()
        case .pickLists:
            PickListsView()
        case .purchaseOrders:
            PurchaseOrdersView()
        case .addItems:
            PurchaseOrderAddItemsView()
        case .receiveItems:
            PurchaseOrderReceiveItemsView()
        case .calculations:
            InventoryCalculationsView()
        }
    }
}

private struct WorkflowCard: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let systemImage: String
    let badge: String?
    let actions: [WorkflowAction]
    let destination: WorkflowDestination?
}

private struct WorkflowAction: Identifiable {
    let id = UUID()
    let title: String
    let badge: String?
    let destination: WorkflowDestination?
}

private let workflowCards: [WorkflowCard] = [
    WorkflowCard(
        title: "Run Shift",
        description: "One-screen execution flow: count queue, exceptions, replenishment, done.",
        systemImage: "play.circle.fill",
        badge: "NEW",
        actions: [],
        destination: .runShift
    ),
    WorkflowCard(
        title: "Automation Inbox",
        description: "Autopilot task queue that generates count, replenishment, and shrink actions from live signals.",
        systemImage: "tray.full",
        badge: "NEW",
        actions: [],
        destination: .automationInbox
    ),
    WorkflowCard(
        title: "Integration Hub",
        description: "Run QuickBooks/Shopify sync jobs plus CSV import/export for real inventory data movement.",
        systemImage: "arrow.triangle.2.circlepath",
        badge: "NEW",
        actions: [],
        destination: .integrationHub
    ),
    WorkflowCard(
        title: "Trust Center",
        description: "Create backups, monitor audit history, and recover fast after import or count errors.",
        systemImage: "checkmark.shield",
        badge: "NEW",
        actions: [],
        destination: .trustCenter
    ),
    WorkflowCard(
        title: "Ops Intelligence",
        description: "Execute returns/adjustments and track owner-level impact on shrink and labor.",
        systemImage: "waveform.path.ecg.rectangle",
        badge: "NEW",
        actions: [],
        destination: .opsIntelligence
    ),
    WorkflowCard(
        title: "Daily Ops Brief",
        description: "Start each shift with an actionable queue built from real risk, stale counts, and data gaps.",
        systemImage: "checklist.checked",
        badge: "NEW",
        actions: [],
        destination: .dailyOpsBrief
    ),
    WorkflowCard(
        title: "Zone Mission",
        description: "Count one location at a time with a fast mission flow and automatic variance review.",
        systemImage: "map.fill",
        badge: "NEW",
        actions: [],
        destination: .zoneMission
    ),
    WorkflowCard(
        title: "KPI Dashboard",
        description: "Monitor stockout risk, days of cover, and dead stock from one operational dashboard.",
        systemImage: "chart.bar.doc.horizontal",
        badge: "NEW",
        actions: [],
        destination: .kpiDashboard
    ),
    WorkflowCard(
        title: "Starter Templates",
        description: "Pick a business type and instantly seed the workspace with practical starter SKUs.",
        systemImage: "wand.and.sparkles",
        badge: "NEW",
        actions: [],
        destination: .starterTemplates
    ),
    WorkflowCard(
        title: "Exception Feed",
        description: "Focus only on critical stock risks, stale counts, and missing data.",
        systemImage: "exclamationmark.bubble",
        badge: "NEW",
        actions: [],
        destination: .exceptions
    ),
    WorkflowCard(
        title: "Replenishment Planner",
        description: "Prioritize urgent SKUs, generate suggested order units, and copy a PO-ready plan.",
        systemImage: "chart.line.uptrend.xyaxis",
        badge: "NEW",
        actions: [],
        destination: .replenishment
    ),
    WorkflowCard(
        title: "Calculations Lab",
        description: "Learn reorder point, safety stock, EOQ, and turnover with live formulas.",
        systemImage: "function",
        badge: "NEW",
        actions: [],
        destination: .calculations
    ),
    WorkflowCard(
        title: "Stock Counts",
        description: "Run blind counts, auto-flag high variance, and require recount reason codes.",
        systemImage: "123.rectangle",
        badge: "NEW",
        actions: [],
        destination: .stockCounts
    ),
    WorkflowCard(
        title: "Pick Lists",
        description: "Create pick lists, assign them, and update quantities automatically.",
        systemImage: "list.clipboard",
        badge: "NEW",
        actions: [],
        destination: .pickLists
    ),
    WorkflowCard(
        title: "Purchase Orders",
        description: "Create, manage, and track purchase orders in one place.",
        systemImage: "cart",
        badge: nil,
        actions: [
            WorkflowAction(title: "Add Items", badge: "NEW", destination: .addItems),
            WorkflowAction(title: "Receive Items", badge: "NEW", destination: .receiveItems)
        ],
        destination: .purchaseOrders
    )
]

private enum WorkflowDestination {
    case runShift
    case automationInbox
    case integrationHub
    case trustCenter
    case opsIntelligence
    case dailyOpsBrief
    case zoneMission
    case kpiDashboard
    case starterTemplates
    case exceptions
    case replenishment
    case stockCounts
    case pickLists
    case purchaseOrders
    case addItems
    case receiveItems
    case calculations
}
