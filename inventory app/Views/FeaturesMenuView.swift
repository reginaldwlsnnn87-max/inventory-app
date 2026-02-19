import SwiftUI

struct FeaturesMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        ForEach(features) { feature in
                            featureCard(feature)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Features")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(Theme.accent)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Simple and fast inventory.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Tap any feature below for a quick reminder on how to use it.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.5)
    }

    private func featureCard(_ feature: FeatureInfo) -> some View {
        let isOpen = expanded == feature.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(feature.title)
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(feature.summary)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if isOpen {
                Text(feature.howTo)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: isOpen ? 0.44 : 0.2)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded = isOpen ? nil : feature.id
            }
        }
    }
}

private struct FeatureInfo: Identifiable {
    let id: String
    let title: String
    let summary: String
    let howTo: String
}

private let features: [FeatureInfo] = [
    FeatureInfo(
        id: "run-shift",
        title: "Run Shift",
        summary: "Single-screen shift workflow for count queue, exceptions, replenishment, and close-out.",
        howTo: "Open Run Shift from Quick Actions, Menu, or Workflows. Complete tasks top-to-bottom, then tap Complete Shift to lock progress and review value metrics."
    ),
    FeatureInfo(
        id: "accounts-workspaces",
        title: "Accounts + Workspaces",
        summary: "Sign in, assign roles, and scope inventory to the active workspace.",
        howTo: "Sign in from the auth screen, then open Menu → Workspace Access to switch workspaces or create a new one (owner only)."
    ),
    FeatureInfo(
        id: "guided-help",
        title: "Guided Help",
        summary: "Step-by-step walkthroughs plus replayable on-screen coach marks for new users.",
        howTo: "Open Guided Help from Menu or Quick Actions. Pick Add Item, Zone Mission, or Replenishment, then use Replay On-Screen Tips to highlight key controls on the home screen."
    ),
    FeatureInfo(
        id: "daily-ops-brief",
        title: "Daily Ops Brief",
        summary: "A shift-ready action queue with task tracking, team activity log, and 7-day completion trend.",
        howTo: "Open Daily Ops Brief from Menu, Quick Actions, or Workflows. Check off tasks as your team completes them, launch linked workflows in one tap, and review recent activity for accountability."
    ),
    FeatureInfo(
        id: "automation-inbox",
        title: "Automation Inbox",
        summary: "Offline autopilot that creates tasks for stale counts, replenishment risk, shrink watch, and data hygiene.",
        howTo: "Open Automation Inbox from Quick Actions, Menu, or Workflows. Keep Autopilot and Task Reminders on, choose a reminder window for your shift, and tap reminder notifications to jump straight into the linked workflow."
    ),
    FeatureInfo(
        id: "integration-hub",
        title: "Integration Hub",
        summary: "Central place for QuickBooks/Shopify sync jobs and CSV import/export.",
        howTo: "Open Integration Hub from Quick Actions, Menu, or Workflows. Run sync jobs, export workspace CSV for external systems, and import CSV updates safely with automatic pre-import backup."
    ),
    FeatureInfo(
        id: "trust-center",
        title: "Trust Center",
        summary: "Backups, audit trail, and controlled restore for safer operations.",
        howTo: "Open Trust Center and create a manual backup before risky bulk changes. Review audit events to see who changed what, and restore a backup if counts or imports go wrong."
    ),
    FeatureInfo(
        id: "ops-intelligence",
        title: "Ops Intelligence",
        summary: "Operational command view for receiving, returns, adjustments, and owner impact.",
        howTo: "Open Ops Intelligence to process returns, apply counted adjustments, and monitor owner-level impact metrics like labor time saved and shrink-risk response."
    ),
    FeatureInfo(
        id: "exception-feed",
        title: "Exception Feed",
        summary: "Shows only urgent issues: critical restocks, stale counts, and data gaps.",
        howTo: "Open Quick Actions or Workflows and launch Exception Feed. Work top to bottom, tap each action button, and clear critical items first."
    ),
    FeatureInfo(
        id: "starter-templates",
        title: "Starter Templates",
        summary: "Seeds your workspace with business-specific starter inventory in one tap.",
        howTo: "Open Starter Templates from Quick Actions, Workflows, or Menu. Pick your business type, preview SKUs, and apply to create missing items plus optional planning defaults."
    ),
    FeatureInfo(
        id: "kpi-dashboard",
        title: "KPI Dashboard",
        summary: "Tracks stockout risk, average days of cover, and dead stock percentage in real time.",
        howTo: "Open KPI Dashboard from Quick Actions, Workflows, or Menu. Start with Stockout Risk and Dead Stock, then open Replenishment Planner directly for fast action."
    ),
    FeatureInfo(
        id: "zone-mission",
        title: "Zone Mission",
        summary: "Runs fast location-based counts with progress tracking and variance review.",
        howTo: "Open Zone Mission, choose a zone, and start. Count one item at a time, then review high-variance items and log reasons before applying."
    ),
    FeatureInfo(
        id: "shelf-scan",
        title: "Shelf Scan",
        summary: "Snap a shelf photo, let the app detect labels, then confirm counts.",
        howTo: "Tap the camera icon, take a clear photo, then review the detected items. Tap any item to adjust counts and press Apply Counts."
    ),
    FeatureInfo(
        id: "quick-add",
        title: "Quick Add",
        summary: "Add an item fast with basic counts when you're in a hurry.",
        howTo: "Tap the bolt icon, fill in the essentials, and press Save. You can refine details later."
    ),
    FeatureInfo(
        id: "replenishment-planner",
        title: "Replenishment Planner",
        summary: "Shows urgent SKUs plus auto-reorder suggestions built from demand velocity, lead time, and safety stock.",
        howTo: "Open Replenishment Planner, start in Auto-Reorder Suggestions, review confidence and critical count, then tap Create Auto Draft PO. Use Log Usage to improve forecast quality over time."
    ),
    FeatureInfo(
        id: "smart-reorder",
        title: "Smart Reorder",
        summary: "Set daily usage, lead time, and safety stock to see reorder suggestions.",
        howTo: "Edit an item, enter usage, lead time, and safety stock under Reorder, then check the item row for the reorder target."
    ),
    FeatureInfo(
        id: "calculations-lab",
        title: "Calculations Lab",
        summary: "Learn reorder point, EOQ, safety stock, and turnover with live formulas and sliders.",
        howTo: "Open Calculations Lab, move the Scenario Simulator sliders to test assumptions, then tap Apply Scenario To Inputs to compare with live formulas."
    ),
    FeatureInfo(
        id: "barcode-scan",
        title: "Barcode Scan",
        summary: "Scan a barcode to find an item or create a new one.",
        howTo: "Tap the barcode icon or Quick Actions → Scan Barcode. If it matches, the item opens; if not, a new item is started."
    ),
    FeatureInfo(
        id: "workflows",
        title: "Workflows",
        summary: "Run guided flows for stock counts, pick lists, and purchase orders.",
        howTo: "Open the Menu, tap Workflows, and choose the flow you need."
    ),
    FeatureInfo(
        id: "stock-counts",
        title: "Stock Counts",
        summary: "Run blind first-pass counts, auto-trigger recounts on variance, and log shrink reasons.",
        howTo: "Open Stock Counts, keep Blind Count mode on, enter first-pass counts, then tap Run Variance Check. Recount flagged items and select a reason code before finalizing."
    ),
    FeatureInfo(
        id: "pick-lists",
        title: "Pick Lists",
        summary: "Create lists for items that need to be pulled.",
        howTo: "In Workflows, open Pick Lists and tap New to start a list."
    ),
    FeatureInfo(
        id: "purchase-orders",
        title: "Purchase Orders",
        summary: "Create and receive purchase orders to keep stock aligned.",
        howTo: "In Workflows, open Purchase Orders to add items or receive deliveries."
    ),
    FeatureInfo(
        id: "shift-modes",
        title: "Shift Modes",
        summary: "Open/Mid/Close sorts items to fit your shift workflow.",
        howTo: "Use the Shift control at the top to switch between Open, Mid, or Close sorting styles."
    ),
    FeatureInfo(
        id: "pin-items",
        title: "Pin Items",
        summary: "Pin high-priority items so they stay on top.",
        howTo: "Swipe an item from the left and tap Pin. Pinned items stay at the top of the list."
    ),
    FeatureInfo(
        id: "set-amount",
        title: "Set Amount",
        summary: "Swipe an item and set its exact count.",
        howTo: "Swipe an item to reveal Set, enter the exact count, and confirm."
    ),
    FeatureInfo(
        id: "notes",
        title: "Notes",
        summary: "Swipe an item to add notes for reminders or usage tips.",
        howTo: "Swipe an item, tap Note, type your reminder, and save."
    ),
    FeatureInfo(
        id: "search-filter",
        title: "Search + Filters",
        summary: "Search by name and filter by category to find items fast.",
        howTo: "Use the search bar for names, or tap the filter icon to select a category."
    ),
    FeatureInfo(
        id: "quick-actions",
        title: "Quick Actions",
        summary: "Open a single sheet to jump into common tasks.",
        howTo: "Tap the ellipsis button in the toolbar to open Quick Actions."
    ),
    FeatureInfo(
        id: "menu",
        title: "Menu",
        summary: "Access workflows, labels, reports, and account tools.",
        howTo: "Tap the Menu icon in the toolbar and choose a section."
    )
]
