// Draws the 1024×1024 app icon: a lined notepad on a blue rounded square.
// Usage: make-icon <output.png>

import AppKit

let output = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Background
let background = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: color(0.55, 0.74, 0.93), ending: color(0.22, 0.45, 0.78))!.draw(in: background, angle: -90)

// Paper with shadow
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0, 0, 0, 0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
color(1, 1, 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 245, y: 185, width: 534, height: 610), xRadius: 26, yRadius: 26).fill()
NSGraphicsContext.restoreGraphicsState()

// Ruled lines
color(0.60, 0.74, 0.90).setStroke()
for i in 0..<9 {
    let y = 245.0 + Double(i) * 56
    let line = NSBezierPath()
    line.lineWidth = 7
    line.move(to: NSPoint(x: 285, y: y))
    line.line(to: NSPoint(x: 740, y: y))
    line.stroke()
}

// Margin
color(0.90, 0.36, 0.36).setStroke()
let margin = NSBezierPath()
margin.lineWidth = 6
margin.move(to: NSPoint(x: 345, y: 205))
margin.line(to: NSPoint(x: 345, y: 730))
margin.stroke()

// Spiral binding
color(0.32, 0.34, 0.38).setFill()
for i in 0..<7 {
    let x = 297.0 + Double(i) * 70
    NSBezierPath(roundedRect: NSRect(x: x, y: 750, width: 28, height: 92), xRadius: 14, yRadius: 14).fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
