#!/usr/bin/swift

import Foundation
import AppKit
import CoreGraphics

let outputPath: String = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments[1]
    }
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    return scriptURL
        .deletingLastPathComponent()
        .appendingPathComponent("AppIconSource/pulse_remote.png")
        .path
}()

let canvasSize = 1024
let rect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)

guard let ctx = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("error: could not create graphics context\n", stderr)
    exit(1)
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

func drawLinearGradient(
    _ colors: [CGColor],
    _ locations: [CGFloat],
    _ start: CGPoint,
    _ end: CGPoint
) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: colors as CFArray,
        locations: locations
    )!
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
}

func drawRadialGlow(center: CGPoint, radius: CGFloat, color: CGColor, alpha: CGFloat) {
    let transparent = color.copy(alpha: 0)!
    let strong = color.copy(alpha: alpha)!
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [strong, transparent] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: .drawsAfterEndLocation
    )
}

func deg(_ value: CGFloat) -> CGFloat {
    value * .pi / 180
}

func strokeArc(
    center: CGPoint,
    radius: CGFloat,
    start: CGFloat,
    end: CGFloat,
    lineWidth: CGFloat,
    color: CGColor,
    alpha: CGFloat = 1.0
) {
    ctx.saveGState()
    ctx.setStrokeColor(color.copy(alpha: alpha)!)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addArc(
        center: center,
        radius: radius,
        startAngle: deg(start),
        endAngle: deg(end),
        clockwise: false
    )
    ctx.strokePath()
    ctx.restoreGState()
}

ctx.interpolationQuality = .high
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// Base background.
ctx.setFillColor(rgba(6, 8, 22))
ctx.fill(rect)
drawLinearGradient(
    [rgba(8, 10, 28), rgba(18, 22, 44)],
    [0, 1],
    CGPoint(x: 0, y: canvasSize),
    CGPoint(x: canvasSize, y: 0)
)

// Ambient glow on background.
drawRadialGlow(center: CGPoint(x: 310, y: 720), radius: 340, color: rgba(30, 90, 255), alpha: 0.20)
drawRadialGlow(center: CGPoint(x: 760, y: 360), radius: 300, color: rgba(255, 50, 120), alpha: 0.18)

// Main rounded tile.
let tileRect = CGRect(x: 120, y: 120, width: 784, height: 784)
let tilePath = CGPath(
    roundedRect: tileRect,
    cornerWidth: 150,
    cornerHeight: 150,
    transform: nil
)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 30, color: rgba(0, 0, 0, 0.55))
ctx.addPath(tilePath)
ctx.setFillColor(rgba(21, 24, 46, 0.96))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
drawLinearGradient(
    [rgba(64, 67, 88, 0.95), rgba(26, 29, 52, 0.95)],
    [0, 1],
    CGPoint(x: tileRect.minX, y: tileRect.maxY),
    CGPoint(x: tileRect.maxX, y: tileRect.minY)
)
ctx.setFillColor(rgba(255, 255, 255, 0.04))
ctx.fill(CGRect(x: tileRect.midX, y: tileRect.minY, width: tileRect.width / 2, height: tileRect.height))
ctx.fill(CGRect(x: tileRect.minX, y: tileRect.midY, width: tileRect.width, height: tileRect.height / 2))
ctx.restoreGState()

ctx.addPath(tilePath)
ctx.setStrokeColor(rgba(225, 230, 255, 0.40))
ctx.setLineWidth(4)
ctx.strokePath()

let center = CGPoint(x: 512, y: 512)

// Ring glows.
strokeArc(
    center: center,
    radius: 252,
    start: 24,
    end: 226,
    lineWidth: 48,
    color: rgba(255, 56, 142),
    alpha: 0.15
)
strokeArc(
    center: center,
    radius: 252,
    start: 206,
    end: 384,
    lineWidth: 52,
    color: rgba(58, 207, 255),
    alpha: 0.17
)

// Main ring.
strokeArc(
    center: center,
    radius: 252,
    start: 24,
    end: 226,
    lineWidth: 22,
    color: rgba(255, 78, 156)
)
strokeArc(
    center: center,
    radius: 252,
    start: 206,
    end: 384,
    lineWidth: 22,
    color: rgba(86, 220, 255)
)

strokeArc(
    center: center,
    radius: 252,
    start: 34,
    end: 218,
    lineWidth: 5,
    color: rgba(255, 206, 230),
    alpha: 0.55
)
strokeArc(
    center: center,
    radius: 252,
    start: 218,
    end: 376,
    lineWidth: 5,
    color: rgba(208, 248, 255),
    alpha: 0.52
)

strokeArc(
    center: center,
    radius: 278,
    start: 0,
    end: 360,
    lineWidth: 3,
    color: rgba(204, 215, 255),
    alpha: 0.22
)
strokeArc(
    center: center,
    radius: 228,
    start: 0,
    end: 360,
    lineWidth: 3,
    color: rgba(174, 185, 232),
    alpha: 0.24
)

// Power symbol glow.
let powerCenter = CGPoint(x: 512, y: 470)
strokeArc(
    center: powerCenter,
    radius: 122,
    start: 40,
    end: 320,
    lineWidth: 88,
    color: rgba(255, 42, 112),
    alpha: 0.16
)

// Power symbol body.
strokeArc(
    center: powerCenter,
    radius: 122,
    start: 40,
    end: 320,
    lineWidth: 60,
    color: rgba(228, 36, 98),
    alpha: 0.98
)
strokeArc(
    center: powerCenter,
    radius: 122,
    start: 52,
    end: 306,
    lineWidth: 22,
    color: rgba(255, 130, 176),
    alpha: 0.42
)

ctx.saveGState()
ctx.setLineCap(.round)
ctx.setStrokeColor(rgba(230, 36, 98, 1.0))
ctx.setLineWidth(60)
ctx.move(to: CGPoint(x: 512, y: 540))
ctx.addLine(to: CGPoint(x: 512, y: 670))
ctx.strokePath()

ctx.setStrokeColor(rgba(255, 150, 186, 0.46))
ctx.setLineWidth(22)
ctx.move(to: CGPoint(x: 512, y: 552))
ctx.addLine(to: CGPoint(x: 512, y: 664))
ctx.strokePath()
ctx.restoreGState()

drawRadialGlow(center: CGPoint(x: 512, y: 474), radius: 138, color: rgba(255, 64, 128), alpha: 0.15)

guard let cgImage = ctx.makeImage() else {
    fputs("error: failed to create image output\n", stderr)
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("error: failed to encode PNG output\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL, options: .atomic)

print("Generated logo at: \(outputURL.path)")
