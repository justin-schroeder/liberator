import SwiftUI

private let scopeInk = Color(red: 0.045, green: 0.065, blue: 0.032)
private let scopeLight = Color(red: 0.78, green: 0.81, blue: 0.47)

struct RadarScanView: View {
    let radar: RadarState
    let found: Int
    let inspected: Int
    let startedAt: TimeInterval
    let onStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                PaintedText(text: "Scanning for enemies", size: 29)
                Spacer()
                Button("Stop", action: onStop).buttonStyle(CleanButton(quiet: true))
            }.padding(.horizontal, 12)
            GeometryReader { geometry in
                let diameter = min(geometry.size.width, geometry.size.height)
                ZStack {
                    RadarHousing()
                    // The timeline belongs only to the scope, not the scanner or results list.
                    TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { _ in
                        RadarReturns(contacts: radar.contacts, time: ProcessInfo.processInfo.systemUptime,
                                     startedAt: startedAt, reduceMotion: reduceMotion)
                    }.padding(17)
                }.frame(width: diameter, height: diameter)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 12) {
                Text("\(inspected.formatted()) inspected")
                Text("·")
                Text("\(found.formatted()) found").foregroundStyle(fieldCream)
            }.font(.custom("CourierNewPS-BoldMT", size: 12)).foregroundStyle(fieldCream.opacity(0.8))
            Text("Searching for quarantined apps and files…")
                .font(.system(size: 10)).foregroundStyle(fieldCream.opacity(0.6))
        }.padding(.top, 27).padding(.bottom, 20).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RadarHousing: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.48, green: 0.46, blue: 0.33), .black, Color(red: 0.30, green: 0.29, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.7), radius: 5, y: 3)
            Circle().strokeBorder(fieldCream.opacity(0.28), lineWidth: 1)
            Circle().inset(by: 5).strokeBorder(.black.opacity(0.7), lineWidth: 2)
            Circle().fill(RadialGradient(colors: [Color(red: 0.13, green: 0.17, blue: 0.07), scopeInk, .black], center: .center, startRadius: 0, endRadius: 165)).padding(12)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = size.width / 2 - 17
                for ring in 1...4 {
                    let r = radius * CGFloat(ring) / 4
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(scopeLight.opacity(0.18)), lineWidth: 0.6)
                }
                for n in 0..<72 {
                    let angle = Double(n) * .pi / 36
                    let major = n % 6 == 0
                    var tick = Path()
                    tick.move(to: point(center, radius - (major ? 7 : 3), angle))
                    tick.addLine(to: point(center, radius, angle))
                    context.stroke(tick, with: .color(scopeLight.opacity(major ? 0.5 : 0.22)), lineWidth: 0.7)
                }
                for angle in [0.0, Double.pi / 2] {
                    var line = Path(); line.move(to: point(center, radius, angle)); line.addLine(to: point(center, radius, angle + .pi))
                    context.stroke(line, with: .color(scopeLight.opacity(0.17)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
                for n in 0..<4 {
                    let angle = Double(n) * .pi / 2 + .pi / 4
                    let p = point(center, size.width / 2 - 7, angle)
                    let screw = CGRect(x: p.x - 2.3, y: p.y - 2.3, width: 4.6, height: 4.6)
                    context.fill(Path(ellipseIn: screw), with: .color(fieldCream.opacity(0.35)))
                    var slot = Path(); slot.move(to: CGPoint(x: p.x - 1.5, y: p.y + 1)); slot.addLine(to: CGPoint(x: p.x + 1.5, y: p.y - 1))
                    context.stroke(slot, with: .color(.black.opacity(0.9)), lineWidth: 0.9)
                }
                // Imperfect etched glass, fixed between frames.
                for n in 0..<380 {
                    let a = Double(n) * 2.39996323
                    let r = radius * sqrt(Double((n * 71) % 383) / 383)
                    let p = point(center, r, a)
                    context.fill(Path(CGRect(x: p.x, y: p.y, width: n % 19 == 0 ? 4 : 0.6, height: 0.4)), with: .color(scopeLight.opacity(0.06)))
                }
            }
            Circle().fill(LinearGradient(colors: [.white.opacity(0.05), .clear, .black.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(13)
        }.allowsHitTesting(false)
    }
}

private struct RadarReturns: View {
    let contacts: [RadarContact]
    let time: TimeInterval
    let startedAt: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2
            let sweep = reduceMotion ? -Double.pi / 3 : (time - startedAt) * .pi / 2.4 - .pi / 2
            context.clip(to: Path(ellipseIn: CGRect(origin: .zero, size: size)))
            // A dim broad persistence trail follows the bright mechanical-looking sweep.
            for step in 0..<36 {
                let angle = sweep - Double(step) * .pi / 100
                var wedge = Path(); wedge.move(to: center)
                wedge.addLine(to: point(center, radius, angle))
                wedge.addLine(to: point(center, radius, angle - .pi / 100)); wedge.closeSubpath()
                context.fill(wedge, with: .color(scopeLight.opacity(0.14 * pow(1 - Double(step) / 36, 2))))
            }
            var beam = Path(); beam.move(to: center); beam.addLine(to: point(center, radius, sweep))
            context.stroke(beam, with: .color(scopeLight.opacity(0.8)), lineWidth: 0.8)
            let visible = contacts.filter { $0.isVisible(at: time) }
            func beamDistance(_ contact: RadarContact) -> Double {
                let relative = (sweep - contact.bearing).truncatingRemainder(dividingBy: .pi * 2)
                return relative < 0 ? relative + .pi * 2 : relative
            }
            func location(_ contact: RadarContact) -> CGPoint {
                point(center, radius * contact.range(at: reduceMotion ? contact.born : time), contact.bearing)
            }
            func centerFade(_ contact: RadarContact) -> Double {
                min(1, max(0, (contact.range(at: time) - 0.12) / 0.09))
            }
            for contact in visible {
                let p = location(contact)
                let brightness = max(0.2, contact.opacity(at: time)) * centerFade(contact)
                    * (0.5 + 0.5 * exp(-beamDistance(contact) * 2))
                var echo = context; echo.opacity = brightness
                if !reduceMotion {
                    let behind = point(center, radius * min(0.98, contact.range(at: time) + 0.025), contact.bearing)
                    var wake = Path(); wake.move(to: behind); wake.addLine(to: p)
                    echo.stroke(wake, with: .color(scopeLight.opacity(0.3)), lineWidth: 1)
                }
                echo.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(scopeLight.opacity(0.1)))
                echo.fill(Path(CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6)), with: .color(scopeLight))
            }
            // Radar targets remain visible; readable callouts rotate with the sweep.
            // Reserve label rectangles so a burst cannot turn filenames into a solid ring.
            var occupied: [CGRect] = []
            let labelSweep = floor(sweep / (.pi / 4)) * (.pi / 4)
            func labelPriority(_ contact: RadarContact) -> Double {
                let delta = (labelSweep - contact.bearing).truncatingRemainder(dividingBy: .pi * 2)
                return delta < 0 ? delta + .pi * 2 : delta
            }
            for contact in visible.sorted(by: { labelPriority($0) < labelPriority($1) }) {
                guard occupied.count < 38 else { break }
                let p = location(contact)
                let name = contact.filename.count > 25 ? String(contact.filename.prefix(22)) + "…" : contact.filename
                let label = context.resolve(Text(name).font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(scopeLight))
                let measured = label.measure(in: CGSize(width: 160, height: 15))
                let width = min(160, measured.width), height = max(12, measured.height)
                let right = p.x < center.x
                let primaryX = right ? p.x + 7 : p.x - width - 7
                let oppositeX = right ? p.x - width - 7 : p.x + 7
                let options = [
                    CGRect(x: primaryX, y: p.y - height - 3, width: width, height: height),
                    CGRect(x: primaryX, y: p.y + 3, width: width, height: height),
                    CGRect(x: oppositeX, y: p.y - height - 3, width: width, height: height),
                    CGRect(x: oppositeX, y: p.y + 3, width: width, height: height)
                ]
                guard let box = options.first(where: { box in
                    let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
                    return corners.allSatisfy { hypot($0.x - center.x, $0.y - center.y) < radius - 8 }
                        && !occupied.contains { $0.intersects(box.insetBy(dx: -4, dy: -3)) }
                }) else { continue }
                occupied.append(box)
                var ink = context
                ink.opacity = max(0.55, contact.opacity(at: time)) * centerFade(contact)
                let join = CGPoint(x: right ? box.minX - 2 : box.maxX + 2, y: box.midY)
                var leader = Path(); leader.move(to: p); leader.addLine(to: join)
                ink.stroke(leader, with: .color(scopeLight.opacity(0.25)), lineWidth: 0.5)
                ink.draw(label, at: box.origin, anchor: .topLeading)
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)), with: .color(fieldCream.opacity(0.7)))
        }.allowsHitTesting(false)
    }
}

private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
    CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
}
