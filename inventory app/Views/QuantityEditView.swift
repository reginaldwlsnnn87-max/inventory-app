import SwiftUI
import CoreData

struct QuantityEditView: View {
    @EnvironmentObject private var dataController: InventoryDataController
    @Environment(\.dismiss) private var dismiss

    let item: InventoryItemEntity

    @State private var casesText: String
    @State private var unitsText: String
    @State private var eachesText: String
    @State private var partialUnitText: String

    init(item: InventoryItemEntity) {
        self.item = item
        _casesText = State(initialValue: String(item.quantity))
        _unitsText = State(initialValue: String(item.looseUnits))
        _eachesText = State(initialValue: String(item.looseEaches))
        _partialUnitText = State(initialValue: item.gallonFraction == 0 ? "" : String(item.gallonFraction))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                Form {
                Section {
                    if item.isLiquid {
                        TextField("Units (Gallons)", text: $unitsText)
                            .keyboardType(.numberPad)
                    } else {
                        TextField("Cases", text: $casesText)
                            .keyboardType(.numberPad)
                        TextField("Units", text: $unitsText)
                            .keyboardType(.numberPad)
                        TextField("Each", text: $eachesText)
                            .keyboardType(.numberPad)
                    }
                } header: {
                    Text("Counts")
                        .font(Theme.sectionFont())
                }

                Section {
                    HStack {
                        Text("Total Units")
                            .font(.system(.subheadline, design: .rounded))
                        Spacer()
                        Text("\(totalUnitsPreview)")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    HStack {
                        Text("Total Each")
                            .font(.system(.subheadline, design: .rounded))
                        Spacer()
                        Text("\(totalEachesPreview) each")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    if item.isLiquid {
                        HStack {
                            Text("Total Gallons")
                                .font(.system(.subheadline, design: .rounded))
                            Spacer()
                            Text(formattedGallons(totalGallonsPreview))
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                } header: {
                    Text("Preview")
                        .font(Theme.sectionFont())
                }

                if item.isLiquid {
                    Section {
                        TextField("Partial Unit (e.g., 0.5, 1.25)", text: $partialUnitText)
                            .keyboardType(.decimalPad)
                        HStack(spacing: 8) {
                            Button("1/4") { partialUnitText = "0.25" }
                            Button("1/2") { partialUnitText = "0.5" }
                            Button("3/4") { partialUnitText = "0.75" }
                            Button("1/3") { partialUnitText = "0.33" }
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .buttonStyle(.bordered)
                    } header: {
                        Text("Gallons")
                            .font(Theme.sectionFont())
                    }
                }
            }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Set Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private var totalUnitsPreview: Int {
        let casesValue = Int(casesText) ?? 0
        let unitsValue = Int(unitsText) ?? 0
        let baseUnits = item.isLiquid ? unitsValue : casesValue * Int(item.unitsPerCase) + unitsValue
        guard item.isLiquid else { return baseUnits }
        let eachesValue = Int(eachesText) ?? 0
        let eachesPerUnit = Int(item.eachesPerUnit)
        let eachesFraction = eachesPerUnit > 0 ? Double(eachesValue) / Double(eachesPerUnit) : 0
        let extraGallons = Double(partialUnitText) ?? 0
        let totalGallons = Double(baseUnits) + eachesFraction + extraGallons
        return Int((totalGallons * 128).rounded())
    }

    private var totalEachesPreview: Int {
        if item.isLiquid {
            return totalUnitsPreview
        }
        let casesValue = Int(casesText) ?? 0
        let unitsValue = Int(unitsText) ?? 0
        let eachesValue = Int(eachesText) ?? 0
        let unitsPerCase = Int(item.unitsPerCase)
        let eachesPerUnit = Int(item.eachesPerUnit)
        return (casesValue * unitsPerCase + unitsValue) * eachesPerUnit + eachesValue
    }

    private var totalGallonsPreview: Double {
        let casesValue = Int(casesText) ?? 0
        let unitsValue = Int(unitsText) ?? 0
        let baseUnits = item.isLiquid
            ? Double(unitsValue)
            : Double(casesValue * Int(item.unitsPerCase) + unitsValue)
        let eachesValue = Int(eachesText) ?? 0
        let eachesPerUnit = Int(item.eachesPerUnit)
        let eachesFraction = eachesPerUnit > 0 ? Double(eachesValue) / Double(eachesPerUnit) : 0
        let extraGallons = Double(partialUnitText) ?? 0
        return baseUnits + eachesFraction + extraGallons
    }

    private func formattedGallons(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        var text = String(format: "%.2f", rounded)
        if text.contains(".") {
            text = text.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }
        return text
    }

    private func save() {
        let casesValue = Int(casesText) ?? 0
        let unitsValue = Int(unitsText) ?? 0
        let eachesValue = Int(eachesText) ?? 0
        let extraGallons = Double(partialUnitText) ?? 0

        let normalized = normalizeCounts(
            cases: casesValue,
            unitsPerCase: Int(item.unitsPerCase),
            units: unitsValue,
            eachesPerUnit: Int(item.eachesPerUnit),
            eaches: eachesValue
        )

        item.quantity = Int64(normalized.cases)
        item.looseUnits = Int64(normalized.units)
        item.looseEaches = Int64(normalized.eaches)
        if item.isLiquid {
            item.gallonFraction = extraGallons
        }
        item.updatedAt = Date()

        dataController.save()
        Haptics.success()
        dismiss()
    }

    private func normalizeCounts(
        cases: Int,
        unitsPerCase: Int,
        units: Int,
        eachesPerUnit: Int,
        eaches: Int
    ) -> (cases: Int, units: Int, eaches: Int) {
        let clampedCases = max(0, cases)
        let clampedUnitsPerCase = max(1, unitsPerCase)
        let clampedUnits = max(0, units)
        let clampedEachesPerUnit = max(1, eachesPerUnit)
        let clampedEaches = max(0, eaches)

        let totalEaches = (clampedCases * clampedUnitsPerCase + clampedUnits) * clampedEachesPerUnit + clampedEaches
        let totalUnits = totalEaches / clampedEachesPerUnit
        let normalizedEaches = totalEaches % clampedEachesPerUnit
        let normalizedCases = totalUnits / clampedUnitsPerCase
        let normalizedUnits = totalUnits % clampedUnitsPerCase
        return (normalizedCases, normalizedUnits, normalizedEaches)
    }
}
