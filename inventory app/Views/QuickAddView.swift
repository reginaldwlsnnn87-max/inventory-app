import SwiftUI
import CoreData

struct QuickAddView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var casesText = "1"
    @State private var unitsPerCaseText = ""
    @State private var eachesPerUnitText = ""
    @State private var unitsText = ""
    @State private var eachesText = ""
    @State private var category = ""
    @State private var location = ""
    @State private var isLiquid = false
    @State private var gallonFractionText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Theme.backgroundTop, Theme.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Form {
                    Section {
                        TextField("Item name", text: $name)
                        TextField("Cases", text: $casesText)
                            .keyboardType(.numberPad)
                    } header: {
                        Text("Quick Add")
                            .font(Theme.sectionFont())
                    }

                    Section {
                        TextField("Units per Case", text: $unitsPerCaseText)
                            .keyboardType(.numberPad)
                        TextField("Each per Unit", text: $eachesPerUnitText)
                            .keyboardType(.numberPad)
                        TextField("Units", text: $unitsText)
                            .keyboardType(.numberPad)
                        TextField("Each", text: $eachesText)
                            .keyboardType(.numberPad)
                    } header: {
                        Text("Units")
                            .font(Theme.sectionFont())
                    }

                    Section {
                        TextField("Category", text: $category)
                        TextField("Location", text: $location)
                    } header: {
                        Text("Details")
                            .font(Theme.sectionFont())
                    }

                    Section {
                        Toggle("Liquid (Gallons)", isOn: $isLiquid)
                        if isLiquid {
                            TextField("Partial Unit (e.g., 0.5, 1.25)", text: $gallonFractionText)
                                .keyboardType(.decimalPad)
                            HStack(spacing: 8) {
                                Button("1/4") { gallonFractionText = "0.25" }
                                Button("1/2") { gallonFractionText = "0.5" }
                                Button("3/4") { gallonFractionText = "0.75" }
                                Button("1/3") { gallonFractionText = "0.33" }
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .buttonStyle(.bordered)
                        }
                    } header: {
                        Text("Gallons")
                            .font(Theme.sectionFont())
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .tint(Theme.accent)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let casesValue = Int(casesText) ?? 0
        let unitsPerCaseValue = Int(unitsPerCaseText) ?? 0
        let eachesPerUnitValue = Int(eachesPerUnitText) ?? 0
        let unitsValue = Int(unitsText) ?? 0
        let eachesValue = Int(eachesText) ?? 0
        let extraGallons = Double(gallonFractionText) ?? 0
        let normalized = normalizeCounts(
            cases: casesValue,
            unitsPerCase: unitsPerCaseValue,
            units: unitsValue,
            eachesPerUnit: eachesPerUnitValue,
            eaches: eachesValue
        )

        let item = InventoryItemEntity(context: context)
        item.id = UUID()
        item.name = trimmedName
        item.quantity = Int64(normalized.cases)
        item.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        item.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = ""
        item.unitsPerCase = Int64(normalized.unitsPerCase)
        item.looseUnits = Int64(normalized.units)
        item.eachesPerUnit = Int64(normalized.eachesPerUnit)
        item.looseEaches = Int64(normalized.eaches)
        item.isLiquid = isLiquid
        item.gallonFraction = isLiquid ? extraGallons : 0
        item.createdAt = Date()
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
    ) -> (cases: Int, unitsPerCase: Int, units: Int, eachesPerUnit: Int, eaches: Int) {
        let clampedCases = max(0, cases)
        let clampedUnitsPerCase = max(0, unitsPerCase)
        let clampedUnits = max(0, units)
        let clampedEachesPerUnit = max(0, eachesPerUnit)
        let clampedEaches = max(0, eaches)

        guard clampedUnitsPerCase > 0, clampedEachesPerUnit > 0 else {
            return (clampedCases, clampedUnitsPerCase, clampedUnits, clampedEachesPerUnit, clampedEaches)
        }

        let totalEaches = (clampedCases * clampedUnitsPerCase + clampedUnits) * clampedEachesPerUnit + clampedEaches
        let totalUnits = totalEaches / clampedEachesPerUnit
        let normalizedEaches = totalEaches % clampedEachesPerUnit
        let normalizedCases = totalUnits / clampedUnitsPerCase
        let normalizedUnits = totalUnits % clampedUnitsPerCase
        return (normalizedCases, clampedUnitsPerCase, normalizedUnits, clampedEachesPerUnit, normalizedEaches)
    }
}
