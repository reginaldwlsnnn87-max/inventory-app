import SwiftUI
import CoreData

struct QuickStockAdjustView: View {
    @EnvironmentObject private var dataController: InventoryDataController
    @Environment(\.dismiss) private var dismiss

    let item: InventoryItemEntity

    @State private var mode: AdjustMode = .stockIn
    @State private var amount: Double = 1

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                VStack(spacing: 16) {
                    headerCard
                    modePicker
                    amountCard
                    applyButton
                }
                .padding(16)
            }
            .navigationTitle("Stock In / Out")
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
        .onAppear {
            amount = item.isLiquid ? 0.5 : 1
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(Theme.font(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(onHandLabel)
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

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(AdjustMode.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.isLiquid ? "Gallons" : "Units")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)

            if item.isLiquid {
                TextField(
                    "Gallons",
                    value: $amount,
                    format: .number.precision(.fractionLength(0...2))
                )
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .textFieldStyle(.roundedBorder)
            } else {
                Stepper(value: unitsBinding, in: 1...10_000) {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("\(Int(unitsBinding.wrappedValue))")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
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
            applyAdjustment()
        } label: {
            Text(mode == .stockIn ? "Apply Stock In" : "Apply Stock Out")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var onHandUnits: Int64 {
        if item.isLiquid {
            let gallons = Double(item.looseUnits) + item.gallonFraction
            return Int64((gallons * 128).rounded())
        }
        let units = item.unitsPerCase > 0
            ? item.quantity * item.unitsPerCase + item.looseUnits
            : item.quantity
        return units
    }

    private var onHandLabel: String {
        if item.isLiquid {
            let gallons = Double(item.looseUnits) + item.gallonFraction
            return "On hand \(formattedGallons(gallons)) gallons"
        }
        return "On hand \(onHandUnits) units"
    }

    private var unitsBinding: Binding<Int> {
        Binding(
            get: { Int(max(1, amount.rounded())) },
            set: { amount = Double(max(1, $0)) }
        )
    }

    private func applyAdjustment() {
        let delta = mode == .stockIn ? amount : -amount
        if item.isLiquid {
            let currentGallons = Double(item.looseUnits) + item.gallonFraction
            let updated = max(0, currentGallons + delta)
            let whole = floor(updated)
            let fraction = updated - whole
            item.looseUnits = Int64(whole)
            item.gallonFraction = fraction
        } else {
            let currentUnits = Double(onHandUnits)
            let updatedUnits = max(0, currentUnits + delta)
            let totalUnits = Int64(updatedUnits.rounded())
            if item.unitsPerCase > 0 {
                item.quantity = totalUnits / item.unitsPerCase
                item.looseUnits = totalUnits % item.unitsPerCase
            } else {
                item.quantity = totalUnits
                item.looseUnits = 0
            }
        }
        item.updatedAt = Date()
        dataController.save()
        Haptics.success()
        dismiss()
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
}

private enum AdjustMode: String, CaseIterable, Identifiable {
    case stockIn = "Stock In"
    case stockOut = "Stock Out"

    var id: String { rawValue }

    var label: String { rawValue }
}
