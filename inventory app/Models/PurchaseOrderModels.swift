import Foundation

enum PurchaseOrderStatus: String, Codable, CaseIterable {
    case draft = "Draft"
    case sent = "Sent"
    case partial = "Partially Received"
    case received = "Received"

    var sortOrder: Int {
        switch self {
        case .draft:
            return 0
        case .sent:
            return 1
        case .partial:
            return 2
        case .received:
            return 3
        }
    }
}

struct PurchaseOrderLine: Identifiable, Codable, Hashable {
    let id: UUID
    let itemID: UUID
    var itemName: String
    var category: String
    var suggestedUnits: Int64
    var reorderPoint: Int64
    var onHandUnits: Int64
    var leadTimeDays: Int64
    var forecastDailyDemand: Double
    var preferredSupplier: String?
    var supplierSKU: String?
    var minimumOrderQuantity: Int64?
    var reorderCasePack: Int64?
    var leadTimeVarianceDays: Int64?
    var receivedUnits: Int64

    init(
        id: UUID = UUID(),
        itemID: UUID,
        itemName: String,
        category: String,
        suggestedUnits: Int64,
        reorderPoint: Int64,
        onHandUnits: Int64,
        leadTimeDays: Int64,
        forecastDailyDemand: Double,
        preferredSupplier: String? = nil,
        supplierSKU: String? = nil,
        minimumOrderQuantity: Int64? = nil,
        reorderCasePack: Int64? = nil,
        leadTimeVarianceDays: Int64? = nil,
        receivedUnits: Int64 = 0
    ) {
        self.id = id
        self.itemID = itemID
        self.itemName = itemName
        self.category = category
        self.suggestedUnits = max(0, suggestedUnits)
        self.reorderPoint = max(0, reorderPoint)
        self.onHandUnits = max(0, onHandUnits)
        self.leadTimeDays = max(0, leadTimeDays)
        self.forecastDailyDemand = max(0, forecastDailyDemand)
        self.preferredSupplier = preferredSupplier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.supplierSKU = supplierSKU?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.minimumOrderQuantity = minimumOrderQuantity.map { max(0, $0) }
        self.reorderCasePack = reorderCasePack.map { max(0, $0) }
        self.leadTimeVarianceDays = leadTimeVarianceDays.map { max(0, $0) }
        self.receivedUnits = max(0, receivedUnits)
    }

    var openUnits: Int64 {
        max(0, suggestedUnits - max(0, receivedUnits))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case itemID
        case itemName
        case category
        case suggestedUnits
        case reorderPoint
        case onHandUnits
        case leadTimeDays
        case forecastDailyDemand
        case preferredSupplier
        case supplierSKU
        case minimumOrderQuantity
        case reorderCasePack
        case leadTimeVarianceDays
        case receivedUnits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let itemID = try container.decode(UUID.self, forKey: .itemID)
        let itemName = try container.decodeIfPresent(String.self, forKey: .itemName) ?? ""
        let category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        let suggestedUnits = try container.decodeIfPresent(Int64.self, forKey: .suggestedUnits) ?? 0
        let reorderPoint = try container.decodeIfPresent(Int64.self, forKey: .reorderPoint) ?? 0
        let onHandUnits = try container.decodeIfPresent(Int64.self, forKey: .onHandUnits) ?? 0
        let leadTimeDays = try container.decodeIfPresent(Int64.self, forKey: .leadTimeDays) ?? 0
        let forecastDailyDemand = try container.decodeIfPresent(Double.self, forKey: .forecastDailyDemand) ?? 0
        let preferredSupplier = try container.decodeIfPresent(String.self, forKey: .preferredSupplier)
        let supplierSKU = try container.decodeIfPresent(String.self, forKey: .supplierSKU)
        let minimumOrderQuantity = try container.decodeIfPresent(Int64.self, forKey: .minimumOrderQuantity)
        let reorderCasePack = try container.decodeIfPresent(Int64.self, forKey: .reorderCasePack)
        let leadTimeVarianceDays = try container.decodeIfPresent(Int64.self, forKey: .leadTimeVarianceDays)
        let receivedUnits = try container.decodeIfPresent(Int64.self, forKey: .receivedUnits) ?? 0

        self.init(
            id: id,
            itemID: itemID,
            itemName: itemName,
            category: category,
            suggestedUnits: suggestedUnits,
            reorderPoint: reorderPoint,
            onHandUnits: onHandUnits,
            leadTimeDays: leadTimeDays,
            forecastDailyDemand: forecastDailyDemand,
            preferredSupplier: preferredSupplier,
            supplierSKU: supplierSKU,
            minimumOrderQuantity: minimumOrderQuantity,
            reorderCasePack: reorderCasePack,
            leadTimeVarianceDays: leadTimeVarianceDays,
            receivedUnits: receivedUnits
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(itemID, forKey: .itemID)
        try container.encode(itemName, forKey: .itemName)
        try container.encode(category, forKey: .category)
        try container.encode(suggestedUnits, forKey: .suggestedUnits)
        try container.encode(reorderPoint, forKey: .reorderPoint)
        try container.encode(onHandUnits, forKey: .onHandUnits)
        try container.encode(leadTimeDays, forKey: .leadTimeDays)
        try container.encode(forecastDailyDemand, forKey: .forecastDailyDemand)
        try container.encodeIfPresent(preferredSupplier, forKey: .preferredSupplier)
        try container.encodeIfPresent(supplierSKU, forKey: .supplierSKU)
        try container.encodeIfPresent(minimumOrderQuantity, forKey: .minimumOrderQuantity)
        try container.encodeIfPresent(reorderCasePack, forKey: .reorderCasePack)
        try container.encodeIfPresent(leadTimeVarianceDays, forKey: .leadTimeVarianceDays)
        try container.encode(receivedUnits, forKey: .receivedUnits)
    }
}

struct PurchaseOrderDraft: Identifiable, Codable, Hashable {
    let id: UUID
    var reference: String
    var workspaceID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var status: PurchaseOrderStatus
    var source: String
    var notes: String
    var lines: [PurchaseOrderLine]
    var sentAt: Date?
    var receivedAt: Date?
    var lastReceivedAt: Date?

    var itemCount: Int {
        lines.count
    }

    var totalSuggestedUnits: Int64 {
        lines.reduce(0) { partial, line in
            partial + max(0, line.suggestedUnits)
        }
    }

    var totalReceivedUnits: Int64 {
        lines.reduce(0) { partial, line in
            partial + max(0, line.receivedUnits)
        }
    }

    var openUnits: Int64 {
        max(0, totalSuggestedUnits - totalReceivedUnits)
    }

    var fulfillmentProgress: Double {
        guard totalSuggestedUnits > 0 else { return 0 }
        return min(1, Double(totalReceivedUnits) / Double(totalSuggestedUnits))
    }
}
