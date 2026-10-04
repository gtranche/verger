// Le logo de Verger : une pomme et deux collines sur fond bleu nuit, dessinees
// en formes simples pour rester nettes a toutes les tailles.
// Sort l'illustration en 1024 x 1024, plein cadre ; la forme d'icone de macOS
// est appliquee ensuite par icone.swift.
//   swift Scripts/logo.swift <sortie.png>
import AppKit

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let nuit = rgb(0x0D1320)
let rougeHaut = rgb(0xFF5A3A), rougeBas = rgb(0xDD1F3A)
let vertClair = rgb(0x8EDB6C), vertFonce = rgb(0x17876B), vertMoyen = rgb(0x4DB36E)
let ecart: CGFloat = 26          // la separation sombre entre deux formes

func remplir(_ p: NSBezierPath, _ a: NSColor, _ b: NSColor, angle: CGFloat) {
    NSGradient(starting: a, ending: b)!.draw(in: p, angle: angle)
}
/// Detache une forme de ce qui est derriere elle par un lisere de la couleur du fond.
func detacher(_ p: NSBezierPath) {
    nuit.setStroke(); p.lineWidth = ecart * 2; p.lineJoinStyle = .round; p.stroke()
}
func pomme(cx: CGFloat = 512, cy: CGFloat = 470, e: CGFloat = 1) -> NSBezierPath {
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: cx + x * e, y: cy + y * e) }
    let p = NSBezierPath()
    p.move(to: pt(0, 150))                                   // le creux du haut
    p.curve(to: pt(-120, 215), controlPoint1: pt(-30, 185), controlPoint2: pt(-70, 215))
    p.curve(to: pt(-262, 60), controlPoint1: pt(-205, 215), controlPoint2: pt(-262, 150))
    p.curve(to: pt(-120, -215), controlPoint1: pt(-262, -60), controlPoint2: pt(-205, -180))
    p.curve(to: pt(0, -205), controlPoint1: pt(-75, -235), controlPoint2: pt(-35, -225))
    p.curve(to: pt(120, -215), controlPoint1: pt(35, -225), controlPoint2: pt(75, -235))
    p.curve(to: pt(262, 60), controlPoint1: pt(205, -180), controlPoint2: pt(262, -60))
    p.curve(to: pt(120, 215), controlPoint1: pt(262, 150), controlPoint2: pt(205, 215))
    p.curve(to: pt(0, 150), controlPoint1: pt(70, 215), controlPoint2: pt(30, 185))
    p.close()
    return p
}
func feuille(cx: CGFloat = 512, cy: CGFloat = 470, e: CGFloat = 1) {
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: cx + x * e, y: cy + y * e) }
    let f = NSBezierPath()
    f.move(to: pt(6, 190))
    f.curve(to: pt(200, 400), controlPoint1: pt(-20, 330), controlPoint2: pt(90, 400))
    f.curve(to: pt(6, 190), controlPoint1: pt(205, 270), controlPoint2: pt(120, 195))
    f.close()
    detacher(f)
    remplir(f, vertFonce, vertClair, angle: 60)
}
func queue(cx: CGFloat = 512, cy: CGFloat = 470, e: CGFloat = 1) {
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: cx + x * e, y: cy + y * e) }
    let q = NSBezierPath()
    q.move(to: pt(-14, 170))
    q.curve(to: pt(-95, 285), controlPoint1: pt(-25, 225), controlPoint2: pt(-55, 270))
    q.lineCapStyle = .round
    nuit.setStroke(); q.lineWidth = 30 * e + ecart * 1.4; q.stroke()
    rougeHaut.setStroke(); q.lineWidth = 30 * e; q.stroke()
}
/// Les collines : des ellipses, coupees en bas par un grand cercle (le « bol » du logo).
func collines(_ formes: [(NSRect, NSColor, NSColor)]) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: NSRect(x: 512 - 400, y: 130, width: 800, height: 800)).addClip()
    for (r, a, b) in formes {
        let p = NSBezierPath(ovalIn: r)
        detacher(p)
        remplir(p, a, b, angle: -70)
    }
    NSGraphicsContext.restoreGraphicsState()
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGradient(starting: rgb(0x0A0F1A), ending: rgb(0x141C2E))!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: 90)

let deuxCollines: [(NSRect, NSColor, NSColor)] = [
    (NSRect(x: 430, y: -190, width: 720, height: 500), vertMoyen, vertFonce),     // derriere, a droite
    (NSRect(x: -110, y: -220, width: 800, height: 560), vertClair, vertFonce),    // devant, a gauche
]
remplir(pomme(cy: 520), rougeHaut, rougeBas, angle: -60)
collines(deuxCollines)
queue(cy: 520)
feuille(cy: 520)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
