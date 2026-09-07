import Foundation
import Darwin

private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScanProgress] = []
    func append(_ value: ScanProgress) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
    var values: [ScanProgress] { lock.lock(); defer { lock.unlock() }; return storage }
}

@main struct RadarTests {
    static var passed = 0
    static func check(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        passed += 1; print("PASS: \(message)")
    }
    static func main() throws {
        var radar = RadarState()
        radar.ingest((0..<400).map { "/fixture/bogey-\($0).txt" }, at: 100)
        check(radar.contacts.count == 300, "a large burst cannot exceed 300 rendered contacts")
        check(radar.contacts.first?.filename == "bogey-100.txt" && radar.contacts.last?.filename == "bogey-399.txt", "overflow preserves the most recent filenames")
        let echo = radar.contacts[0]
        check(abs(echo.opacity(at: 108) - 0.5) < 0.0001, "contacts have an eight-second half-life")
        check(echo.range(at: 108) < echo.range(at: 100) && !echo.isVisible(at: 1000), "contacts approach the center and retire before crossing it")
        let arrival = echo.born + (echo.range(at: echo.born) - 0.12) / 0.028
        check(echo.isVisible(at: arrival - 0.01) && !echo.isVisible(at: arrival + 0.01), "contacts drop off precisely at the center exclusion zone")
        radar.ingest([], at: 133)
        check(radar.contacts.isEmpty, "expired contacts are removed even without new findings")
        for batch in 0..<30 { radar.ingest((0..<200).map { "/fixture/\(batch)-\($0)" }, at: 200 + Double(batch) / 10) }
        check(radar.contacts.count == 300 && Set(radar.contacts.map(\.id)).count == 300, "sustained bursts stay bounded with unique contacts")

        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("LiberatorRadarTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let attr = Data("0081;00000000;LiberatorRadarTest;".utf8)
        for n in 0..<405 {
            let file = root.appendingPathComponent("flagged-\(n).txt")
            try Data("test fixture".utf8).write(to: file)
            guard attr.withUnsafeBytes({ setxattr(file.path, quarantineName, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }) == 0 else { throw POSIXError(.EIO) }
        }
        try Data().write(to: root.appendingPathComponent("unflagged.txt"))
        let capture = ProgressCapture()
        let result = FileAttributes.scan(root: root, isApp: false, cancellation: Cancellation(), includeProvenance: false) { capture.append($0) }
        let updates = capture.values
        check(!updates.isEmpty && updates.allSatisfy { $0.foundPaths.count <= 300 }, "scanner progress batches are bounded")
        check(updates.flatMap(\.foundPaths).allSatisfy { URL(fileURLWithPath: $0).lastPathComponent.hasPrefix("flagged-") }, "only actual quarantine findings become bogeys")
        check(updates.last?.quarantined == 405, "the live total includes findings beyond the animation limit")
        check(result.files.count == 405 && FindingList.rows(result.files).count == 405, "the full result list retains every file beyond the radar cap")
        let token = Cancellation(); token.cancel()
        let stopped = ProgressCapture()
        let cancelled = FileAttributes.scan(root: root, isApp: false, cancellation: token) { stopped.append($0) }
        check(cancelled.cancelled && stopped.values.flatMap(\.foundPaths).isEmpty, "an already cancelled scan emits no phantom contacts")
        print("\(passed) radar assertions passed")
    }
}
