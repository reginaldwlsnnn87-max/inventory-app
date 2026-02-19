#!/usr/bin/swift

import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct Config {
    let inputPath: String
    let outputPath: String
}

enum IconPolishError: Error, CustomStringConvertible {
    case couldNotLoadImage(String)
    case couldNotRenderImage
    case couldNotEncodePNG

    var description: String {
        switch self {
        case let .couldNotLoadImage(path):
            return "Could not load image at: \(path)"
        case .couldNotRenderImage:
            return "Could not render final image."
        case .couldNotEncodePNG:
            return "Could not encode PNG data."
        }
    }
}

func defaultConfig() -> Config {
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let brandingDir = scriptURL.deletingLastPathComponent()
    let sourceDir = brandingDir.appendingPathComponent("AppIconSource", isDirectory: true)
    let input = sourceDir.appendingPathComponent("app_icon.png").path
    let output = sourceDir.appendingPathComponent("pulse_remote.png").path
    return Config(inputPath: input, outputPath: output)
}

func parseConfig() -> Config {
    let fallback = defaultConfig()
    guard CommandLine.arguments.count >= 3 else { return fallback }
    return Config(inputPath: CommandLine.arguments[1], outputPath: CommandLine.arguments[2])
}

func polishedImage(from input: CIImage) -> CIImage {
    var image = input
    let extent = input.extent.integral

    let color = CIFilter.colorControls()
    color.inputImage = image
    color.saturation = 1.08
    color.brightness = 0.01
    color.contrast = 1.13
    image = color.outputImage?.cropped(to: extent) ?? image

    let vibrance = CIFilter.vibrance()
    vibrance.inputImage = image
    vibrance.amount = 0.32
    image = vibrance.outputImage?.cropped(to: extent) ?? image

    let sharpen = CIFilter.sharpenLuminance()
    sharpen.inputImage = image
    sharpen.sharpness = 0.42
    image = sharpen.outputImage?.cropped(to: extent) ?? image

    let bloom = CIFilter.bloom()
    bloom.inputImage = image
    bloom.radius = 5.5
    bloom.intensity = 0.14
    image = bloom.outputImage?.cropped(to: extent) ?? image

    let vignette = CIFilter.vignette()
    vignette.inputImage = image
    vignette.intensity = 0.20
    vignette.radius = 1.35
    image = vignette.outputImage?.cropped(to: extent) ?? image

    let highlightShadow = CIFilter.highlightShadowAdjust()
    highlightShadow.inputImage = image
    highlightShadow.shadowAmount = 0.15
    highlightShadow.highlightAmount = 0.92
    image = highlightShadow.outputImage?.cropped(to: extent) ?? image

    return image.cropped(to: extent)
}

func renderPNG(from image: CIImage, to outputURL: URL) throws {
    let context = CIContext(options: [
        .cacheIntermediates: true,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    guard let cg = context.createCGImage(image, from: image.extent.integral) else {
        throw IconPolishError.couldNotRenderImage
    }

    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = NSSize(width: image.extent.width, height: image.extent.height)

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw IconPolishError.couldNotEncodePNG
    }

    try pngData.write(to: outputURL, options: .atomic)
}

@discardableResult
func run() throws -> Config {
    let config = parseConfig()
    let inputURL = URL(fileURLWithPath: config.inputPath)
    let outputURL = URL(fileURLWithPath: config.outputPath)

    guard let inputImage = CIImage(contentsOf: inputURL) else {
        throw IconPolishError.couldNotLoadImage(config.inputPath)
    }

    let polished = polishedImage(from: inputImage)
    try renderPNG(from: polished, to: outputURL)
    return config
}

do {
    let config = try run()
    print("Polished icon written to: \(config.outputPath)")
} catch let error as IconPolishError {
    fputs("error: \(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
