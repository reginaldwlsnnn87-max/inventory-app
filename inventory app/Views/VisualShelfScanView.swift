import SwiftUI
import CoreData
import UIKit
import Vision

private struct ShelfScanTag: Identifiable {
    let id = UUID()
    let item: InventoryItemEntity
    var count: Double
    var isConfirmed: Bool
    var position: CGPoint?
}

struct VisualShelfScanView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var dataController: InventoryDataController
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InventoryItemEntity.name, ascending: true)],
        animation: .default
    )
    private var items: FetchedResults<InventoryItemEntity>

    @State private var capturedImage: UIImage?
    @State private var lastScanImage: UIImage?
    @State private var isPresentingImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .camera
    @State private var tags: [ShelfScanTag] = []
    @State private var pendingTagPosition: CGPoint?
    @State private var isPresentingTagPicker = false
    @State private var showAlignment = true
    @State private var isTaggingEnabled = true
    @State private var isAutoDetectEnabled = false
    @State private var lastDetectionAt: Date?
    @State private var isDetecting = false
    @State private var detectionStatus: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                ScrollView {
                    VStack(spacing: 16) {
                        headerView
                        captureCard
                        if capturedImage != nil {
                            reviewCard
                            suggestionsCard
                            taggedItemsCard
                            applyButton
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Shelf Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset") {
                        capturedImage = nil
                        tags = []
                    }
                    .disabled(capturedImage == nil)
                }
            }
            .tint(Theme.accent)
            .sheet(isPresented: $isPresentingImagePicker) {
                ImagePicker(image: $capturedImage, sourceType: imagePickerSource)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $isPresentingTagPicker) {
                ItemSelectionView(title: "Tag Item", items: Array(items)) { item in
                    addTag(for: item, position: pendingTagPosition)
                    pendingTagPosition = nil
                }
            }
            .onAppear {
                lastScanImage = loadLastScanImage()
            }
            .onChange(of: capturedImage) { _, newValue in
                if newValue != nil {
                    seedSuggestionsIfNeeded()
                    if isAutoDetectEnabled {
                        runAutoDetection()
                    }
                }
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capture a shelf photo, tap items, and confirm counts.")
                .font(Theme.font(14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("Tip: Align your shot to the last scan for faster review.")
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capture")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
            if let image = capturedImage {
                shelfImageView(image: image)
            } else {
                placeholderImageView
            }
            HStack(spacing: 12) {
                Button {
                    imagePickerSource = .camera
                    isPresentingImagePicker = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                Button {
                    imagePickerSource = .photoLibrary
                    isPresentingImagePicker = true
                } label: {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
            }

            if lastScanImage != nil {
                Toggle("Align to last scan", isOn: $showAlignment)
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
            Toggle("Auto-detect items", isOn: $isAutoDetectEnabled)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .onChange(of: isAutoDetectEnabled) { _, newValue in
                    if newValue {
                        runAutoDetection()
                    }
                }

            Toggle("Tap to tag items", isOn: $isTaggingEnabled)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            if isAutoDetectEnabled {
                HStack(spacing: 12) {
                    Button {
                        runAutoDetection()
                    } label: {
                        Label("Run Detection", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDetecting)
                    if let lastDetectionAt {
                        Text("Updated \(lastDetectionAt.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.font(11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                if let detectionStatus {
                    Text(detectionStatus)
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Text("Auto-detect reads shelf labels offline. Tap items to correct or add.")
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                Text("Tap the photo to tag items and confirm counts below.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Tags")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
            if suggestedItems.isEmpty {
                Text("Add items from the photo to begin.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(suggestedItems) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(Theme.font(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(item.category.isEmpty ? "Uncategorized" : item.category)
                                .font(Theme.font(11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button("Add") {
                            addTag(for: item, position: nil)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var taggedItemsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tagged Items")
                    .font(Theme.sectionFont())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if !tags.isEmpty {
                    Button("Confirm All") {
                        tags = tags.map { tag in
                            var updated = tag
                            updated.isConfirmed = true
                            return updated
                        }
                    }
                    .font(Theme.font(12, weight: .semibold))
                }
            }

            if tags.isEmpty {
                Text("No tagged items yet.")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach($tags) { $tag in
                    ShelfScanTagRow(tag: $tag) {
                        removeTag(tag.id)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
        .disabled(tags.isEmpty)
    }

    private var placeholderImageView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.backgroundBottom.opacity(0.6))
                .frame(height: 220)
            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.textSecondary)
                Text("Capture or choose a shelf photo")
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func shelfImageView(image: UIImage) -> some View {
        GeometryReader { proxy in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showAlignment, let ghost = lastScanImage {
                    Image(uiImage: ghost)
                        .resizable()
                        .scaledToFit()
                        .opacity(0.18)
                }
                ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                    if let position = tag.position {
                        Text("\(index + 1)")
                            .font(Theme.font(11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(Theme.accent))
                            .position(
                                x: position.x * proxy.size.width,
                                y: position.y * proxy.size.height
                            )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard isTaggingEnabled else { return }
                        if isAutoDetectEnabled {
                            runAutoDetection()
                        }
                        let normalized = normalizedPoint(value.location, in: proxy.size)
                        pendingTagPosition = normalized
                        isPresentingTagPicker = true
                    }
            )
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var suggestedItems: [InventoryItemEntity] {
        let existing = Set(tags.map { $0.item.id })
        return items
            .filter { !existing.contains($0.id) }
            .prefix(4)
            .map { $0 }
    }

    private func addTag(for item: InventoryItemEntity, position: CGPoint?) {
        guard !tags.contains(where: { $0.item.id == item.id }) else { return }
        let tag = ShelfScanTag(
            item: item,
            count: defaultCount(for: item),
            isConfirmed: false,
            position: position
        )
        tags.append(tag)
    }

    private func removeTag(_ id: UUID) {
        tags.removeAll { $0.id == id }
    }

    private func seedSuggestionsIfNeeded() {
        guard tags.isEmpty else { return }
        let suggestions = items.prefix(3)
        for item in suggestions {
            addTag(for: item, position: nil)
        }
    }

    private func runAutoDetection() {
        guard let image = capturedImage, !isDetecting else { return }
        isDetecting = true
        detectionStatus = "Scanning shelf labels..."

        Task.detached(priority: .userInitiated) {
            let detected = await detectItems(in: image, items: Array(items))
            await MainActor.run {
                mergeDetectedTags(detected)
                lastDetectionAt = Date()
                isDetecting = false
                detectionStatus = detected.isEmpty ? "No readable labels found. Try a closer shot." : "Detection ready. Tap to confirm."
            }
        }
    }

    private func mergeDetectedTags(_ detected: [ShelfScanTag]) {
        guard !detected.isEmpty else { return }
        var existing = Dictionary(uniqueKeysWithValues: tags.map { ($0.item.id, $0) })
        for tag in detected {
            if var current = existing[tag.item.id] {
                if current.position == nil {
                    current.position = tag.position
                }
                existing[tag.item.id] = current
            } else {
                existing[tag.item.id] = tag
            }
        }
        tags = Array(existing.values)
    }

    private func detectItems(in image: UIImage, items: [InventoryItemEntity]) async -> [ShelfScanTag] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let matches = matchItems(items, observations: observations)
                    continuation.resume(returning: matches)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func matchItems(
        _ items: [InventoryItemEntity],
        observations: [VNRecognizedTextObservation]
    ) -> [ShelfScanTag] {
        guard !observations.isEmpty else { return [] }
        let recognized: [(text: String, position: CGPoint)] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let normalized = CGPoint(
                x: observation.boundingBox.midX,
                y: 1 - observation.boundingBox.midY
            )
            return (candidate.string, normalized)
        }

        var bestByItem: [UUID: (score: Int, position: CGPoint?)] = [:]
        for item in items {
            let itemName = item.name
            for entry in recognized {
                let score = matchScore(itemName: itemName, text: entry.text)
                guard score > 0 else { continue }
                let current = bestByItem[item.id]
                if current == nil || score > current?.score ?? 0 {
                    bestByItem[item.id] = (score, entry.position)
                }
            }
        }

        let ranked = bestByItem
            .map { entry -> (InventoryItemEntity, Int, CGPoint?)? in
                guard let item = items.first(where: { $0.id == entry.key }) else { return nil }
                return (item, entry.value.score, entry.value.position)
            }
            .compactMap { $0 }
            .sorted { $0.1 > $1.1 }
            .prefix(6)

        return ranked.map { item, _, position in
            ShelfScanTag(
                item: item,
                count: defaultCount(for: item),
                isConfirmed: false,
                position: position
            )
        }
    }

    private func matchScore(itemName: String, text: String) -> Int {
        let normalizedItem = itemName.lowercased()
        let normalizedText = text.lowercased()
        let itemTokens = tokenize(normalizedItem)
        let textTokens = tokenize(normalizedText)

        var score = 0
        if normalizedText.contains(normalizedItem) || normalizedItem.contains(normalizedText) {
            if min(normalizedItem.count, normalizedText.count) > 2 {
                score += 3
            }
        }
        let overlap = Set(itemTokens).intersection(textTokens).count
        score += overlap
        return score
    }

    private func tokenize(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
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

    private func normalizedPoint(_ location: CGPoint, in size: CGSize) -> CGPoint {
        let x = min(max(location.x / max(size.width, 1), 0), 1)
        let y = min(max(location.y / max(size.height, 1), 0), 1)
        return CGPoint(x: x, y: y)
    }

    private func applyCounts() {
        guard !tags.isEmpty else { return }
        let now = Date()
        for tag in tags {
            let item = tag.item
            if item.isLiquid {
                let totalGallons = max(0, tag.count)
                let whole = floor(totalGallons)
                let fraction = totalGallons - whole
                item.looseUnits = Int64(whole)
                item.gallonFraction = fraction
            } else {
                let totalUnits = Int64(max(0, tag.count.rounded()))
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
        if let image = capturedImage {
            saveLastScanImage(image)
        }
        Haptics.success()
        dismiss()
    }

    private func loadLastScanImage() -> UIImage? {
        guard let data = try? Data(contentsOf: lastScanURL),
              let image = UIImage(data: data)
        else { return nil }
        return image
    }

    private func saveLastScanImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return }
        try? data.write(to: lastScanURL, options: [.atomic])
    }

    private var lastScanURL: URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (directory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("last_shelf_scan.jpg")
    }
}

private struct ShelfScanTagRow: View {
    @Binding var tag: ShelfScanTag
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tag.item.name)
                        .font(Theme.font(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(tag.item.isLiquid ? "Gallons" : "Units")
                        .font(Theme.font(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    tag.isConfirmed.toggle()
                } label: {
                    Image(systemName: tag.isConfirmed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(tag.isConfirmed ? Theme.accent : Theme.textTertiary)
                }
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
            }

            if tag.item.isLiquid {
                TextField(
                    "Gallons",
                    value: $tag.count,
                    format: .number.precision(.fractionLength(0...2))
                )
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .textFieldStyle(.roundedBorder)
            } else {
                Stepper(value: unitBinding, in: 0...1_000_000) {
                    HStack {
                        Text("Count")
                        Spacer()
                        Text("\(Int(unitBinding.wrappedValue))")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }

    private var unitBinding: Binding<Int> {
        Binding(
            get: { Int(max(0, tag.count.rounded())) },
            set: { tag.count = Double(max(0, $0)) }
        )
    }
}

private struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            if let selected = info[.originalImage] as? UIImage {
                parent.image = selected
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
