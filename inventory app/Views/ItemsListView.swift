import SwiftUI
import CoreData

struct ItemsListView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.updatedAt, ascending: false)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var isPresentingAdd = false
    @State private var editingItem: InventoryItemEntity?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Theme.backgroundTop, Theme.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                List {
                    if filteredItems.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(filteredItems) { item in
                            ItemRowView(
                                item: item,
                                onEdit: { editingItem = item },
                                onStockChange: { delta in adjustQuantity(for: item, delta: delta) }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete { offsets in
                            delete(offsets, from: filteredItems)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categoryOptions, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresentingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .searchable(text: $searchText, prompt: "Search items")
            .tint(Theme.accent)
            .sheet(isPresented: $isPresentingAdd) {
                ItemFormView(mode: .add)
            }
            .sheet(item: $editingItem) { item in
                ItemFormView(mode: .edit(item))
            }
        }
    }

    private var filteredItems: [InventoryItemEntity] {
        items.filter { item in
            matchesSearch(item) && matchesCategory(item)
        }
    }

    private var categoryOptions: [String] {
        var options = ["All"]
        let categories = Set(items.map { normalizedCategoryName($0.category) })
            .filter { !$0.isEmpty && $0 != "Uncategorized" }
            .sorted()
        let hasUncategorized = items.contains { normalizedCategoryName($0.category) == "Uncategorized" }
        if hasUncategorized {
            options.append("Uncategorized")
        }
        options.append(contentsOf: categories)
        return options
    }

    private var emptyStateView: some View {
        let title = items.isEmpty ? "No Items" : "No Matches"
        let subtitle = items.isEmpty
            ? "Add your first item to start tracking inventory."
            : "Try adjusting your search or category filter."
        return VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(Theme.titleFont())
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func delete(_ offsets: IndexSet, from items: [InventoryItemEntity]) {
        let targets = offsets.map { items[$0] }
        targets.forEach(context.delete)
        dataController.save()
    }

    private func adjustQuantity(for item: InventoryItemEntity, delta: Int64) {
        let newValue = max(0, item.quantity + delta)
        item.quantity = newValue
        item.updatedAt = Date()
        dataController.save()
    }

    private func matchesSearch(_ item: InventoryItemEntity) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let query = trimmed.lowercased()
        return item.name.lowercased().contains(query)
            || item.notes.lowercased().contains(query)
            || item.category.lowercased().contains(query)
            || item.location.lowercased().contains(query)
    }

    private func matchesCategory(_ item: InventoryItemEntity) -> Bool {
        guard selectedCategory != "All" else { return true }
        let normalized = normalizedCategoryName(item.category)
        return normalized == selectedCategory
    }

    private func normalizedCategoryName(_ category: String) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Uncategorized" : trimmed
    }
}

private struct ItemRowView: View {
    let item: InventoryItemEntity
    let onEdit: () -> Void
    let onStockChange: (Int64) -> Void

    var body: some View {
        let totalUnits = item.unitsPerCase > 0
            ? item.quantity * item.unitsPerCase + item.looseUnits
            : 0

        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(.headline, design: .rounded))
                    HStack(spacing: 8) {
                        if !item.category.isEmpty {
                            Label(item.category, systemImage: "tag")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        if !item.location.isEmpty {
                            Label(item.location, systemImage: "mappin.and.ellipse")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !item.notes.isEmpty {
                        Text(item.notes)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if item.unitsPerCase > 0 {
                        let casesText = item.quantity == 1 ? "1 case" : "\(item.quantity) cases"
                        let unitsText = item.looseUnits == 1 ? "1 unit" : "\(item.looseUnits) units"
                        Text(item.looseUnits > 0 ? "\(casesText) + \(unitsText)" : casesText)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(totalUnits) total units")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Qty \(item.quantity)")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(item.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 12) {
                Button {
                    onStockChange(-1)
                } label: {
                    Label("Stock Out", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onStockChange(1)
                } label: {
                    Label("Stock In", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }
}
