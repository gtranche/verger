// Met une illustration carree a la forme des icones macOS : un carre arrondi de
// 824 points dans un canevas de 1024, avec son ombre.
//   swift Scripts/icone.swift <source.png> <sortie.png> [taille]
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3, let source = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("usage : icone.swift <source.png> <sortie.png> [taille]\n".utf8))
    exit(2)
}
let size = arguments.count > 3 ? CGFloat(Double(arguments[3]) ?? 1024) : 1024

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high

let frame = NSRect(x: size * 0.0977, y: size * 0.0977, width: size * 0.8046, height: size * 0.8046)
let shape = NSBezierPath(roundedRect: frame, xRadius: size * 0.181, yRadius: size * 0.181)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
shadow.shadowBlurRadius = size * 0.02
shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()
shape.addClip()
source.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
