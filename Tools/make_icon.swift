import AppKit
// Gera um PNG 1024x1024 com o ícone do app.
let out = CommandLine.arguments[1]
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 100, dy: 100)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 1.0, green: 0.42, blue: 0.32, alpha: 1), NSColor(red: 0.85, green: 0.1, blue: 0.35, alpha: 1)])!
    .draw(in: path, angle: -90)
let emoji = "🖐️" as NSString
let font = NSFont.systemFont(ofSize: 520)
let attrs: [NSAttributedString.Key: Any] = [.font: font]
let s = emoji.size(withAttributes: attrs)
emoji.draw(at: NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2 - 10), withAttributes: attrs)
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
