import SwiftUI
import CoreData

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
    @State private var looseUnits: Int

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
            _looseUnits = State(initialValue: 0)
        case .edit(let item):
            _name = State(initialValue: item.name)
            _quantity = State(initialValue: Int(item.quantity))
            _notes = State(initialValue: item.notes)
            _category = State(initialValue: item.category)
            _location = State(initialValue: item.location)
            _unitsPerCase = State(initialValue: Int(item.unitsPerCase))
            _looseUnits = State(initialValue: Int(item.looseUnits))
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
                        Stepper(value: $quantity, in: 0...1_000_000) {
                            HStack {
                                Text("Cases")
                                Spacer()
                                Text("\(quantity)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Item")
                            .font(Theme.sectionFont())
                    }

                    Section {
                        TextField("Category", text: $category)
                        TextField("Location", text: $location)
                        Stepper(value: $unitsPerCase, in: 0...1_000) {
                            HStack {
                                Text("Units per Case")
                                Spacer()
                                Text("\(unitsPerCase)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Stepper(value: $looseUnits, in: looseUnitsRange) {
                            HStack {
                                Text("Loose Units")
                                Spacer()
                                Text("\(looseUnits)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Details")
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
        let normalized = normalizeCounts(
            cases: quantity,
            unitsPerCase: unitsPerCase,
            looseUnits: looseUnits
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
            item.looseUnits = Int64(normalized.looseUnits)
            item.createdAt = Date()
            item.updatedAt = Date()
        case .edit(let item):
            item.name = trimmedName
            item.quantity = Int64(normalized.cases)
            item.notes = updatedNotes
            item.category = updatedCategory
            item.location = updatedLocation
            item.unitsPerCase = Int64(normalized.unitsPerCase)
            item.looseUnits = Int64(normalized.looseUnits)
            item.updatedAt = Date()
        }

        dataController.save()
        dismiss()
    }

    private var looseUnitsRange: ClosedRange<Int> {
        if unitsPerCase > 0 {
            return 0...max(unitsPerCase - 1, 0)
        }
        return 0...1_000
    }

    private func normalizeCounts(cases: Int, unitsPerCase: Int, looseUnits: Int) -> (cases: Int, unitsPerCase: Int, looseUnits: Int) {
        let clampedCases = max(0, cases)
        let clampedUnitsPerCase = max(0, unitsPerCase)
        let clampedLooseUnits = max(0, looseUnits)

        guard clampedUnitsPerCase > 0 else {
            return (clampedCases, clampedUnitsPerCase, 0)
        }

        let totalUnits = clampedCases * clampedUnitsPerCase + clampedLooseUnits
        let normalizedCases = totalUnits / clampedUnitsPerCase
        let normalizedLooseUnits = totalUnits % clampedUnitsPerCase
        return (normalizedCases, clampedUnitsPerCase, normalizedLooseUnits)
    }
}
