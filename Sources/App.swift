import SwiftUI
import AppKit

enum AirframeArtwork {
    static let nose: NSImage = {
        guard let url = Bundle.main.url(forResource: "DockIcon", withExtension: "png"), let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }()
    @MainActor static func installDockIcon() {
        NSApplication.shared.applicationIconImage = nose
        let tile = NSApplication.shared.dockTile
        let aircraft = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
        aircraft.image = nose
        aircraft.imageScaling = .scaleProportionallyUpOrDown
        aircraft.autoresizingMask = [.width, .height]
        tile.contentView = aircraft
        tile.display()
    }
}

private let ink = fieldInk
private let lime = fieldBrass
private let muted = fieldCream.opacity(0.72)
private let divider = fieldCream.opacity(0.16)

@main struct LiberatorApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .frame(width: 640, height: 730)
                .preferredColorScheme(.dark)
                .onAppear { AirframeArtwork.installDockIcon() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 640, height: 730)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan") { model.scanEverything() }.keyboardShortcut("r")
                    .disabled(model.isScanning || model.isWorking)
            }
            CommandGroup(replacing: .appSettings) {}
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    private var incomplete: Bool { model.totalUnreadable > 0 || model.scanLimited || model.scanStopped }
    var body: some View {
        VStack(spacing: 0) {
            if model.isScanning { scanning } else {
            HStack(spacing: 10) {
                Color.clear.frame(width: 230, height: 110)
                    .accessibilityElement(children: .ignore).accessibilityLabel("Liberator")
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if model.isScanning {
                    Button("Stop") { model.stopScan() }.buttonStyle(CleanButton(quiet: true))
                } else {
                    Button("Scan") { model.scanEverything() }.buttonStyle(CleanButton()).disabled(model.isWorking)
                }
            }.padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 25)
            Rectangle().fill(divider).frame(height: 1)
            if !model.scanFinished { welcome }
            else { findings }
            receipt
            }
        }
        .background(AirframeSkin(scanning: model.isScanning).ignoresSafeArea())
        .foregroundStyle(fieldCream)
        .alert("Some items need attention", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            if model.cleanupNeedsAccess {
                Button("Allow access") { model.errorMessage = nil; model.allowCleanupAccess() }
            }
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private var welcome: some View {
        VStack(spacing: 16) {
            PaintedText(text: "Scan for enemies", size: 40).rotationEffect(.degrees(-1.5))
            Text("Scan your Mac for quarantined apps and files.")
                .font(.system(size: 13)).foregroundStyle(muted)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var scanning: some View {
        RadarScanView(radar: model.radar, found: model.radarFound, inspected: model.inspected, startedAt: model.scanStartedAt, onStop: model.stopScan)
    }
    @ViewBuilder private var findings: some View {
        if model.quarantineCount == 0 {
            VStack(spacing: 10) {
                PaintedText(text: incomplete ? "Nothing found so far." : "All clear.", size: 32)
                Text(incomplete ? "The scan is incomplete. Scan again to check the rest." : "No quarantine flags remain in these results.")
                    .font(.system(size: 12)).foregroundStyle(muted).multilineTextAlignment(.center)
                if model.totalUnreadable > 0 {
                    Button("Allow full scan") { model.openSettings("Privacy_AllFiles") }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(lime).padding(.top, 4)
                }
            }.padding(.horizontal, 28).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PaintedText(text: "Here’s what we found.", size: 32)
                Spacer()
                if model.totalUnreadable > 0 {
                    Button("Allow full scan") { model.openSettings("Privacy_AllFiles") }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(lime)
                }
            }.padding(.horizontal, 28).padding(.top, 24)
            Text("Uncheck anything you want to keep quarantined.")
                .font(.system(size: 12)).foregroundStyle(muted).padding(.horizontal, 28).padding(.top, 7).padding(.bottom, 20)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.results.filter { $0.quarantined > 0 }) { row in
                        FindingRow(row: row)
                    }
                }
            }
            if incomplete {
                Text(model.scanStopped ? "Scan stopped. Results cover only the items inspected." : model.status).font(.system(size: 11)).foregroundStyle(muted).padding(.horizontal, 28).padding(.vertical, 10)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
    private var receipt: some View {
        VStack(spacing: 11) {
            Rectangle().fill(fieldInk.opacity(0.22)).frame(height: 1)
            HStack {
                Text("FILES SCANNED"); Spacer(); Text(model.totalFiles.formatted()).monospacedDigit()
            }
            HStack {
                Text("APPS SCANNED"); Spacer(); Text(model.totalApps.formatted()).monospacedDigit()
            }
            HStack {
                Text("SELECTED TO CLEAN"); Spacer(); Text(model.selectedFiles.count.formatted()).monospacedDigit().foregroundStyle(fieldInk)
            }
            Rectangle().fill(fieldInk.opacity(0.22)).frame(height: 1)
            if model.isWorking {
                HStack { ProgressView().controlSize(.small); Text("Cleaning up…").font(.system(size: 12)) }
            } else if model.status.contains(" cleaned.") || model.status.contains("flags restored") {
                HStack {
                    Text(model.status).font(.system(size: 11)).lineLimit(2)
                    Spacer()
                    if let journal = model.latestUndo {
                        Button("Undo") { model.undo(journal) }.buttonStyle(.plain).foregroundStyle(lime)
                    }
                }
            }
            Button { model.cleanSelected() } label: {
                HStack { Spacer(); Text("Liberate"); Image(systemName: "arrow.right"); Spacer() }
            }.buttonStyle(CleanButton()).disabled(model.selectedFiles.isEmpty || model.isScanning || model.isWorking)
            Text("Only clean items you trust. Quarantine is not a malware diagnosis.")
                .font(.system(size: 10)).foregroundStyle(fieldInk.opacity(0.7)).frame(maxWidth: .infinity)
        }
        .font(.custom("CourierNewPS-BoldMT", size: 10)).tracking(0.5).foregroundStyle(fieldInk.opacity(0.8))
        .padding(.horizontal, 20).padding(.vertical, 20)
        .background(ReceiptPaper().fill(LinearGradient(colors: [Color(red: 0.82, green: 0.78, blue: 0.60), fieldCream, Color(red: 0.70, green: 0.65, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing)).overlay(PaperWear().clipShape(ReceiptPaper())).shadow(color: .black.opacity(0.5), radius: 4, y: 4))
        .padding(.horizontal, 29).padding(.bottom, 24)
    }
}

struct FindingRow: View {
    @EnvironmentObject var model: AppModel
    let row: ScanResult
    var body: some View {
        HStack(spacing: 13) {
            Toggle(row.title, isOn: Binding(get: { model.selected.contains(row.id) }, set: { _ in model.toggle(row) }))
                .labelsHidden().toggleStyle(.checkbox).tint(lime).disabled(row.isSystem || model.isWorking)
                .accessibilityLabel("Clean " + row.title)
            Image(nsImage: NSWorkspace.shared.icon(forFile: row.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(row.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10)).foregroundStyle(muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(row.isSystem ? "Protected" : row.isApp ? "\(row.quarantined.formatted()) files" : "File")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
        }.padding(.horizontal, 28).padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(divider.opacity(0.5)).frame(height: 1).padding(.leading, 28) }
    }
}

struct CleanButton: ButtonStyle {
    var quiet = false
    func makeBody(configuration: Configuration) -> some View { ButtonBody(configuration: configuration, quiet: quiet) }
    struct ButtonBody: View {
        let configuration: Configuration
        let quiet: Bool
        @Environment(\.isEnabled) var enabled
        var body: some View {
            configuration.label.font(.custom("SignPainter-HouseScriptSemibold", size: 25))
                .foregroundStyle(quiet ? fieldCream : fieldInk).padding(.horizontal, 23).padding(.vertical, 7)
                .mask(PaintWear())
                .background(RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: quiet ? [Color.white.opacity(0.08), Color.black.opacity(0.1)] : [Color(red: 0.67, green: 0.63, blue: 0.40), Color(red: 0.75, green: 0.70, blue: 0.46), Color(red: 0.53, green: 0.50, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing)).overlay(PaperWear().clipShape(RoundedRectangle(cornerRadius: 3))))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(fieldInk.opacity(0.8), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 4).inset(by: 1.5).strokeBorder(fieldCream.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(enabled ? 0.4 : 0.1), radius: 1, y: configuration.isPressed ? 0 : 2)
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.25)
        }
    }
}
