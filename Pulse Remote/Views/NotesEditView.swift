import SwiftUI

struct NotesEditView: View {
    let item: InventoryItemEntity

    @EnvironmentObject private var dataController: InventoryDataController
    @EnvironmentObject private var authStore: AuthStore
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

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard

                        sectionCard(title: "Notes") {
                            TextField("", text: $notes, prompt: Theme.inputPrompt("Write note"), axis: .vertical)
                                .lineLimit(5...10)
                                .inventoryTextInputField()
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 96)
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
            .tint(Theme.accent)
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Theme.accentSoft.opacity(0.34))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name.isEmpty ? "Item notes" : item.name)
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Capture quick context for count history, damage, or handling details.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .inventoryCard(cornerRadius: 16, emphasis: 0.62)
    }

    private var saveBar: some View {
        HStack {
            Button(action: save) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Note")
                        .font(Theme.font(14, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accentDeep],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
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
        .inventoryCard(cornerRadius: 16, emphasis: 0.44)
    }

    private func save() {
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.assignWorkspaceIfNeeded(authStore.activeWorkspaceID)
        item.updatedAt = Date()
        dataController.save()
        Haptics.success()
        dismiss()
    }
}
