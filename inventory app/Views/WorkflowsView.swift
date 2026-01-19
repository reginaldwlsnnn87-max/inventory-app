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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
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
                                Capsule().fill(Color.red.opacity(0.85))
                            )
                            .foregroundStyle(.white)
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
                        Capsule().fill(Color.red.opacity(0.85))
                    )
                    .foregroundStyle(.white)
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
        title: "Stock Counts",
        description: "Count and verify inventory to keep records accurate.",
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
    case stockCounts
    case pickLists
    case purchaseOrders
    case addItems
    case receiveItems
}
