import SwiftUI
import AppKit

let fieldInk = Color(red: 0.11, green: 0.14, blue: 0.085)
let fieldCream = Color(red: 0.89, green: 0.86, blue: 0.72)
let fieldBrass = Color(red: 0.76, green: 0.70, blue: 0.40)

// The texture is loaded once; scanning does not decode or regenerate the artwork.
private enum PanelArtwork {
    static let bare: NSImage = {
        guard let url = Bundle.main.url(forResource: "AgedPanelBare", withExtension: "png"), let image = NSImage(contentsOf: url) else { return NSImage() }
        image.size = NSSize(width: 640, height: 640 * image.size.height / image.size.width)
        return image
    }()
    static let metal: NSImage = {
        guard let url = Bundle.main.url(forResource: "AgedPanel", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        image.size = NSSize(width: 640, height: 640 * image.size.height / image.size.width)
        return image
    }()
}

struct AirframeSkin: View {
    var scanning = false
    var body: some View {
        GeometryReader { geometry in
            // Preserve the painted title and panel edges within the fixed app window.
            Image(nsImage: scanning ? PanelArtwork.bare : PanelArtwork.metal)
                .resizable(capInsets: EdgeInsets(top: 205, leading: 480, bottom: 30, trailing: 100), resizingMode: .stretch)
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .overlay(Color.black.opacity(0.12))
                .overlay(LinearGradient(colors: [.black.opacity(0.05), .clear, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.6), lineWidth: 2))
        }.background(Color(red: 0.23, green: 0.25, blue: 0.16))
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Small gaps in the pigment reveal the actual surface beneath the lettering.
/// The deterministic mask preserves native text and its accessibility label.
struct PaintWear: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            context.blendMode = .destinationOut
            let count = min(2400, Int(size.width * size.height / 11))
            for n in 0..<count {
                let x = CGFloat((n * 127 + 43) % 2003) / 2003 * size.width
                let y = CGFloat((n * 337 + 17) % 1999) / 1999 * size.height
                let width = n % 13 == 0 ? CGFloat(2 + n % 4) : CGFloat(0.4 + Double(n % 4) * 0.25)
                context.fill(Path(CGRect(x: x, y: y, width: width, height: n % 13 == 0 ? 0.55 : 0.8)), with: .color(.white.opacity(n % 3 == 0 ? 0.8 : 0.4)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct PaintedText: View {
    let text: String
    var size: CGFloat = 38
    var body: some View {
        Text(text).font(.custom("SignPainter-HouseScriptSemibold", size: size))
            // Script swashes extend outside the font's line box. Expand the mask to include them.
            .padding(.horizontal, size * 0.18).padding(.vertical, size * 0.18)
            .foregroundStyle(fieldCream).mask(PaintWear())
            .shadow(color: .black.opacity(0.25), radius: 0.3, x: 0, y: 0.6)
    }
}

struct PaperWear: View {
    var body: some View {
        Canvas { context, size in
            for n in 0..<1600 {
                let x = CGFloat((n * 131 + 19) % 2011) / 2011 * size.width
                let y = CGFloat((n * 313 + 47) % 1999) / 1999 * size.height
                context.fill(Path(CGRect(x: x, y: y, width: n % 17 == 0 ? 5 : 0.8, height: 0.6)), with: .color(fieldInk.opacity(n % 3 == 0 ? 0.12 : 0.04)))
            }
            var crease = Path()
            crease.move(to: CGPoint(x: size.width * 0.63, y: 0))
            crease.addLine(to: CGPoint(x: size.width * 0.61, y: size.height))
            context.stroke(crease, with: .color(fieldInk.opacity(0.08)), lineWidth: 1.5)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ReceiptPaper: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: 0, y: 5))
        for x in stride(from: CGFloat(0), through: rect.width, by: 8) {
            p.addLine(to: CGPoint(x: min(x + 4, rect.width), y: 0))
            p.addLine(to: CGPoint(x: min(x + 8, rect.width), y: 5))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - 5))
        for x in stride(from: rect.width, through: 0, by: -8) {
            p.addLine(to: CGPoint(x: max(0, x - 4), y: rect.height))
            p.addLine(to: CGPoint(x: max(0, x - 8), y: rect.height - 5))
        }
        p.closeSubpath(); return p
    }
}
