import SwiftUI

struct NotesEditView: View {
    let item: InventoryItemEntity

    @EnvironmentObject private var dataController: InventoryDataController
    @Environment(\.dismiss) private var dismiss

    @State private var notes: String

    init(item: InventoryItemEntity) {
        self.item = item
        _notes = State(initialValue: item.notes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                Form {
                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                } header: {
                    Text("Notes")
                        .font(Theme.sectionFont())
                }
            }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Notes")
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

    private func save() {
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.updatedAt = Date()
        dataController.save()
        Haptics.success()
        dismiss()
    }
}
