import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PurchaseOrdersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseOrderStore: PurchaseOrderStore
    @EnvironmentObject private var authStore: AuthStore
    @State private var copyFeedback: String?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    supplierPerformanceCard
                    quickActions
                    if workspaceOrders.isEmpty {
                        emptyStateCard
                    } else {
                        ForEach(workspaceOrders) { order in
                            orderCard(order)
                        }
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
                    .disabled(!authStore.canManagePurchasing)
            }
        }
        .tint(Theme.accent)
        .alert(
            "Copied",
            isPresented: Binding(
                get: { copyFeedback != nil },
                set: { if !$0 { copyFeedback = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                copyFeedback = nil
            }
        } message: {
            Text(copyFeedback ?? "")
        }
    }

    private var workspaceOrders: [PurchaseOrderDraft] {
        purchaseOrderStore.orders(for: authStore.activeWorkspaceID)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create and track purchase orders in one place.")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Draft orders can be generated directly from Replenishment Planner, then sent and received here.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private var supplierPerformanceCard: some View {
        let onTime = onTimePerformance
        return VStack(alignment: .leading, spacing: 10) {
            Text("Supplier Performance")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 2)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    performanceMetricTile(
                        title: "On-Time",
                        value: onTime.rateText,
                        tint: onTime.rate >= 0.85 ? .green : .orange
                    )
                    performanceMetricTile(
                        title: "Late Open",
                        value: "\(lateOpenOrderCount)",
                        tint: lateOpenOrderCount == 0 ? Theme.textSecondary : .red
                    )
                    performanceMetricTile(
                        title: "Avg Delay",
                        value: averageDelayText,
                        tint: Theme.accentDeep
                    )
                }

                Text("On-time compares actual receipt date vs expected lead time + variance from PO lines.")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: 0.24)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("No purchase orders yet")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Open Replenishment Planner and tap Create Draft PO to auto-build your first order.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.28)
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
        .inventoryCard(cornerRadius: 16, emphasis: 0.34)
    }

    private func orderCard(_ order: PurchaseOrderDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(order.reference)
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(order.status.rawValue)
                    .font(Theme.font(11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Theme.accentSoft.opacity(0.45))
                    )
                    .foregroundStyle(Theme.accentDeep)
            }

            Text("\(order.itemCount) items • \(order.totalSuggestedUnits) units")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Text("Source: \(order.source.capitalized) • \(order.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            Text("Received \(order.totalReceivedUnits)/\(order.totalSuggestedUnits) units")
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            ProgressView(value: order.fulfillmentProgress)
                .tint(order.status == .received ? .green : Theme.accent)

            if let timeline = orderTimelineText(order) {
                Text(timeline)
                    .font(Theme.font(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            if !order.lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(order.lines.prefix(3)) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lineSummaryText(line))
                                .font(Theme.font(11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            if let metadata = lineSupplierMetadataText(line) {
                                Text(metadata)
                                    .font(Theme.font(10, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    if order.lines.count > 3 {
                        Text("+ \(order.lines.count - 3) more items")
                            .font(Theme.font(11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            HStack(spacing: 8) {
                statusButton(order, status: .draft)
                statusButton(order, status: .sent)
                statusButton(order, status: .received)
                Spacer()
            }

            HStack(spacing: 8) {
                copyButton(
                    title: "Copy PO",
                    systemImage: "doc.on.doc",
                    action: { copyOrderText(order) }
                )
                copyButton(
                    title: "Copy CSV",
                    systemImage: "tablecells",
                    action: { copyOrderCSV(order) }
                )
                ShareLink(item: orderTextPayload(order)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(Theme.font(11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.28)
    }

    private func statusButton(_ order: PurchaseOrderDraft, status: PurchaseOrderStatus) -> some View {
        Button(status.rawValue) {
            guard authStore.canManagePurchasing else { return }
            purchaseOrderStore.updateStatus(orderID: order.id, status: status)
            Haptics.tap()
        }
        .buttonStyle(.bordered)
        .tint(order.status == status ? Theme.accent : Theme.textSecondary)
        .disabled(!authStore.canManagePurchasing)
    }

    private func copyButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.font(11, weight: .semibold))
        }
        .buttonStyle(.bordered)
    }

    private func lineSummaryText(_ line: PurchaseOrderLine) -> String {
        "• \(line.itemName): \(line.receivedUnits)/\(line.suggestedUnits) units"
    }

    private func lineSupplierMetadataText(_ line: PurchaseOrderLine) -> String? {
        let supplier = line.preferredSupplier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sku = line.supplierSKU?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let moq = line.minimumOrderQuantity ?? 0
        let casePack = line.reorderCasePack ?? 0
        let variance = line.leadTimeVarianceDays ?? 0

        var parts: [String] = []
        if !supplier.isEmpty {
            parts.append("Vendor \(supplier)")
        }
        if !sku.isEmpty {
            parts.append("SKU \(sku)")
        }
        if moq > 0 {
            parts.append("MOQ \(moq)")
        }
        if casePack > 0 {
            parts.append("Pack \(casePack)")
        }
        if variance > 0 {
            parts.append("LT ±\(variance)d")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }

    private func addOrder() {
        guard authStore.canManagePurchasing else { return }
        _ = purchaseOrderStore.createEmptyDraft(
            workspaceID: authStore.activeWorkspaceID,
            source: "manual"
        )
        Haptics.tap()
    }

    private func copyOrderText(_ order: PurchaseOrderDraft) {
        let text = orderTextPayload(order)
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        copyFeedback = "PO text for \(order.reference) copied."
    }

    private func copyOrderCSV(_ order: PurchaseOrderDraft) {
        let csv = orderCSVPayload(order)
        #if canImport(UIKit)
        UIPasteboard.general.string = csv
        #endif
        copyFeedback = "PO CSV for \(order.reference) copied."
    }

    private func supplierName(for order: PurchaseOrderDraft) -> String {
        let supplierNames = Set(
            order.lines.compactMap { line in
                let trimmed = (line.preferredSupplier ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        )
        if supplierNames.isEmpty {
            return "Unassigned Supplier"
        }
        if supplierNames.count == 1 {
            return supplierNames.first ?? "Unassigned Supplier"
        }
        return "Multiple Suppliers"
    }

    private func orderTextPayload(_ order: PurchaseOrderDraft) -> String {
        let supplier = supplierName(for: order)
        let header = [
            "Purchase Order \(order.reference)",
            "Supplier: \(supplier)",
            "Status: \(order.status.rawValue)",
            "Created: \(order.createdAt.formatted(date: .abbreviated, time: .omitted))",
            "Sent: \(order.sentAt?.formatted(date: .abbreviated, time: .omitted) ?? "-")",
            "Received: \(order.receivedAt?.formatted(date: .abbreviated, time: .omitted) ?? "-")",
            ""
        ]

        let lines = order.lines.enumerated().map { index, line in
            let sku = (line.supplierSKU ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let skuText = sku.isEmpty ? "" : " (SKU: \(sku))"
            return "\(index + 1). \(line.itemName)\(skuText) - Received \(line.receivedUnits) / Ordered \(line.suggestedUnits)"
        }

        let totals = [
            "",
            "Total Items: \(order.itemCount)",
            "Total Units: \(order.totalSuggestedUnits)"
        ]

        return (header + lines + totals).joined(separator: "\n")
    }

    private func orderCSVPayload(_ order: PurchaseOrderDraft) -> String {
        let supplier = supplierName(for: order)
        let createdAtValue = order.createdAt.ISO8601Format()
        let headers = [
            "order_reference",
            "supplier",
            "status",
            "created_at",
            "sent_at",
            "received_at",
            "item_name",
            "supplier_sku",
            "category",
            "suggested_units",
            "received_units",
            "open_units",
            "reorder_point",
            "on_hand_units",
            "lead_time_days",
            "forecast_daily_demand",
            "minimum_order_quantity",
            "reorder_case_pack",
            "lead_time_variance_days"
        ]

        var rows: [String] = []
        rows.reserveCapacity(order.lines.count)
        for line in order.lines {
            let fields = csvFields(
                for: line,
                order: order,
                supplier: supplier,
                createdAtValue: createdAtValue,
                sentAtValue: order.sentAt?.ISO8601Format() ?? "",
                receivedAtValue: order.receivedAt?.ISO8601Format() ?? ""
            )
            rows.append(fields.map(csvEscaped).joined(separator: ","))
        }

        return ([headers.map(csvEscaped).joined(separator: ",")] + rows)
            .joined(separator: "\n")
    }

    private func csvFields(
        for line: PurchaseOrderLine,
        order: PurchaseOrderDraft,
        supplier: String,
        createdAtValue: String,
        sentAtValue: String,
        receivedAtValue: String
    ) -> [String] {
        [
            order.reference,
            supplier,
            order.status.rawValue,
            createdAtValue,
            sentAtValue,
            receivedAtValue,
            line.itemName,
            line.supplierSKU ?? "",
            line.category,
            String(line.suggestedUnits),
            String(line.receivedUnits),
            String(line.openUnits),
            String(line.reorderPoint),
            String(line.onHandUnits),
            String(line.leadTimeDays),
            String(format: "%.3f", line.forecastDailyDemand),
            String(line.minimumOrderQuantity ?? 0),
            String(line.reorderCasePack ?? 0),
            String(line.leadTimeVarianceDays ?? 0)
        ]
    }

    private func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func performanceMetricTile(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var lateOpenOrderCount: Int {
        let now = Date()
        return workspaceOrders.filter { order in
            guard order.status == .sent || order.status == .partial else { return false }
            guard let expectedDate = expectedArrivalDate(for: order, fallbackFrom: order.sentAt ?? order.createdAt) else {
                return false
            }
            return expectedDate < now
        }.count
    }

    private var onTimePerformance: (rate: Double, rateText: String) {
        let completed = workspaceOrders.filter { order in
            order.status == .received && order.receivedAt != nil && (order.sentAt ?? order.createdAt) <= (order.receivedAt ?? Date.distantFuture)
        }
        guard !completed.isEmpty else {
            return (0, "-")
        }

        let onTimeCount = completed.filter { order in
            guard let receivedAt = order.receivedAt else { return false }
            guard let expectedDate = expectedArrivalDate(for: order, fallbackFrom: order.sentAt ?? order.createdAt) else {
                return true
            }
            return receivedAt <= expectedDate
        }.count

        let rate = Double(onTimeCount) / Double(completed.count)
        let percent = Int((rate * 100).rounded())
        return (rate, "\(percent)%")
    }

    private var averageDelayText: String {
        let completed = workspaceOrders.filter { order in
            order.status == .received && order.receivedAt != nil
        }
        guard !completed.isEmpty else { return "-" }

        var delayDays: [Int] = []
        delayDays.reserveCapacity(completed.count)
        for order in completed {
            guard let receivedAt = order.receivedAt else { continue }
            guard let expectedDate = expectedArrivalDate(for: order, fallbackFrom: order.sentAt ?? order.createdAt) else {
                continue
            }
            let days = Calendar.current.dateComponents([.day], from: expectedDate, to: receivedAt).day ?? 0
            if days > 0 {
                delayDays.append(days)
            }
        }
        guard !delayDays.isEmpty else { return "0d" }
        let avg = Double(delayDays.reduce(0, +)) / Double(delayDays.count)
        return "\(Int(avg.rounded()))d"
    }

    private func expectedArrivalDate(for order: PurchaseOrderDraft, fallbackFrom baseDate: Date) -> Date? {
        let leadDays = order.lines.map { max(0, Int($0.leadTimeDays)) }.max() ?? 0
        let variance = order.lines.map { max(0, Int($0.leadTimeVarianceDays ?? 0)) }.max() ?? 0
        let totalDays = leadDays + variance
        guard totalDays > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: totalDays, to: baseDate)
    }

    private func orderTimelineText(_ order: PurchaseOrderDraft) -> String? {
        var parts: [String] = []
        if let sentAt = order.sentAt {
            parts.append("Sent \(sentAt.formatted(date: .abbreviated, time: .omitted))")
        }
        if let receivedAt = order.receivedAt {
            parts.append("Received \(receivedAt.formatted(date: .abbreviated, time: .omitted))")
        } else if let lastReceivedAt = order.lastReceivedAt {
            parts.append("Last receipt \(lastReceivedAt.formatted(date: .abbreviated, time: .omitted))")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }
}
