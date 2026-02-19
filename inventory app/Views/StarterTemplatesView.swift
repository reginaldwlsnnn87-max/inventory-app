import SwiftUI
import CoreData

private struct StarterTemplate: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let guidance: String
    let items: [StarterTemplateItem]
}

private struct StarterTemplateItem: Identifiable {
    let name: String
    let category: String
    let location: String
    let unitsPerCase: Int64
    let openingCases: Int64
    let openingUnits: Int64
    let averageDailyUsage: Double
    let leadTimeDays: Int64
    let safetyStockUnits: Int64

    var id: String { "\(category.lowercased())|\(name.lowercased())" }
}

private enum StarterTemplatesAlert: Identifiable {
    case permission
    case applied(created: Int, updated: Int, skipped: Int)

    var id: String {
        switch self {
        case .permission:
            return "permission"
        case .applied(let created, let updated, let skipped):
            return "applied-\(created)-\(updated)-\(skipped)"
        }
    }
}

struct StarterTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var authStore: AuthStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var selectedTemplateID = starterTemplates.first?.id ?? "retail"
    @State private var updateExistingPlanningData = true
    @State private var activeAlert: StarterTemplatesAlert?

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    templatePickerCard
                    summaryCard
                    previewCard
                    applyCard
                }
                .padding(16)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Starter Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .permission:
                return Alert(
                    title: Text("Permission Required"),
                    message: Text("Only owners and managers can apply starter templates."),
                    dismissButton: .default(Text("OK"))
                )
            case .applied(let created, let updated, let skipped):
                return Alert(
                    title: Text("Template Applied"),
                    message: Text("Created \(created) items • Updated \(updated) planning profiles • Skipped \(skipped) existing matches."),
                    dismissButton: .default(Text("Done"))
                )
            }
        }
    }

    private var selectedTemplate: StarterTemplate {
        starterTemplates.first(where: { $0.id == selectedTemplateID }) ?? starterTemplates[0]
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var templateCategoryCount: Int {
        Set(selectedTemplate.items.map { $0.category.lowercased() }).count
    }

    private var templateTotalUnits: Int64 {
        selectedTemplate.items.reduce(0) { total, item in
            total + item.openingCases * max(1, item.unitsPerCase) + max(0, item.openingUnits)
        }
    }

    private var templateAverageLeadTime: Double {
        guard !selectedTemplate.items.isEmpty else { return 0 }
        let total = selectedTemplate.items.reduce(0.0) { $0 + Double($1.leadTimeDays) }
        return total / Double(selectedTemplate.items.count)
    }

    private var previewItems: [StarterTemplateItem] {
        Array(selectedTemplate.items.prefix(10))
    }

    private var isApplyDisabled: Bool {
        selectedTemplate.items.isEmpty || !authStore.canManageCatalog
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Launch faster with business-ready starter inventory.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Pick your business type, seed common SKUs, then tune counts and demand with your real data.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }

    private var templatePickerCard: some View {
        sectionCard(title: "Business Type") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(starterTemplates) { template in
                        Button {
                            selectedTemplateID = template.id
                        } label: {
                            templateButton(template, isSelected: selectedTemplateID == template.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            Text(selectedTemplate.guidance)
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func templateButton(_ template: StarterTemplate, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: template.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                Text(template.title)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(template.subtitle)
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: 220, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(isSelected ? 0.98 : 0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Theme.accent : Theme.subtleBorder, lineWidth: isSelected ? 1.5 : 1)
        )
    }

    private var summaryCard: some View {
        sectionCard(title: "Template Summary") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                metricTile(title: "Starter SKUs", value: "\(selectedTemplate.items.count)", tint: Theme.accent)
                metricTile(title: "Categories", value: "\(templateCategoryCount)", tint: Theme.accentDeep)
                metricTile(title: "Opening Units", value: "\(templateTotalUnits)", tint: Theme.textPrimary)
                metricTile(title: "Avg Lead Time", value: "\(Int(templateAverageLeadTime.rounded()))d", tint: Theme.textSecondary)
            }
        }
    }

    private var previewCard: some View {
        sectionCard(title: "Preview Items") {
            ForEach(previewItems) { item in
                templateItemRow(item)
            }

            if selectedTemplate.items.count > previewItems.count {
                Text("Showing \(previewItems.count) of \(selectedTemplate.items.count) template items.")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func templateItemRow(_ item: StarterTemplateItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(item.category)
                    .font(Theme.font(10, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Theme.accentSoft.opacity(0.45))
                    )
            }

            HStack(spacing: 10) {
                detailChip("Opening", value: "\(item.openingCases)c + \(item.openingUnits)u")
                detailChip("Usage/day", value: formatted(item.averageDailyUsage))
                detailChip("Lead", value: "\(item.leadTimeDays)d")
                detailChip("Safety", value: "\(item.safetyStockUnits)")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var applyCard: some View {
        sectionCard(title: "Apply Template") {
            Toggle("Update planning defaults on matched items", isOn: $updateExistingPlanningData)
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)

            Text("Matched by item name + category inside the active workspace: \(authStore.activeWorkspaceName).")
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Button {
                applyTemplate()
            } label: {
                HStack {
                    Image(systemName: "wand.and.sparkles")
                    Text("Apply Starter Template")
                        .font(Theme.font(13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isApplyDisabled)
            .opacity(isApplyDisabled ? 0.55 : 1)
        }
    }

    @ViewBuilder
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
        .inventoryCard(cornerRadius: 16, emphasis: 0.42)
    }

    private func metricTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func detailChip(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.font(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func applyTemplate() {
        guard authStore.canManageCatalog else {
            activeAlert = .permission
            Haptics.tap()
            return
        }

        let now = Date()
        var createdCount = 0
        var updatedCount = 0
        var skippedCount = 0
        var lookup = Dictionary(
            uniqueKeysWithValues: workspaceItems.map { (templateKey(name: $0.name, category: $0.category), $0) }
        )

        for templateItem in selectedTemplate.items {
            let key = templateKey(name: templateItem.name, category: templateItem.category)

            if let existing = lookup[key] {
                if updateExistingPlanningData {
                    let didUpdate = applyPlanningDefaults(
                        to: existing,
                        templateItem: templateItem,
                        now: now
                    )
                    if didUpdate {
                        updatedCount += 1
                    } else {
                        skippedCount += 1
                    }
                } else {
                    skippedCount += 1
                }
                continue
            }

            let item = InventoryItemEntity(context: context)
            item.id = UUID()
            item.name = templateItem.name
            item.quantity = max(0, templateItem.openingCases)
            item.notes = "Starter template: \(selectedTemplate.title)"
            item.category = templateItem.category
            item.location = templateItem.location
            item.unitsPerCase = max(0, templateItem.unitsPerCase)
            item.looseUnits = max(0, templateItem.openingUnits)
            item.eachesPerUnit = 0
            item.looseEaches = 0
            item.isLiquid = false
            item.gallonFraction = 0
            item.isPinned = false
            item.barcode = ""
            item.averageDailyUsage = max(0, templateItem.averageDailyUsage)
            item.leadTimeDays = max(0, templateItem.leadTimeDays)
            item.safetyStockUnits = max(0, templateItem.safetyStockUnits)
            item.workspaceID = authStore.activeWorkspaceIDString()
            item.recentDemandSamples = ""
            item.setDailyDemandSamples(Array(repeating: max(0, templateItem.averageDailyUsage), count: 7))
            item.createdAt = now
            item.updatedAt = now

            lookup[key] = item
            createdCount += 1
        }

        dataController.save()
        Haptics.success()
        activeAlert = .applied(created: createdCount, updated: updatedCount, skipped: skippedCount)
    }

    private func applyPlanningDefaults(
        to item: InventoryItemEntity,
        templateItem: StarterTemplateItem,
        now: Date
    ) -> Bool {
        var changed = false

        if item.averageDailyUsage <= 0, templateItem.averageDailyUsage > 0 {
            item.averageDailyUsage = templateItem.averageDailyUsage
            changed = true
        }
        if item.leadTimeDays <= 0, templateItem.leadTimeDays > 0 {
            item.leadTimeDays = templateItem.leadTimeDays
            changed = true
        }
        if item.safetyStockUnits <= 0, templateItem.safetyStockUnits > 0 {
            item.safetyStockUnits = templateItem.safetyStockUnits
            changed = true
        }
        if item.unitsPerCase <= 0, templateItem.unitsPerCase > 0 {
            item.unitsPerCase = templateItem.unitsPerCase
            changed = true
        }
        if item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !templateItem.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.location = templateItem.location
            changed = true
        }
        if item.recentDemandSamples.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           templateItem.averageDailyUsage > 0 {
            item.setDailyDemandSamples(Array(repeating: templateItem.averageDailyUsage, count: 7))
            changed = true
        }

        if changed {
            item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
            item.updatedAt = now
        }
        return changed
    }

    private func templateKey(name: String, category: String) -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedName)|\(normalizedCategory)"
    }

    private func formatted(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.01 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

private let starterTemplates: [StarterTemplate] = [
    StarterTemplate(
        id: "retail",
        title: "Retail Store",
        subtitle: "General merchandise",
        systemImage: "bag.fill",
        guidance: "Use this for boutiques, convenience, and gift shops with mixed SKU velocity.",
        items: [
            StarterTemplateItem(name: "Bottled Water 24pk", category: "Beverages", location: "Aisle A", unitsPerCase: 24, openingCases: 8, openingUnits: 0, averageDailyUsage: 3.4, leadTimeDays: 3, safetyStockUnits: 36),
            StarterTemplateItem(name: "Soda 12oz Cans", category: "Beverages", location: "Aisle A", unitsPerCase: 24, openingCases: 10, openingUnits: 0, averageDailyUsage: 5.2, leadTimeDays: 3, safetyStockUnits: 48),
            StarterTemplateItem(name: "Granola Bars", category: "Snacks", location: "Aisle B", unitsPerCase: 48, openingCases: 6, openingUnits: 0, averageDailyUsage: 4.8, leadTimeDays: 5, safetyStockUnits: 42),
            StarterTemplateItem(name: "Paper Towels", category: "Household", location: "Aisle C", unitsPerCase: 12, openingCases: 5, openingUnits: 0, averageDailyUsage: 1.8, leadTimeDays: 6, safetyStockUnits: 16),
            StarterTemplateItem(name: "Hand Soap", category: "Personal Care", location: "Aisle D", unitsPerCase: 24, openingCases: 4, openingUnits: 0, averageDailyUsage: 1.4, leadTimeDays: 6, safetyStockUnits: 20),
            StarterTemplateItem(name: "Trash Bags", category: "Household", location: "Aisle C", unitsPerCase: 18, openingCases: 4, openingUnits: 0, averageDailyUsage: 0.9, leadTimeDays: 7, safetyStockUnits: 12),
            StarterTemplateItem(name: "AA Batteries 4pk", category: "Electronics", location: "Counter", unitsPerCase: 24, openingCases: 3, openingUnits: 0, averageDailyUsage: 0.7, leadTimeDays: 8, safetyStockUnits: 10),
            StarterTemplateItem(name: "Candy Assorted", category: "Snacks", location: "Checkout", unitsPerCase: 36, openingCases: 6, openingUnits: 0, averageDailyUsage: 3.9, leadTimeDays: 4, safetyStockUnits: 30)
        ]
    ),
    StarterTemplate(
        id: "cafe",
        title: "Cafe / Coffee",
        subtitle: "High-turn consumables",
        systemImage: "cup.and.saucer.fill",
        guidance: "Use this for cafes and quick service locations where demand shifts by daypart.",
        items: [
            StarterTemplateItem(name: "Espresso Beans", category: "Coffee", location: "Back Bar", unitsPerCase: 6, openingCases: 4, openingUnits: 0, averageDailyUsage: 1.3, leadTimeDays: 4, safetyStockUnits: 5),
            StarterTemplateItem(name: "Milk 1 Gallon", category: "Dairy", location: "Walk-In", unitsPerCase: 4, openingCases: 12, openingUnits: 0, averageDailyUsage: 5.6, leadTimeDays: 2, safetyStockUnits: 10),
            StarterTemplateItem(name: "Oat Milk", category: "Dairy Alternatives", location: "Walk-In", unitsPerCase: 12, openingCases: 3, openingUnits: 0, averageDailyUsage: 2.2, leadTimeDays: 3, safetyStockUnits: 8),
            StarterTemplateItem(name: "Cold Cups 16oz", category: "Disposables", location: "Storage", unitsPerCase: 1000, openingCases: 1, openingUnits: 200, averageDailyUsage: 120, leadTimeDays: 6, safetyStockUnits: 350),
            StarterTemplateItem(name: "Hot Lids 12/16oz", category: "Disposables", location: "Storage", unitsPerCase: 1000, openingCases: 1, openingUnits: 150, averageDailyUsage: 110, leadTimeDays: 6, safetyStockUnits: 320),
            StarterTemplateItem(name: "Pastry Boxes", category: "Packaging", location: "Storage", unitsPerCase: 250, openingCases: 1, openingUnits: 80, averageDailyUsage: 34, leadTimeDays: 7, safetyStockUnits: 100),
            StarterTemplateItem(name: "Vanilla Syrup", category: "Syrups", location: "Back Bar", unitsPerCase: 6, openingCases: 2, openingUnits: 0, averageDailyUsage: 0.8, leadTimeDays: 5, safetyStockUnits: 4),
            StarterTemplateItem(name: "Chocolate Sauce", category: "Syrups", location: "Back Bar", unitsPerCase: 6, openingCases: 2, openingUnits: 0, averageDailyUsage: 0.6, leadTimeDays: 5, safetyStockUnits: 3)
        ]
    ),
    StarterTemplate(
        id: "salon",
        title: "Salon / Spa",
        subtitle: "Service-linked products",
        systemImage: "scissors",
        guidance: "Use this for salons and spas that blend retail items with appointment-driven usage.",
        items: [
            StarterTemplateItem(name: "Shampoo 1L", category: "Backbar", location: "Color Bar", unitsPerCase: 12, openingCases: 2, openingUnits: 0, averageDailyUsage: 0.8, leadTimeDays: 7, safetyStockUnits: 6),
            StarterTemplateItem(name: "Conditioner 1L", category: "Backbar", location: "Color Bar", unitsPerCase: 12, openingCases: 2, openingUnits: 0, averageDailyUsage: 0.7, leadTimeDays: 7, safetyStockUnits: 6),
            StarterTemplateItem(name: "Developer 20 Vol", category: "Color", location: "Color Bar", unitsPerCase: 6, openingCases: 2, openingUnits: 0, averageDailyUsage: 0.5, leadTimeDays: 6, safetyStockUnits: 4),
            StarterTemplateItem(name: "Hair Color Tubes", category: "Color", location: "Color Bar", unitsPerCase: 24, openingCases: 3, openingUnits: 0, averageDailyUsage: 2.1, leadTimeDays: 6, safetyStockUnits: 18),
            StarterTemplateItem(name: "Foil Sheets", category: "Tools", location: "Stations", unitsPerCase: 500, openingCases: 1, openingUnits: 200, averageDailyUsage: 55, leadTimeDays: 5, safetyStockUnits: 180),
            StarterTemplateItem(name: "Retail Shampoo 300ml", category: "Retail", location: "Front Shelf", unitsPerCase: 12, openingCases: 4, openingUnits: 0, averageDailyUsage: 1.0, leadTimeDays: 8, safetyStockUnits: 7),
            StarterTemplateItem(name: "Retail Conditioner 300ml", category: "Retail", location: "Front Shelf", unitsPerCase: 12, openingCases: 4, openingUnits: 0, averageDailyUsage: 0.9, leadTimeDays: 8, safetyStockUnits: 7),
            StarterTemplateItem(name: "Nitrile Gloves", category: "Supplies", location: "Color Bar", unitsPerCase: 100, openingCases: 3, openingUnits: 40, averageDailyUsage: 28, leadTimeDays: 4, safetyStockUnits: 120)
        ]
    ),
    StarterTemplate(
        id: "parts",
        title: "Parts & Repair",
        subtitle: "Critical components",
        systemImage: "gearshape.2.fill",
        guidance: "Use this for auto parts, repair, and field service operations with stockout-sensitive parts.",
        items: [
            StarterTemplateItem(name: "Oil Filter Standard", category: "Filters", location: "Bin F1", unitsPerCase: 24, openingCases: 6, openingUnits: 0, averageDailyUsage: 2.6, leadTimeDays: 3, safetyStockUnits: 24),
            StarterTemplateItem(name: "Air Filter Standard", category: "Filters", location: "Bin F2", unitsPerCase: 20, openingCases: 4, openingUnits: 0, averageDailyUsage: 1.5, leadTimeDays: 4, safetyStockUnits: 16),
            StarterTemplateItem(name: "Spark Plug", category: "Ignition", location: "Bin I1", unitsPerCase: 40, openingCases: 5, openingUnits: 0, averageDailyUsage: 4.2, leadTimeDays: 5, safetyStockUnits: 35),
            StarterTemplateItem(name: "Brake Pads Front", category: "Brakes", location: "Bin B1", unitsPerCase: 8, openingCases: 6, openingUnits: 0, averageDailyUsage: 1.1, leadTimeDays: 5, safetyStockUnits: 12),
            StarterTemplateItem(name: "Brake Pads Rear", category: "Brakes", location: "Bin B2", unitsPerCase: 8, openingCases: 5, openingUnits: 0, averageDailyUsage: 0.9, leadTimeDays: 5, safetyStockUnits: 10),
            StarterTemplateItem(name: "5W-30 Oil Quarts", category: "Fluids", location: "Rack O1", unitsPerCase: 12, openingCases: 10, openingUnits: 0, averageDailyUsage: 6.8, leadTimeDays: 3, safetyStockUnits: 40),
            StarterTemplateItem(name: "Coolant Gallon", category: "Fluids", location: "Rack O2", unitsPerCase: 6, openingCases: 6, openingUnits: 0, averageDailyUsage: 1.4, leadTimeDays: 4, safetyStockUnits: 10),
            StarterTemplateItem(name: "Serpentine Belt", category: "Belts", location: "Bin BL1", unitsPerCase: 10, openingCases: 3, openingUnits: 0, averageDailyUsage: 0.7, leadTimeDays: 6, safetyStockUnits: 7)
        ]
    )
]
