// SPDX-License-Identifier: GPL-3.0-or-later
// macArmyKnife icon generator. Part of macArmyKnife, a modified version of
// Vorssaint (https://github.com/vorssaint/vorssaint-utils), changed 2026-11-23.
//
// Draws the macArmyKnife artwork from code, so the build never ships the
// Vorssaint icon or mark. Writes into the output directory:
//   AppIcon.icns          the Finder / Dock icon
//   AppIcon-1024.png      the same icon as a flat preview
//   MenuBarIcon.png       26×20 template glyph (1x)
//   MenuBarIcon@2x.png    52×40 template glyph (2x)
//   BrandMark.png         trimmed template glyph for in-app use (About, panel)
//
// The menu bar canvas must stay 26×20 points: the app's --selftest checks the
// bundled glyph against BlackHoleGlyph.pointSize.
//
// Usage: swift scripts/mak/MakeIcon.swift <output-dir>

import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/mak-icons"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: - Glyph geometry
//
// A fan of three tools opening from one rivet, in a 1000-unit design space
// with y pointing up. The tools are built pointing straight up from the pivot
// and then rotated into place.

let pivot = CGPoint(x: 500, y: 215)
let rivetRadius: CGFloat = 92
let rivetHoleRadius: CGFloat = 34

/// Knife: straight spine on the left, cutting edge curving up into the point.
func knifeBlade() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -58, y: 0))
    p.addLine(to: CGPoint(x: -58, y: 640))
    p.addLine(to: CGPoint(x: -40, y: 690))
    p.addQuadCurve(to: CGPoint(x: 58, y: 455), control: CGPoint(x: 64, y: 640))
    p.addLine(to: CGPoint(x: 58, y: 0))
    p.closeSubpath()
    return p
}

/// Screwdriver: narrow shaft with a squared, slightly tapered tip.
func screwdriverBlade() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -34, y: 0))
    p.addLine(to: CGPoint(x: -34, y: 500))
    p.addLine(to: CGPoint(x: -20, y: 560))
    p.addLine(to: CGPoint(x: 20, y: 560))
    p.addLine(to: CGPoint(x: 34, y: 500))
    p.addLine(to: CGPoint(x: 34, y: 0))
    p.closeSubpath()
    return p
}

/// Opener: wider tool with a rounded end and a hook notch.
func openerBlade() -> CGPath {
    let p = CGMutablePath()
    let half: CGFloat = 46
    p.move(to: CGPoint(x: -half, y: 0))
    p.addLine(to: CGPoint(x: -half, y: 470))
    p.addArc(center: CGPoint(x: 0, y: 470), radius: half,
             startAngle: .pi, endAngle: 0, clockwise: true)
    p.addLine(to: CGPoint(x: half, y: 410))
    p.addLine(to: CGPoint(x: 6, y: 385))
    p.addLine(to: CGPoint(x: half, y: 360))
    p.addLine(to: CGPoint(x: half, y: 0))
    p.closeSubpath()
    return p
}

func placed(_ path: CGPath, degrees: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: pivot.x, y: pivot.y)
        .rotated(by: degrees * .pi / 180)
    return path.copy(using: &t) ?? path
}

let tools: [CGPath] = [
    placed(screwdriverBlade(), degrees: 38),   // leans left
    placed(openerBlade(), degrees: -38),       // leans right
    placed(knifeBlade(), degrees: 0),          // center, on top
]

func rivetPath() -> CGPath {
    CGPath(ellipseIn: CGRect(x: pivot.x - rivetRadius, y: pivot.y - rivetRadius,
                             width: rivetRadius * 2, height: rivetRadius * 2), transform: nil)
}

func rivetHolePath() -> CGPath {
    CGPath(ellipseIn: CGRect(x: pivot.x - rivetHoleRadius, y: pivot.y - rivetHoleRadius,
                             width: rivetHoleRadius * 2, height: rivetHoleRadius * 2), transform: nil)
}

/// Bounding box of everything the glyph draws, in design units.
let glyphBounds: CGRect = {
    var box = rivetPath().boundingBoxOfPath
    for tool in tools { box = box.union(tool.boundingBoxOfPath) }
    return box
}()

/// Maps the design space onto `target`, keeping the aspect ratio and centering.
func fitTransform(into target: CGRect) -> CGAffineTransform {
    let scale = min(target.width / glyphBounds.width, target.height / glyphBounds.height)
    let w = glyphBounds.width * scale, h = glyphBounds.height * scale
    let ox = target.minX + (target.width - w) / 2
    let oy = target.minY + (target.height - h) / 2
    return CGAffineTransform(translationX: ox, y: oy)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -glyphBounds.minX, y: -glyphBounds.minY)
}

// MARK: - Canvas

func canvas(_ width: Int, _ height: Int) -> (NSBitmapImageRep, CGContext)? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let ns = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }
    let ctx = ns.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return (rep, ctx)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Template glyph: solid ink with the rivet hole punched through.
func drawTemplateGlyph(in ctx: CGContext, target: CGRect) {
    var t = fitTransform(into: target)
    ctx.saveGState()
    ctx.setFillColor(color(0x000000))
    for tool in tools {
        if let p = tool.copy(using: &t) { ctx.addPath(p); ctx.fillPath() }
    }
    if let p = rivetPath().copy(using: &t) { ctx.addPath(p); ctx.fillPath() }
    ctx.setBlendMode(.clear)
    if let p = rivetHolePath().copy(using: &t) { ctx.addPath(p); ctx.fillPath() }
    ctx.restoreGState()
}

// MARK: - App icon

func renderAppIcon(px: Int) -> Data? {
    guard let (rep, ctx) = canvas(px, px) else { return nil }
    let s = CGFloat(px) / 1024

    // macOS icon grid: an 824-point body centered on the 1024 canvas.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = CGPath(roundedRect: body, cornerWidth: 186 * s, cornerHeight: 186 * s, transform: nil)

    // Soft drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: color(0x000000, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x1E3A8A))
    ctx.fillPath()
    ctx.restoreGState()

    // Blue gradient body.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0x60A5FA), color(0x2563EB), color(0x1E3A8A)] as CFArray,
                              locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY),
                           end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    // The glyph, steel on blue, with a soft shadow for depth.
    let inset = body.insetBy(dx: 150 * s, dy: 140 * s)
    var t = fitTransform(into: inset)
    let steel = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0xFFFFFF), color(0xD5DCE6)] as CFArray,
                           locations: [0, 1])!
    for tool in tools {
        guard let p = tool.copy(using: &t) else { continue }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 14 * s, color: color(0x0B1B47, 0.45))
        ctx.addPath(p)
        ctx.setFillColor(color(0xE8EDF3))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        let box = p.boundingBoxOfPath
        ctx.drawLinearGradient(steel, start: CGPoint(x: box.minX, y: box.maxY),
                               end: CGPoint(x: box.maxX, y: box.minY), options: [])
        ctx.restoreGState()
    }
    if let rivet = rivetPath().copy(using: &t), let hole = rivetHolePath().copy(using: &t) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4 * s), blur: 10 * s, color: color(0x0B1B47, 0.5))
        ctx.addPath(rivet)
        ctx.setFillColor(color(0xF59E0B))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(hole)
        ctx.setFillColor(color(0xB45309))
        ctx.fillPath()
    }
    return rep.representation(using: .png, properties: [:])
}

// MARK: - ICNS

func appendFourCC(_ value: String, to data: inout Data) { data.append(contentsOf: Array(value.utf8)) }
func appendUInt32BE(_ value: Int, to data: inout Data) {
    var be = UInt32(value).bigEndian
    withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
}

// Same representation choice as Tools/MakeIcon.swift: current macOS misreads
// PNG payloads in the legacy small chunks, so only these types are written.
let icnsSizes: [(px: Int, type: String)] = [
    (32, "ic11"), (64, "ic12"), (128, "ic07"), (256, "ic13"),
    (256, "ic08"), (512, "ic14"), (512, "ic09"), (1024, "ic10"),
]
var icnsBody = Data()
for (px, type) in icnsSizes {
    guard let png = renderAppIcon(px: px) else { print("failed to render \(px)px icon"); exit(1) }
    appendFourCC(type, to: &icnsBody)
    appendUInt32BE(8 + png.count, to: &icnsBody)
    icnsBody.append(png)
}
var icns = Data()
appendFourCC("icns", to: &icns)
appendUInt32BE(8 + icnsBody.count, to: &icns)
icns.append(icnsBody)
try icns.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon.icns"))
if let preview = renderAppIcon(px: 1024) {
    try preview.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-1024.png"))
}

// MARK: - Menu bar glyph (template), 26×20 points

let menuBarCanvas = (width: 26, height: 20)
let menuBarInkHeight: CGFloat = 16

for scale in [1, 2] {
    let w = menuBarCanvas.width * scale, h = menuBarCanvas.height * scale
    guard let (rep, ctx) = canvas(w, h) else { print("failed menu bar canvas"); exit(1) }
    let ink = menuBarInkHeight * CGFloat(scale)
    let target = CGRect(x: 0, y: (CGFloat(h) - ink) / 2, width: CGFloat(w), height: ink)
    drawTemplateGlyph(in: ctx, target: target)
    rep.size = NSSize(width: menuBarCanvas.width, height: menuBarCanvas.height)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    let suffix = scale == 1 ? "" : "@2x"
    try data.write(to: URL(fileURLWithPath: "\(outDir)/MenuBarIcon\(suffix).png"))
}

// MARK: - Brand mark (template), trimmed to the glyph

let markWidth = 640
let markHeight = Int((CGFloat(markWidth) * glyphBounds.height / glyphBounds.width).rounded())
if let (rep, ctx) = canvas(markWidth, markHeight) {
    drawTemplateGlyph(in: ctx, target: CGRect(x: 0, y: 0, width: CGFloat(markWidth), height: CGFloat(markHeight)))
    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: "\(outDir)/BrandMark.png"))
    }
}
print("macArmyKnife icons written to \(outDir)")
