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
        .appendingPathComponent("AppIconSource/pulse_remote_luxury_glow.png")
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

// Background.
ctx.setFillColor(rgba(5, 7, 20))
ctx.fill(rect)
drawLinearGradient(
    [rgba(7, 9, 28), rgba(16, 13, 35), rgba(13, 20, 43)],
    [0, 0.56, 1],
    CGPoint(x: 0, y: canvasSize),
    CGPoint(x: canvasSize, y: 0)
)
drawRadialGlow(center: CGPoint(x: 760, y: 780), radius: 370, color: rgba(255, 82, 168), alpha: 0.18)
drawRadialGlow(center: CGPoint(x: 255, y: 250), radius: 330, color: rgba(39, 205, 255), alpha: 0.16)
drawRadialGlow(center: CGPoint(x: 520, y: 150), radius: 280, color: rgba(255, 196, 94), alpha: 0.10)

// Tile.
let tileRect = CGRect(x: 120, y: 120, width: 784, height: 784)
let tilePath = CGPath(
    roundedRect: tileRect,
    cornerWidth: 150,
    cornerHeight: 150,
    transform: nil
)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 34, color: rgba(0, 0, 0, 0.62))
ctx.addPath(tilePath)
ctx.setFillColor(rgba(20, 22, 44, 0.96))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
drawLinearGradient(
    [rgba(73, 76, 101, 0.95), rgba(29, 32, 56, 0.95)],
    [0, 1],
    CGPoint(x: tileRect.minX, y: tileRect.maxY),
    CGPoint(x: tileRect.maxX, y: tileRect.minY)
)
ctx.setFillColor(rgba(255, 255, 255, 0.035))
ctx.fill(CGRect(x: tileRect.minX, y: tileRect.minY, width: tileRect.width, height: tileRect.height * 0.48))
ctx.setFillColor(rgba(0, 0, 0, 0.07))
ctx.fill(CGRect(x: tileRect.minX, y: tileRect.midY, width: tileRect.width, height: tileRect.height * 0.5))
ctx.restoreGState()

ctx.addPath(tilePath)
ctx.setStrokeColor(rgba(232, 236, 255, 0.36))
ctx.setLineWidth(4)
ctx.strokePath()

let center = CGPoint(x: 512, y: 512)
let ringRadius: CGFloat = 252

// Premium glow stack.
strokeArc(center: center, radius: ringRadius, start: 26, end: 230, lineWidth: 54, color: rgba(255, 84, 170), alpha: 0.16)
strokeArc(center: center, radius: ringRadius, start: 202, end: 386, lineWidth: 56, color: rgba(78, 220, 255), alpha: 0.16)
strokeArc(center: center, radius: ringRadius + 6, start: 0, end: 360, lineWidth: 7, color: rgba(255, 205, 113), alpha: 0.24)

// Main ring.
strokeArc(center: center, radius: ringRadius, start: 24, end: 226, lineWidth: 23, color: rgba(255, 88, 170))
strokeArc(center: center, radius: ringRadius, start: 206, end: 384, lineWidth: 23, color: rgba(94, 226, 255))

// Highlight ring and luxury gold accent.
strokeArc(center: center, radius: ringRadius, start: 30, end: 220, lineWidth: 5, color: rgba(255, 214, 236), alpha: 0.58)
strokeArc(center: center, radius: ringRadius, start: 216, end: 376, lineWidth: 5, color: rgba(220, 250, 255), alpha: 0.56)
strokeArc(center: center, radius: ringRadius + 2, start: 54, end: 165, lineWidth: 5, color: rgba(255, 212, 131), alpha: 0.78)
strokeArc(center: center, radius: ringRadius + 2, start: 244, end: 332, lineWidth: 5, color: rgba(255, 212, 131), alpha: 0.66)

strokeArc(center: center, radius: 279, start: 0, end: 360, lineWidth: 3, color: rgba(220, 226, 250), alpha: 0.19)
strokeArc(center: center, radius: 227, start: 0, end: 360, lineWidth: 3, color: rgba(180, 190, 230), alpha: 0.25)

let powerCenter = CGPoint(x: 512, y: 470)

// Power symbol glow + body.
strokeArc(center: powerCenter, radius: 122, start: 40, end: 320, lineWidth: 92, color: rgba(255, 48, 127), alpha: 0.18)
strokeArc(center: powerCenter, radius: 122, start: 40, end: 320, lineWidth: 60, color: rgba(232, 36, 102), alpha: 0.99)
strokeArc(center: powerCenter, radius: 122, start: 54, end: 306, lineWidth: 22, color: rgba(255, 141, 191), alpha: 0.45)

ctx.saveGState()
ctx.setLineCap(.round)
ctx.setStrokeColor(rgba(232, 36, 102))
ctx.setLineWidth(60)
ctx.move(to: CGPoint(x: 512, y: 540))
ctx.addLine(to: CGPoint(x: 512, y: 670))
ctx.strokePath()

ctx.setStrokeColor(rgba(255, 154, 198, 0.50))
ctx.setLineWidth(22)
ctx.move(to: CGPoint(x: 512, y: 552))
ctx.addLine(to: CGPoint(x: 512, y: 664))
ctx.strokePath()
ctx.restoreGState()

// Metallic top sparkle.
drawRadialGlow(center: CGPoint(x: 430, y: 655), radius: 95, color: rgba(255, 209, 120), alpha: 0.10)
drawRadialGlow(center: CGPoint(x: 616, y: 420), radius: 120, color: rgba(255, 225, 150), alpha: 0.08)
drawRadialGlow(center: CGPoint(x: 512, y: 478), radius: 148, color: rgba(255, 68, 140), alpha: 0.16)

// Glass highlight band.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let highlight = CGRect(x: tileRect.minX + 40, y: tileRect.maxY - 250, width: tileRect.width - 80, height: 130)
ctx.setFillColor(rgba(255, 255, 255, 0.07))
ctx.fillEllipse(in: highlight)
ctx.restoreGState()

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

print("Generated luxury logo at: \(outputURL.path)")
