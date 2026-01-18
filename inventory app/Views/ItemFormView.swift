import SwiftUI
import CoreData
import Foundation

struct ItemFormView: View {
    enum Mode: Identifiable {
        case add
        case edit(InventoryItemEntity)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let item):
                return item.id.uuidString
            }
        }
    }

    let mode: Mode

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var quantity: Int
    @State private var notes: String
    @State private var category: String
    @State private var location: String
    @State private var unitsPerCase: Int
    @State private var units: Int
    @State private var eachesPerUnit: Int
    @State private var eaches: Int
    @State private var isLiquid: Bool
    @State private var gallonFractionText: String

    init(mode: Mode) {
        self.mode = mode

        switch mode {
        case .add:
            _name = State(initialValue: "")
            _quantity = State(initialValue: 1)
            _notes = State(initialValue: "")
            _category = State(initialValue: "")
            _location = State(initialValue: "")
            _unitsPerCase = State(initialValue: 0)
            _units = State(initialValue: 0)
            _eachesPerUnit = State(initialValue: 0)
            _eaches = State(initialValue: 0)
            _isLiquid = State(initialValue: false)
            _gallonFractionText = State(initialValue: "")
        case .edit(let item):
            _name = State(initialValue: item.name)
            _quantity = State(initialValue: Int(item.quantity))
            _notes = State(initialValue: item.notes)
            _category = State(initialValue: item.category)
            _location = State(initialValue: item.location)
            _unitsPerCase = State(initialValue: Int(item.unitsPerCase))
            _units = State(initialValue: Int(item.looseUnits))
            _eachesPerUnit = State(initialValue: Int(item.eachesPerUnit))
            _eaches = State(initialValue: Int(item.looseEaches))
            _isLiquid = State(initialValue: item.isLiquid)
            _gallonFractionText = State(initialValue: item.gallonFraction == 0 ? "" : String(item.gallonFraction))
        }
    }

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
                        TextField("Name", text: $name)
                    } header: {
                        Text("Item")
                            .font(Theme.sectionFont())
                    }

                    Section {
                        TextField("Category", text: $category)
                        TextField("Location", text: $location)
                        Toggle("Liquid (Gallons)", isOn: $isLiquid)
                        if !isLiquid {
                            Stepper(value: $quantity, in: 0...1_000_000) {
                                HStack {
                                    Text("Cases")
                                    Spacer()
                                    Text("\(quantity)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Stepper(value: $unitsPerCase, in: 0...1_000) {
                                HStack {
                                    Text("Units per Case")
                                    Spacer()
                                    Text("\(unitsPerCase)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Stepper(value: $eachesPerUnit, in: 0...1_000) {
                                HStack {
                                    Text("Each per Unit")
                                    Spacer()
                                    Text("\(eachesPerUnit)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Stepper(value: $units, in: 0...1_000_000) {
                                HStack {
                                    Text("Units")
                                    Spacer()
                                    Text("\(units)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Stepper(value: $eaches, in: eachesRange) {
                                HStack {
                                    Text("Each")
                                    Spacer()
                                    Text("\(eaches)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Stepper(value: $units, in: 0...1_000_000) {
                                HStack {
                                    Text("Units (Gallons)")
                                    Spacer()
                                    Text("\(units)")
                                        .foregroundStyle(.secondary)
                                }
                            }
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
                        Text("Details")
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
                            Text("Total Eaches")
                                .font(.system(.subheadline, design: .rounded))
                            Spacer()
                            Text("\(totalEachesPreview) each")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        if isLiquid {
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

                    Section {
                        TextField("Optional", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    } header: {
                        Text("Notes")
                            .font(Theme.sectionFont())
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(title)
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

    private var title: String {
        switch mode {
        case .add:
            return "Add Item"
        case .edit:
            return "Edit Item"
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let updatedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraGallons = Double(gallonFractionText) ?? 0
        let normalized = normalizeCounts(
            cases: quantity,
            unitsPerCase: unitsPerCase,
            units: units,
            eachesPerUnit: eachesPerUnit,
            eaches: eaches
        )

        switch mode {
        case .add:
            let item = InventoryItemEntity(context: context)
            item.id = UUID()
            item.name = trimmedName
            item.quantity = Int64(normalized.cases)
            item.notes = updatedNotes
            item.category = updatedCategory
            item.location = updatedLocation
            item.unitsPerCase = Int64(normalized.unitsPerCase)
            item.looseUnits = Int64(normalized.units)
            item.eachesPerUnit = Int64(normalized.eachesPerUnit)
            item.looseEaches = Int64(normalized.eaches)
            item.isLiquid = isLiquid
            item.gallonFraction = isLiquid ? extraGallons : 0
            item.createdAt = Date()
            item.updatedAt = Date()
        case .edit(let item):
            item.name = trimmedName
            item.quantity = Int64(normalized.cases)
            item.notes = updatedNotes
            item.category = updatedCategory
            item.location = updatedLocation
            item.unitsPerCase = Int64(normalized.unitsPerCase)
            item.looseUnits = Int64(normalized.units)
            item.eachesPerUnit = Int64(normalized.eachesPerUnit)
            item.looseEaches = Int64(normalized.eaches)
            item.isLiquid = isLiquid
            item.gallonFraction = isLiquid ? extraGallons : 0
            item.updatedAt = Date()
        }

        dataController.save()
        Haptics.success()
        dismiss()
    }

    private var eachesRange: ClosedRange<Int> {
        if eachesPerUnit > 0 {
            return 0...max(eachesPerUnit - 1, 0)
        }
        return 0...1_000
    }

    private var totalUnitsPreview: Int {
        let baseUnits = quantity * unitsPerCase + units
        guard isLiquid else { return baseUnits }
        let eachesFraction = eachesPerUnit > 0 ? Double(eaches) / Double(eachesPerUnit) : 0
        let extraGallons = Double(gallonFractionText) ?? 0
        let totalGallons = Double(baseUnits) + eachesFraction + extraGallons
        return Int((totalGallons * 128).rounded())
    }

    private var totalEachesPreview: Int {
        if isLiquid {
            let gallons = totalGallonsPreview
            return Int((gallons * 128).rounded())
        }
        return (quantity * unitsPerCase + units) * eachesPerUnit + eaches
    }

    private var totalGallonsPreview: Double {
        let extraGallons = Double(gallonFractionText) ?? 0
        if isLiquid {
            return Double(units) + extraGallons
        }
        let baseUnits = Double(quantity * unitsPerCase + units)
        let eachesFraction = eachesPerUnit > 0 ? Double(eaches) / Double(eachesPerUnit) : 0
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
