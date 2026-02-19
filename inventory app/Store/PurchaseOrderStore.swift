import Foundation
import Combine

@MainActor
final class PurchaseOrderStore: ObservableObject {
    @Published private(set) var orders: [PurchaseOrderDraft] = []

    private let defaults: UserDefaults
    private let storageKey = "inventory.purchase_orders.v1"
    private let sequenceKey = "inventory.purchase_orders.sequence"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    @discardableResult
    func createDraft(
        lines: [PurchaseOrderLine],
        workspaceID: UUID?,
        source: String = "manual",
        notes: String = ""
    ) -> PurchaseOrderDraft? {
        let normalizedLines = normalized(lines)
        guard !normalizedLines.isEmpty else { return nil }

        let order = buildDraft(
            lines: normalizedLines,
            workspaceID: workspaceID,
            source: source,
            notes: notes,
            createdAt: Date()
        )
        orders.insert(order, at: 0)
        persist()
        return order
    }

    @discardableResult
    func createDraftsGroupedBySupplier(
        lines: [PurchaseOrderLine],
        workspaceID: UUID?,
        source: String = "manual",
        notes: String = ""
    ) -> [PurchaseOrderDraft] {
        let normalizedLines = normalized(lines)
        guard !normalizedLines.isEmpty else { return [] }

        let grouped = Dictionary(grouping: normalizedLines) { line in
            let supplier = (line.preferredSupplier ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return supplier.isEmpty ? "Unassigned Supplier" : supplier
        }

        let supplierNames = grouped.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        let createdAt = Date()
        var drafts: [PurchaseOrderDraft] = []
        drafts.reserveCapacity(supplierNames.count)

        for supplierName in supplierNames {
            guard let supplierLines = grouped[supplierName] else { continue }
            let sortedLines = supplierLines.sorted {
                $0.itemName.localizedCaseInsensitiveCompare($1.itemName) == .orderedAscending
            }

            let supplierNote = "Supplier batch: \(supplierName)."
            let mergedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? supplierNote
                : "\(supplierNote) \(notes)"

            let draft = buildDraft(
                lines: sortedLines,
                workspaceID: workspaceID,
                source: source,
                notes: mergedNotes,
                createdAt: createdAt
            )
            drafts.append(draft)
        }

        for draft in drafts.reversed() {
            orders.insert(draft, at: 0)
        }
        persist()
        return drafts
    }

    @discardableResult
    func createEmptyDraft(
        workspaceID: UUID?,
        source: String = "manual",
        notes: String = ""
    ) -> PurchaseOrderDraft {
        let now = Date()
        let order = PurchaseOrderDraft(
            id: UUID(),
            reference: nextReference(),
            workspaceID: workspaceID,
            createdAt: now,
            updatedAt: now,
            status: .draft,
            source: source,
            notes: notes,
            lines: [],
            sentAt: nil,
            receivedAt: nil,
            lastReceivedAt: nil
        )
        orders.insert(order, at: 0)
        persist()
        return order
    }

    func updateStatus(orderID: UUID, status: PurchaseOrderStatus) {
        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return }
        let now = Date()
        orders[index].status = status
        orders[index].updatedAt = now

        switch status {
        case .draft:
            break
        case .sent:
            if orders[index].sentAt == nil {
                orders[index].sentAt = now
            }
        case .partial:
            orders[index].lastReceivedAt = now
            if orders[index].sentAt == nil {
                orders[index].sentAt = now
            }
        case .received:
            if orders[index].sentAt == nil {
                orders[index].sentAt = now
            }
            orders[index].receivedAt = now
            orders[index].lastReceivedAt = now
            for lineIndex in orders[index].lines.indices {
                let targetUnits = max(0, orders[index].lines[lineIndex].suggestedUnits)
                if orders[index].lines[lineIndex].receivedUnits < targetUnits {
                    orders[index].lines[lineIndex].receivedUnits = targetUnits
                }
            }
        }
        persist()
    }

    @discardableResult
    func applyReceipts(
        orderID: UUID,
        receivedByLineID: [UUID: Int64],
        receivedAt: Date = Date()
    ) -> PurchaseOrderDraft? {
        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return nil }
        guard !receivedByLineID.isEmpty else { return nil }

        var hasAppliedReceipt = false
        for lineIndex in orders[index].lines.indices {
            let lineID = orders[index].lines[lineIndex].id
            let receivedUnits = max(0, receivedByLineID[lineID] ?? 0)
            guard receivedUnits > 0 else { continue }
            hasAppliedReceipt = true
            orders[index].lines[lineIndex].receivedUnits += receivedUnits
        }

        guard hasAppliedReceipt else { return nil }

        if orders[index].sentAt == nil {
            orders[index].sentAt = receivedAt
        }
        orders[index].lastReceivedAt = receivedAt
        orders[index].updatedAt = receivedAt

        let isFullyReceived = orders[index].lines.allSatisfy { line in
            max(0, line.receivedUnits) >= max(0, line.suggestedUnits)
        }
        if isFullyReceived {
            orders[index].status = .received
            orders[index].receivedAt = receivedAt
        } else {
            orders[index].status = .partial
            orders[index].receivedAt = nil
        }

        let updatedOrder = orders[index]
        persist()
        return updatedOrder
    }

    func orders(for workspaceID: UUID?) -> [PurchaseOrderDraft] {
        guard let workspaceID else { return [] }
        return orders.filter { order in
            guard let scopedID = order.workspaceID else { return false }
            return scopedID == workspaceID
        }
    }

    func removeOrders(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard orders.indices.contains(index) else { continue }
            orders.remove(at: index)
        }
        persist()
    }

    func resetForUITesting() {
        orders = []
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: sequenceKey)
    }

    private func nextReference() -> String {
        var sequence = defaults.integer(forKey: sequenceKey)
        if sequence < 1000 {
            sequence = 1000
        }
        sequence += 1
        defaults.set(sequence, forKey: sequenceKey)
        return "PO-\(sequence)"
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(orders) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            orders = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let decoded = try? decoder.decode([PurchaseOrderDraft].self, from: data) else {
            orders = []
            return
        }

        orders = decoded.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.reference > rhs.reference
        }
    }

    private func normalized(_ lines: [PurchaseOrderLine]) -> [PurchaseOrderLine] {
        lines
            .filter { $0.suggestedUnits > 0 }
            .sorted {
                $0.itemName.localizedCaseInsensitiveCompare($1.itemName) == .orderedAscending
            }
    }

    private func buildDraft(
        lines: [PurchaseOrderLine],
        workspaceID: UUID?,
        source: String,
        notes: String,
        createdAt: Date
    ) -> PurchaseOrderDraft {
        PurchaseOrderDraft(
            id: UUID(),
            reference: nextReference(),
            workspaceID: workspaceID,
            createdAt: createdAt,
            updatedAt: createdAt,
            status: .draft,
            source: source,
            notes: notes,
            lines: lines,
            sentAt: nil,
            receivedAt: nil,
            lastReceivedAt: nil
        )
    }
}
