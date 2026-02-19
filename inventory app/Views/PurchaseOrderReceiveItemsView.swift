import SwiftUI
import CoreData

private enum ReceiveMode: String, CaseIterable, Identifiable {
    case purchaseOrder
    case quickReceive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .purchaseOrder:
            return "Purchase Order"
        case .quickReceive:
            return "Quick Receive"
        }
    }
}

private enum ReceiveAlert: Identifiable {
    case message(String)

    var id: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

struct PurchaseOrderReceiveItemsView: View {
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var platformStore: PlatformStore
    @EnvironmentObject private var purchaseOrderStore: PurchaseOrderStore
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var mode: ReceiveMode = .purchaseOrder
    @State private var selectedOrderID: UUID?
    @State private var quickReceived: [UUID: Int] = [:]
    @State private var poReceived: [UUID: Int] = [:]
    @State private var hasSeededQuick = false
    @State private var activeAlert: ReceiveAlert?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    modeCard

                    if mode == .purchaseOrder {
                        purchaseOrderSection
                    } else {
                        quickReceiveSection
                    }

                    applyButton
                }
                .padding(16)
            }
        }
        .navigationTitle("Receive Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .onAppear {
            seedQuickIfNeeded()
            initializeOrderSelectionIfNeeded()
        }
        .onChange(of: authStore.activeWorkspaceID) { _, _ in
            hasSeededQuick = false
            quickReceived = [:]
            poReceived = [:]
            selectedOrderID = nil
            seedQuickIfNeeded()
            initializeOrderSelectionIfNeeded()
        }
        .onChange(of: selectedOrderID) { _, newValue in
            guard let newValue,
                  let order = receivableOrders.first(where: { $0.id == newValue }) else {
                poReceived = [:]
                return
            }
            seedPOInputs(for: order)
        }
        .onChange(of: receivableOrders.map(\.id)) { _, ids in
            if let selectedOrderID, ids.contains(selectedOrderID) {
                return
            }
            selectedOrderID = ids.first
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .message(let message):
                return Alert(
                    title: Text("Receipts Applied"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var itemByID: [UUID: InventoryItemEntity] {
        Dictionary(uniqueKeysWithValues: workspaceItems.map { ($0.id, $0) })
    }

    private var receivableOrders: [PurchaseOrderDraft] {
        purchaseOrderStore.orders(for: authStore.activeWorkspaceID).filter { order in
            order.status == .sent || order.status == .partial
        }
    }

    private var selectedOrder: PurchaseOrderDraft? {
        guard let selectedOrderID else { return nil }
        return receivableOrders.first { $0.id == selectedOrderID }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log deliveries with fewer taps.")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Use Purchase Order mode for supplier-accurate receipts or Quick Receive for ad-hoc product drops.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private var modeCard: some View {
        sectionCard(title: "Mode") {
            Picker("Mode", selection: $mode) {
                ForEach(ReceiveMode.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var purchaseOrderSection: some View {
        VStack(spacing: 16) {
            sectionCard(title: "Select Purchase Order") {
                if receivableOrders.isEmpty {
                    Text("No Sent or Partially Received orders are available yet.")
                        .font(Theme.font(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Picker("Order", selection: Binding(
                        get: { selectedOrderID ?? receivableOrders.first?.id },
                        set: { selectedOrderID = $0 }
                    )) {
                        ForEach(receivableOrders) { order in
                            Text("\(order.reference) • \(supplierName(for: order))")
                                .tag(Optional(order.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let order = selectedOrder {
                        orderSummaryCard(order)
                    }
                }
            }

            if let order = selectedOrder {
                sectionCard(title: "Receipt Lines") {
                    if order.lines.isEmpty {
                        Text("This order has no lines to receive.")
                            .font(Theme.font(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(order.lines) { line in
                            lineRow(line)
                        }
                    }
                }
            }
        }
    }

    private var quickReceiveSection: some View {
        sectionCard(title: "Quick Receive") {
            if workspaceItems.isEmpty {
                Text("No inventory items in this workspace.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(workspaceItems) { item in
                    quickRow(for: item)
                }
            }
        }
    }

    private var applyButton: some View {
        Button {
            if mode == .purchaseOrder {
                applyPOReceipts()
            } else {
                applyQuickReceipts()
            }
        } label: {
            Text(mode == .purchaseOrder ? "Apply PO Receipts" : "Apply Quick Receipts")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isApplyDisabled)
    }

    private var isApplyDisabled: Bool {
        switch mode {
        case .purchaseOrder:
            guard selectedOrder != nil else { return true }
            return !poReceived.values.contains(where: { $0 > 0 })
        case .quickReceive:
            return !quickReceived.values.contains(where: { $0 > 0 })
        }
    }

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

    private func orderSummaryCard(_ order: PurchaseOrderDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(order.reference) • \(supplierName(for: order))")
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Status: \(order.status.rawValue) • Received \(order.totalReceivedUnits)/\(order.totalSuggestedUnits) units")
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .inventoryCard(cornerRadius: 12, emphasis: 0.18)
    }

    private func lineRow(_ line: PurchaseOrderLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.itemName)
                        .font(Theme.font(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(line.category.isEmpty ? "Uncategorized" : line.category)
                        .font(Theme.font(10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Fill Open") {
                    poReceived[line.id] = Int(max(0, line.openUnits))
                }
                .buttonStyle(.bordered)
                .font(Theme.font(10, weight: .semibold))
            }

            HStack(spacing: 10) {
                metricChip("Ordered", value: "\(line.suggestedUnits)")
                metricChip("Received", value: "\(line.receivedUnits)")
                metricChip("Open", value: "\(line.openUnits)")
            }

            TextField("Receive now", value: poBinding(for: line.id), format: .number)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .inventoryTextInputField()
        }
        .padding(12)
        .inventoryCard(cornerRadius: 12, emphasis: 0.2)
    }

    private func quickRow(for item: InventoryItemEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(Theme.font(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(item.category.isEmpty ? "Uncategorized" : item.category)
                        .font(Theme.font(10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("On hand \(item.totalUnitsOnHand)")
                    .font(Theme.font(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            TextField("Received units", value: quickBinding(for: item.id), format: .number)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .inventoryTextInputField()
        }
        .padding(12)
        .inventoryCard(cornerRadius: 12, emphasis: 0.2)
    }

    private func metricChip(_ title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(Theme.font(9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Theme.cardBackground.opacity(0.78))
        )
        .overlay(
            Capsule().stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func initializeOrderSelectionIfNeeded() {
        if !receivableOrders.isEmpty {
            mode = .purchaseOrder
            if selectedOrderID == nil {
                selectedOrderID = receivableOrders.first?.id
            }
            if let order = selectedOrder {
                seedPOInputs(for: order)
            }
        } else {
            mode = .quickReceive
        }
    }

    private func seedQuickIfNeeded() {
        guard !hasSeededQuick else { return }
        hasSeededQuick = true
        var seed: [UUID: Int] = [:]
        for item in workspaceItems {
            seed[item.id] = 0
        }
        quickReceived = seed
    }

    private func seedPOInputs(for order: PurchaseOrderDraft) {
        var seed: [UUID: Int] = [:]
        for line in order.lines {
            seed[line.id] = Int(max(0, line.openUnits))
        }
        poReceived = seed
    }

    private func poBinding(for lineID: UUID) -> Binding<Int> {
        Binding(
            get: { poReceived[lineID] ?? 0 },
            set: { poReceived[lineID] = max(0, $0) }
        )
    }

    private func quickBinding(for itemID: UUID) -> Binding<Int> {
        Binding(
            get: { quickReceived[itemID] ?? 0 },
            set: { quickReceived[itemID] = max(0, $0) }
        )
    }

    private func applyQuickReceipts() {
        let now = Date()
        var updatedItems = 0
        var totalUnits: Int64 = 0

        for item in workspaceItems {
            let added = Int64(max(0, quickReceived[item.id] ?? 0))
            guard added > 0 else { continue }
            item.applyTotalUnits(item.totalUnitsOnHand + added)
            item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
            item.updatedAt = now
            platformStore.logReceipt(
                item: item,
                units: added,
                actorName: authStore.displayName,
                workspaceID: authStore.activeWorkspaceID,
                source: "quick-receive"
            )
            updatedItems += 1
            totalUnits += added
            quickReceived[item.id] = 0
        }

        dataController.save()
        Haptics.success()
        activeAlert = .message("Applied \(totalUnits) units across \(updatedItems) item(s).")
    }

    private func applyPOReceipts() {
        guard let order = selectedOrder else { return }

        var receivedByLineID: [UUID: Int64] = [:]
        var itemReceiptTotals: [UUID: Int64] = [:]
        var receivedLineCount = 0
        var totalUnits: Int64 = 0

        for line in order.lines {
            let enteredUnits = Int64(max(0, poReceived[line.id] ?? 0))
            guard enteredUnits > 0 else { continue }
            receivedByLineID[line.id] = enteredUnits
            itemReceiptTotals[line.itemID, default: 0] += enteredUnits
            receivedLineCount += 1
            totalUnits += enteredUnits
        }

        guard !receivedByLineID.isEmpty else { return }

        let now = Date()
        for (itemID, addedUnits) in itemReceiptTotals {
            guard let item = itemByID[itemID] else { continue }
            item.applyTotalUnits(item.totalUnitsOnHand + addedUnits)
            item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
            item.updatedAt = now
            platformStore.logReceipt(
                item: item,
                units: addedUnits,
                actorName: authStore.displayName,
                workspaceID: authStore.activeWorkspaceID,
                source: "po-receive",
                reason: "PO \(order.reference)"
            )
        }

        let updatedOrder = purchaseOrderStore.applyReceipts(
            orderID: order.id,
            receivedByLineID: receivedByLineID,
            receivedAt: now
        )

        dataController.save()
        Haptics.success()

        if let updatedOrder {
            if updatedOrder.status == .received {
                activeAlert = .message("\(updatedOrder.reference) fully received. Applied \(totalUnits) units across \(receivedLineCount) line(s).")
            } else {
                activeAlert = .message("\(updatedOrder.reference) updated to Partially Received with \(totalUnits) units applied.")
            }
        } else {
            activeAlert = .message("Applied \(totalUnits) units across \(receivedLineCount) line(s).")
        }

        poReceived = [:]
        let remainingOrders = receivableOrders
        if remainingOrders.contains(where: { $0.id == order.id }),
           let freshOrder = remainingOrders.first(where: { $0.id == order.id }) {
            selectedOrderID = freshOrder.id
            seedPOInputs(for: freshOrder)
        } else {
            selectedOrderID = remainingOrders.first?.id
            if let nextOrder = remainingOrders.first {
                seedPOInputs(for: nextOrder)
            }
        }
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
}
