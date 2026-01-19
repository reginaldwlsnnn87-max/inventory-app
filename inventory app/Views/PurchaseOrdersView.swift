import SwiftUI

struct PurchaseOrdersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var orders: [PurchaseOrder] = [
        PurchaseOrder(reference: "PO-1024", itemCount: 18, status: "Draft"),
        PurchaseOrder(reference: "PO-1023", itemCount: 42, status: "Sent")
    ]

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    quickActions
                    ForEach(orders) { order in
                        orderCard(order)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Purchase Orders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("New") { addOrder() }
            }
        }
        .tint(Theme.accent)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create and track purchase orders in one place.")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Add items, send to vendors, and receive deliveries quickly.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            NavigationLink {
                PurchaseOrderAddItemsView()
            } label: {
                actionRow(title: "Add Items", subtitle: "Build a new purchase order")
            }
            NavigationLink {
                PurchaseOrderReceiveItemsView()
            } label: {
                actionRow(title: "Receive Items", subtitle: "Confirm deliveries and update counts")
            }
        }
    }

    private func actionRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func orderCard(_ order: PurchaseOrder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(order.reference)
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(order.status)
                    .font(Theme.font(11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Theme.accent.opacity(0.15))
                    )
                    .foregroundStyle(Theme.accent)
            }
            Text("\(order.itemCount) items")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func addOrder() {
        let newOrder = PurchaseOrder(reference: "PO-\(Int.random(in: 2000...9999))", itemCount: 0, status: "Draft")
        orders.insert(newOrder, at: 0)
        Haptics.tap()
    }
}

private struct PurchaseOrder: Identifiable {
    let id = UUID()
    let reference: String
    let itemCount: Int
    let status: String
}
