import SwiftUI
import AVFoundation
import Vision
import UIKit

struct BarcodeScanView: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingPhotoPicker = false
    @State private var photoImage: UIImage?
    @State private var statusText = "Point the camera at a barcode."
    @State private var isDetectingPhoto = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()

                VStack(spacing: 16) {
                    scannerCard
                    actionBar
                    if let photoImage {
                        photoPreview(image: photoImage)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(Theme.accent)
            .sheet(isPresented: $isPresentingPhotoPicker) {
                ImagePicker(image: $photoImage, sourceType: .photoLibrary)
                    .ignoresSafeArea()
            }
            .onChange(of: photoImage) { _, newValue in
                guard let image = newValue else { return }
                scanPhoto(image)
            }
        }
    }

    private var scannerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live Scan")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
            LiveBarcodeScannerView { code in
                handleScan(code)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(statusText)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
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

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                isPresentingPhotoPicker = true
            } label: {
                Label("Scan Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)

            if isDetectingPhoto {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func photoPreview(image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photo Preview")
                .font(Theme.sectionFont())
                .foregroundStyle(Theme.textSecondary)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func handleScan(_ code: String) {
        onScan(code)
        dismiss()
    }

    private func scanPhoto(_ image: UIImage) {
        isDetectingPhoto = true
        statusText = "Scanning photo..."
        detectBarcode(in: image) { result in
            DispatchQueue.main.async {
                isDetectingPhoto = false
                if let result {
                    statusText = "Barcode detected."
                    handleScan(result)
                } else {
                    statusText = "No barcode found. Try another photo."
                }
            }
        }
    }

    private func detectBarcode(in image: UIImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
                let results = request.results?.compactMap { $0.payloadStringValue } ?? []
                completion(results.first)
            } catch {
                completion(nil)
            }
        }
    }
}

private struct LiveBarcodeScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerController {
        BarcodeScannerController(onFound: onFound)
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerController, context: Context) {}
}

private final class BarcodeScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onFound: (String) -> Void
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasFoundCode = false

    init(onFound: @escaping (String) -> Void) {
        self.onFound = onFound
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [
            .ean8,
            .ean13,
            .upce,
            .code128,
            .code39,
            .code93,
            .qr,
            .pdf417,
            .dataMatrix
        ]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasFoundCode else { return }
        if let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let value = object.stringValue {
            hasFoundCode = true
            session.stopRunning()
            onFound(value)
        }
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
