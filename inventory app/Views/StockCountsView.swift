import SwiftUI
import CoreData

struct StockCountsView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var counts: [UUID: Double] = [:]
    @State private var hasSeeded = false

    var body: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    ForEach(items) { item in
                        countRow(for: item)
                    }

                    applyButton
                }
                .padding(16)
            }
        }
        .navigationTitle("Stock Counts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .tint(Theme.accent)
        .onAppear {
            seedCountsIfNeeded()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Count and confirm items in one pass.")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("We prefill with current counts. Adjust and tap Apply Counts.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private func countRow(for item: InventoryItemEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(currentCountLabel(for: item))
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Reset") {
                    counts[item.id] = defaultCount(for: item)
                }
                .font(Theme.font(11, weight: .semibold))
                .buttonStyle(.bordered)
            }

            if item.isLiquid {
                TextField(
                    "Gallons",
                    value: binding(for: item),
                    format: .number.precision(.fractionLength(0...2))
                )
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .textFieldStyle(.roundedBorder)
            } else {
                TextField(
                    "Units",
                    value: binding(for: item),
                    format: .number.precision(.fractionLength(0))
                )
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var applyButton: some View {
        Button {
            applyCounts()
        } label: {
            Text("Apply Counts")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(items.isEmpty)
    }

    private func seedCountsIfNeeded() {
        guard !hasSeeded else { return }
        hasSeeded = true
        var seeded: [UUID: Double] = [:]
        for item in items {
            seeded[item.id] = defaultCount(for: item)
        }
        counts = seeded
    }

    private func defaultCount(for item: InventoryItemEntity) -> Double {
        if item.isLiquid {
            return max(0, Double(item.looseUnits) + item.gallonFraction)
        }
        let totalUnits = item.unitsPerCase > 0
            ? Double(item.quantity * item.unitsPerCase + item.looseUnits)
            : Double(item.quantity)
        return max(0, totalUnits)
    }

    private func binding(for item: InventoryItemEntity) -> Binding<Double> {
        Binding(
            get: { counts[item.id] ?? defaultCount(for: item) },
            set: { counts[item.id] = max(0, $0) }
        )
    }

    private func currentCountLabel(for item: InventoryItemEntity) -> String {
        if item.isLiquid {
            return "Current: \(formattedGallons(defaultCount(for: item))) gallons"
        }
        let units = Int(defaultCount(for: item))
        return units == 1 ? "Current: 1 unit" : "Current: \(units) units"
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

    private func applyCounts() {
        let now = Date()
        for item in items {
            guard let count = counts[item.id] else { continue }
            if item.isLiquid {
                let totalGallons = max(0, count)
                let whole = floor(totalGallons)
                let fraction = totalGallons - whole
                item.looseUnits = Int64(whole)
                item.gallonFraction = fraction
            } else {
                let totalUnits = Int64(max(0, count.rounded()))
                if item.unitsPerCase > 0 {
                    item.quantity = totalUnits / item.unitsPerCase
                    item.looseUnits = totalUnits % item.unitsPerCase
                } else {
                    item.quantity = totalUnits
                    item.looseUnits = 0
                }
                item.looseEaches = 0
            }
            item.updatedAt = now
        }
        dataController.save()
        Haptics.success()
        dismiss()
    }
}
