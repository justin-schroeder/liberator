import Foundation
import Darwin

@main struct WorkflowTests {
    @MainActor static func check(_ value: Bool, _ name: String) {
        guard value else { fputs("FAIL: \(name)\n", stderr); exit(1) }; print("PASS: \(name)")
    }
    @MainActor static func settled(_ model: AppModel) async throws {
        for _ in 0..<1000 {
            if !model.isScanning && !model.isWorking { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Workflow timed out"])
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("LiberatorWorkflow-" + UUID().uuidString)
        let files = root.appendingPathComponent("Fixture")
        let history = root.appendingPathComponent("Undo")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = files.appendingPathComponent("sample.rs")
        try Data("fn main() {}\n".utf8).write(to: file)
        let attr = Data("0081;00000000;LiberatorWorkflow;".utf8)
        check(attr.withUnsafeBytes { setxattr(file.path, quarantineName, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) } == 0, "workflow fixture created")
        let model = AppModel(journalDirectory: history)
        model.scanFolders([files, files])
        try await settled(model)
        check(model.folders.count == 1 && model.quarantineCount == 1, "overlapping roots deduplicated")
        model.selectAllFlagged()
        check(model.selectedFiles.count == 1, "review selection contains one file")
        model.trusted = false; model.liberate()
        check(model.journals.isEmpty, "unreviewed cleanup does nothing")
        model.trusted = true; model.liberate()
        try await settled(model)
        check(model.journals.count == 1 && model.journals[0].outcomes.first?.success == true, "reviewed cleanup records successful outcome")
        check(try FileAttributes.read(file.path, quarantineName) == nil, "workflow actually clears metadata")
        check(model.quarantineCount == 0, "visible result count refreshed")
        let saved = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: history.appendingPathComponent(model.journals[0].id.uuidString + ".json")))
        check(saved.files[0].quarantine == attr, "undo bytes persisted on disk")
        var permissions = stat()
        _ = stat(history.path, &permissions)
        check(permissions.st_mode & 0o777 == 0o700, "private history directory permissions")
        let reloaded = AppModel(journalDirectory: history)
        check(reloaded.journals.count == 1, "history survives app restart")
        reloaded.undo(reloaded.journals[0])
        try await settled(reloaded)
        check(try FileAttributes.read(file.path, quarantineName) == attr, "undo after restart restores exact original bytes")
        check(reloaded.journals[0].restored, "history marks completed undo")
        // Simulate a process interruption between mutation and outcome persistence.
        var interrupted = saved
        interrupted = Journal(id: UUID(), date: Date(), files: saved.files, outcomes: [], restored: false)
        let removed = SafeMutation.apply(ChangeRequest(file: saved.files[0], restore: false), allowedRoots: [files.path])
        check(removed.success, "interrupted operation fixture cleared")
        let incompletePath = history.appendingPathComponent(interrupted.id.uuidString + ".json")
        try JSONEncoder().encode(interrupted).write(to: incompletePath)
        let recovery = AppModel(journalDirectory: history)
        recovery.undo(interrupted, recover: true)
        try await settled(recovery)
        check(try FileAttributes.read(file.path, quarantineName) == attr, "interrupted journal recovers safely")
        check(recovery.journals.first(where: { $0.id == interrupted.id })?.restored == true, "recovery outcome persisted")
        let bundle = files.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let bundled = bundle.appendingPathComponent("payload.txt")
        try Data("app fixture".utf8).write(to: bundled)
        check(attr.withUnsafeBytes { setxattr(bundled.path, quarantineName, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) } == 0, "application fixture marked")
        let simple = AppModel(journalDirectory: root.appendingPathComponent("SimpleUndo"))
        simple.scanEverything(roots: [files])
        try await settled(simple)
        check(simple.totalFiles == 2 && simple.totalApps == 1, "receipt counts files and applications separately")
        check(simple.apps.count == 1 && simple.folders.count == 1, "one list groups app contents and individual files")
        check(simple.selectedFiles.count == 2, "scan checks findings by default")
        check(simple.radar.contacts.isEmpty && simple.radarFound == 2, "finishing replaces the radar with complete findings")
        simple.toggle(simple.apps[0])
        check(simple.selectedFiles.count == 1, "unchecking an app excludes its files")
        simple.cleanSelected()
        try await settled(simple)
        check(try FileAttributes.read(bundled.path, quarantineName) == attr, "unchecked application stays quarantined")
        check(try FileAttributes.read(file.path, quarantineName) == nil, "single cleanup button clears checked file")
        check(simple.quarantineCount == 1 && simple.selectedFiles.isEmpty, "cleanup receipt keeps excluded findings visible")
        simple.undo(simple.latestUndo!)
        try await settled(simple)
        check(try FileAttributes.read(file.path, quarantineName) == attr, "simple cleanup still supports exact undo")
        simple.radar.ingest(["/stale-contact"], at: ProcessInfo.processInfo.systemUptime)
        simple.scanEverything(roots: [files])
        check(simple.radar.contacts.isEmpty && simple.radarFound == 0, "a new scan resets old radar contacts and totals")
        simple.stopScan()
        try await settled(simple)
        check(simple.scanStopped, "cancelled scan retains explicit partial state")
        simple.status = "1 files cleaned. 0 unchanged."
        check(simple.scanStopped, "cleanup messages do not erase partial scan state")
        print("28 workflow assertions passed")
    }
}
