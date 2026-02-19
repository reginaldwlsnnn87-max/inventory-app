import SwiftUI
import CoreData

private enum ServiceLevelPreset: String, CaseIterable, Identifiable {
    case level95 = "95%"
    case level97 = "97%"
    case level99 = "99%"

    var id: String { rawValue }

    var zScore: Double {
        switch self {
        case .level95:
            return 1.65
        case .level97:
            return 1.88
        case .level99:
            return 2.33
        }
    }

    var label: String {
        switch self {
        case .level95:
            return "Lower buffer"
        case .level97:
            return "Balanced"
        case .level99:
            return "High service"
        }
    }
}

struct InventoryCalculationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var selectedItemID: UUID?
    @State private var onHandText = "120"
    @State private var dailyDemandText = "8"
    @State private var leadTimeText = "6"
    @State private var manualSafetyStockText = "20"
    @State private var demandStdDevText = "3"
    @State private var annualDemandText = ""
    @State private var orderCostText = "45"
    @State private var holdingCostText = "5"
    @State private var averageInventoryText = ""
    @State private var serviceLevel: ServiceLevelPreset = .level97
    @State private var simOnHand = 120.0
    @State private var simDailyDemand = 8.0
    @State private var simLeadTime = 6.0
    @State private var simDemandStdDev = 3.0
    @State private var simAnnualDemand = 2920.0
    @State private var simOrderCost = 45.0
    @State private var simHoldingCost = 5.0
    @State private var simServiceLevel = 97.0

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    itemLoaderCard
                    inputCard
                    simulatorCard
                    outputCard
                    learningCard
                    decisionCard
                }
                .padding(16)
            }
        }
        .navigationTitle("Calculations Lab")
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

    private var selectedItem: InventoryItemEntity? {
        guard let selectedItemID else { return nil }
        return workspaceItems.first(where: { $0.id == selectedItemID })
    }

    private var workspaceItems: [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(authStore.activeWorkspaceID) }
    }

    private var onHandUnits: Double {
        sanitizedDouble(onHandText)
    }

    private var dailyDemand: Double {
        sanitizedDouble(dailyDemandText)
    }

    private var leadTimeDays: Double {
        sanitizedDouble(leadTimeText)
    }

    private var manualSafetyStock: Double {
        sanitizedDouble(manualSafetyStockText)
    }

    private var demandStdDev: Double {
        sanitizedDouble(demandStdDevText)
    }

    private var annualDemand: Double {
        let typed = sanitizedDouble(annualDemandText)
        if typed > 0 {
            return typed
        }
        return max(0, dailyDemand * 365)
    }

    private var orderCost: Double {
        sanitizedDouble(orderCostText)
    }

    private var holdingCost: Double {
        sanitizedDouble(holdingCostText)
    }

    private var averageInventory: Double {
        let typed = sanitizedDouble(averageInventoryText)
        if typed > 0 {
            return typed
        }
        if let eoq = eoqUnits {
            return max(1, eoq / 2)
        }
        return max(1, onHandUnits)
    }

    private var leadTimeDemand: Double {
        dailyDemand * leadTimeDays
    }

    private var statisticalSafetyStock: Double {
        guard demandStdDev > 0, leadTimeDays > 0 else { return 0 }
        return serviceLevel.zScore * demandStdDev * sqrt(leadTimeDays)
    }

    private var targetSafetyStock: Double {
        max(manualSafetyStock, statisticalSafetyStock)
    }

    private var reorderPoint: Double {
        leadTimeDemand + targetSafetyStock
    }

    private var suggestedOrder: Double {
        max(0, reorderPoint - onHandUnits)
    }

    private var daysOfSupply: Double? {
        guard dailyDemand > 0 else { return nil }
        return onHandUnits / dailyDemand
    }

    private var eoqUnits: Double? {
        guard annualDemand > 0, orderCost > 0, holdingCost > 0 else { return nil }
        return sqrt((2 * annualDemand * orderCost) / holdingCost)
    }

    private var inventoryTurns: Double? {
        guard averageInventory > 0 else { return nil }
        return annualDemand / averageInventory
    }

    private var orderCycleDays: Double? {
        guard let eoqUnits, dailyDemand > 0 else { return nil }
        return eoqUnits / dailyDemand
    }

    private var simulatorZScore: Double {
        switch simServiceLevel {
        case ..<96:
            return 1.65
        case ..<98:
            return 1.88
        default:
            return 2.33
        }
    }

    private var simulatorSafetyStock: Double {
        guard simDemandStdDev > 0, simLeadTime > 0 else { return 0 }
        return simulatorZScore * simDemandStdDev * sqrt(simLeadTime)
    }

    private var simulatorReorderPoint: Double {
        simDailyDemand * simLeadTime + simulatorSafetyStock
    }

    private var simulatorSuggestedOrder: Double {
        max(0, simulatorReorderPoint - simOnHand)
    }

    private var simulatorEOQ: Double? {
        guard simAnnualDemand > 0, simOrderCost > 0, simHoldingCost > 0 else { return nil }
        return sqrt((2 * simAnnualDemand * simOrderCost) / simHoldingCost)
    }

    private var simulatorCycleDays: Double? {
        guard let simulatorEOQ, simDailyDemand > 0 else { return nil }
        return simulatorEOQ / simDailyDemand
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Learn inventory math while you work.")
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Use real item data or practice values. Every formula updates live so the team can learn on the floor.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .inventoryCard(cornerRadius: 16, emphasis: 0.56)
    }

    private var itemLoaderCard: some View {
        sectionCard(title: "Load Item Data") {
            Picker("Item", selection: $selectedItemID) {
                Text("No item selected").tag(Optional<UUID>.none)
                ForEach(workspaceItems) { item in
                    Text(item.name.isEmpty ? "Unnamed Item" : item.name)
                        .tag(Optional(item.id))
                }
            }
            .pickerStyle(.menu)

            Button {
                seedFromSelectedItem()
            } label: {
                HStack {
                    Image(systemName: "arrow.down.doc")
                    Text("Load Fields From Item")
                        .font(Theme.font(13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedItem == nil)

            if let item = selectedItem {
                Text("On hand: \(formatted(item.totalUnitsOnHand)) units • Avg/day: \(formatted(item.averageDailyUsage))")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var inputCard: some View {
        sectionCard(title: "Inputs") {
            inputField("On-hand units", text: $onHandText, keyboard: .numberPad)
            inputField("Average daily demand", text: $dailyDemandText, keyboard: .decimalPad)
            inputField("Lead time (days)", text: $leadTimeText, keyboard: .decimalPad)

            Picker("Service level", selection: $serviceLevel) {
                ForEach(ServiceLevelPreset.allCases) { preset in
                    Text("\(preset.rawValue) • \(preset.label)").tag(preset)
                }
            }
            .pickerStyle(.segmented)

            inputField("Manual safety stock", text: $manualSafetyStockText, keyboard: .numberPad)
            inputField("Demand std dev (per day)", text: $demandStdDevText, keyboard: .decimalPad)
            inputField("Annual demand (optional)", text: $annualDemandText, keyboard: .decimalPad)
            inputField("Order cost per PO", text: $orderCostText, keyboard: .decimalPad)
            inputField("Holding cost per unit/year", text: $holdingCostText, keyboard: .decimalPad)
            inputField("Average inventory (optional)", text: $averageInventoryText, keyboard: .decimalPad)
        }
    }

    private var simulatorCard: some View {
        sectionCard(title: "Scenario Simulator") {
            Text("Stress test assumptions with sliders, then push the scenario into Inputs.")
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            sliderRow(
                title: "On-hand units",
                value: $simOnHand,
                range: 0...2_000,
                step: 1,
                valueText: formatted(simOnHand)
            )
            sliderRow(
                title: "Daily demand",
                value: $simDailyDemand,
                range: 0...300,
                step: 0.5,
                valueText: formatted(simDailyDemand)
            )
            sliderRow(
                title: "Lead time (days)",
                value: $simLeadTime,
                range: 0...120,
                step: 1,
                valueText: formatted(simLeadTime)
            )
            sliderRow(
                title: "Demand std dev",
                value: $simDemandStdDev,
                range: 0...120,
                step: 0.5,
                valueText: formatted(simDemandStdDev)
            )
            sliderRow(
                title: "Service level (%)",
                value: $simServiceLevel,
                range: 95...99,
                step: 1,
                valueText: "\(Int(simServiceLevel))"
            )
            sliderRow(
                title: "Annual demand",
                value: $simAnnualDemand,
                range: 0...50_000,
                step: 50,
                valueText: formatted(simAnnualDemand)
            )
            sliderRow(
                title: "Order cost",
                value: $simOrderCost,
                range: 0...500,
                step: 1,
                valueText: formatted(simOrderCost)
            )
            sliderRow(
                title: "Holding cost",
                value: $simHoldingCost,
                range: 0.1...200,
                step: 0.5,
                valueText: formatted(simHoldingCost)
            )

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                metricTile("Sim ROP", value: "\(formatted(simulatorReorderPoint)) units", subtitle: "Demand + buffer")
                metricTile("Sim Order", value: "\(formatted(simulatorSuggestedOrder)) units", subtitle: "Gap to target")
                metricTile("Sim Safety", value: "\(formatted(simulatorSafetyStock)) units", subtitle: "From volatility")
                metricTile("Sim EOQ", value: simulatorEOQ.map { "\(formatted($0)) units" } ?? "-", subtitle: "Economic batch")
                metricTile("Sim Cycle", value: simulatorCycleDays.map { "\(formatted($0)) days" } ?? "-", subtitle: "EOQ cadence")
                metricTile("Sim Z", value: formatted(simulatorZScore), subtitle: "Service factor")
            }

            Button {
                applySimulatorToInputs()
            } label: {
                HStack {
                    Image(systemName: "arrow.down.doc.fill")
                    Text("Apply Scenario To Inputs")
                        .font(Theme.font(13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var outputCard: some View {
        sectionCard(title: "Live Output") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                metricTile("Reorder Point", value: "\(formatted(reorderPoint)) units", subtitle: "Demand + buffer")
                metricTile("Order Now", value: "\(formatted(suggestedOrder)) units", subtitle: "Gap to target")
                metricTile("Safety Stock", value: "\(formatted(targetSafetyStock)) units", subtitle: "Manual vs statistical")
                metricTile("EOQ", value: eoqUnits.map { "\(formatted($0)) units" } ?? "Need cost inputs", subtitle: "Economic batch size")
                metricTile("Days of Supply", value: daysOfSupply.map { "\(formatted($0)) days" } ?? "Need demand", subtitle: "On-hand runway")
                metricTile("Turns/Year", value: inventoryTurns.map { formatted($0) } ?? "Need avg inventory", subtitle: "Velocity")
            }
        }
    }

    private var learningCard: some View {
        sectionCard(title: "Formula Walkthrough") {
            formulaRow(
                title: "Reorder Point (ROP)",
                formula: "ROP = (Average Daily Demand × Lead Time) + Safety Stock",
                worked: "\(formatted(dailyDemand)) × \(formatted(leadTimeDays)) + \(formatted(targetSafetyStock)) = \(formatted(reorderPoint))"
            )
            formulaRow(
                title: "Statistical Safety Stock",
                formula: "Safety Stock = Z × Demand StdDev × sqrt(Lead Time)",
                worked: "\(formatted(serviceLevel.zScore)) × \(formatted(demandStdDev)) × sqrt(\(formatted(leadTimeDays))) = \(formatted(statisticalSafetyStock))"
            )
            formulaRow(
                title: "Economic Order Quantity",
                formula: "EOQ = sqrt((2 × Annual Demand × Order Cost) / Holding Cost)",
                worked: eoqUnits.map { _ in
                    "sqrt((2 × \(formatted(annualDemand)) × \(formatted(orderCost)) / \(formatted(holdingCost))) = \(formatted(eoqUnits ?? 0))"
                } ?? "Enter annual demand, order cost, and holding cost."
            )
        }
    }

    private var decisionCard: some View {
        sectionCard(title: "Decision Coach") {
            if suggestedOrder > 0 {
                Text("You are below the recommended reorder point. Consider placing an order for about \(formatted(suggestedOrder)) units.")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Color.orange)
            } else {
                Text("You are above your reorder point. Monitor demand, no immediate reorder needed.")
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            if let cycle = orderCycleDays {
                Text("At current demand, EOQ implies a reorder cycle near every \(formatted(cycle)) days.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            if let turns = inventoryTurns, turns < 4 {
                Text("Turnover is low. Try smaller, more frequent orders or reduce safety stock if service allows.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                content()
            }
            .padding(12)
            .inventoryCard(cornerRadius: 14, emphasis: 0.26)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(valueText)
                    .font(Theme.font(12, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
            }
            Slider(value: value, in: range, step: step)
                .tint(Theme.accent)
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

    private func inputField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField("", text: text, prompt: Theme.inputPrompt(title))
            .keyboardType(keyboard)
            .inventoryTextInputField()
    }

    private func metricTile(_ title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(Theme.font(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func formulaRow(title: String, formula: String, worked: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(formula)
                .font(Theme.font(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(worked)
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.accentDeep)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func seedFromSelectedItem() {
        guard let item = selectedItem else { return }
        onHandText = String(item.totalUnitsOnHand)
        dailyDemandText = formatted(item.averageDailyUsage)
        leadTimeText = String(item.leadTimeDays)
        manualSafetyStockText = String(item.safetyStockUnits)
        if annualDemandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annualDemandText = formatted(item.averageDailyUsage * 365)
        }
        if averageInventoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            averageInventoryText = String(max(1, item.totalUnitsOnHand))
        }

        simOnHand = Double(max(0, item.totalUnitsOnHand))
        simDailyDemand = max(0, item.averageDailyUsage)
        simLeadTime = Double(max(0, item.leadTimeDays))
        simDemandStdDev = max(0, simDailyDemand * 0.4)
        simAnnualDemand = max(0, simDailyDemand * 365)
    }

    private func applySimulatorToInputs() {
        onHandText = formatted(simOnHand)
        dailyDemandText = formatted(simDailyDemand)
        leadTimeText = formatted(simLeadTime)
        demandStdDevText = formatted(simDemandStdDev)
        manualSafetyStockText = formatted(simulatorSafetyStock)
        annualDemandText = formatted(simAnnualDemand)
        orderCostText = formatted(simOrderCost)
        holdingCostText = formatted(simHoldingCost)
        serviceLevel = nearestServiceLevel(to: simServiceLevel)
    }

    private func nearestServiceLevel(to percent: Double) -> ServiceLevelPreset {
        let candidates: [ServiceLevelPreset] = [.level95, .level97, .level99]
        return candidates.min { lhs, rhs in
            abs(servicePercent(for: lhs) - percent) < abs(servicePercent(for: rhs) - percent)
        } ?? .level97
    }

    private func servicePercent(for preset: ServiceLevelPreset) -> Double {
        switch preset {
        case .level95:
            return 95
        case .level97:
            return 97
        case .level99:
            return 99
        }
    }

    private func sanitizedDouble(_ value: String) -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return max(0, Double(trimmed) ?? 0)
    }

    private func formatted(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return "0"
        }
        if abs(value.rounded() - value) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
    }

    private func formatted(_ value: Int64) -> String {
        String(value)
    }
}
