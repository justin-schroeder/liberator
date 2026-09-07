import Foundation
import Darwin

@main struct CoreTests {
    static var passed = 0
    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        passed += 1; print("PASS: \(message)")
    }
    static func mark(_ path: String, _ bytes: Data = Data("0081;00000000;LiberatorTest;".utf8)) {
        let rc = bytes.withUnsafeBytes { setxattr(path, quarantineName, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }
        check(rc == 0, "fixture attribute written")
    }
    static func record(_ url: URL) throws -> MarkedFile {
        var s = stat(); guard lstat(url.path, &s) == 0 else { throw POSIXError(.ENOENT) }
        return MarkedFile(path: url.path, identity: Identity(s), quarantine: try FileAttributes.read(url.path, quarantineName)!)
    }
    static func main() throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("liberator-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("hello.txt")
        try Data("original contents".utf8).write(to: file)
        mark(file.path)
        let record = try record(file)
        let scan = FileAttributes.scan(root: root, isApp: false, cancellation: Cancellation()) { _ in }
        check(scan.inspected == 2 && scan.quarantined == 1, "scan counts root and quarantined file")
        check(scan.files.first?.path == file.path, "scan produces exact reviewable path")
        let outcome = SafeMutation.apply(ChangeRequest(file: record, restore: false), allowedRoots: [root.path])
        check(outcome.success, "quarantine removal succeeds")
        check(try FileAttributes.read(file.path, quarantineName) == nil, "removed attribute verified")
        check(try Data(contentsOf: file) == Data("original contents".utf8), "file contents untouched")
        let restored = SafeMutation.apply(ChangeRequest(file: record, restore: true), allowedRoots: [root.path])
        check(restored.success, "undo succeeds")
        check(try FileAttributes.read(file.path, quarantineName) == record.quarantine, "undo restores exact bytes")
        check(!SafeMutation.apply(ChangeRequest(file: record, restore: true), allowedRoots: [root.path]).success, "undo refuses existing attribute")
        check(!SafeMutation.apply(ChangeRequest(file: record, restore: false), allowedRoots: [root.path + "-other"]).success, "component-boundary scope restriction")
        try Data("modified contents".utf8).write(to: file)
        check(!SafeMutation.apply(ChangeRequest(file: record, restore: false), allowedRoots: [root.path]).success, "changed file identity refused")
        mark(file.path)
        let current = try self.record(file)
        mark(file.path, Data("0081;00000001;OtherSource;".utf8))
        check(!SafeMutation.apply(ChangeRequest(file: current, restore: false), allowedRoots: [root.path]).success, "changed quarantine refused")
        let hard = root.appendingPathComponent("hardlink.txt")
        check(link(file.path, hard.path) == 0, "hard-link fixture created")
        let hardRecord = try self.record(file)
        check(!SafeMutation.apply(ChangeRequest(file: hardRecord, restore: false), allowedRoots: [root.path]).success, "hard-linked targets refused")
        try FileManager.default.removeItem(at: hard)
        let linkURL = root.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: file)
        let linkScan = FileAttributes.scan(root: root, isApp: false, cancellation: Cancellation()) { _ in }
        check(linkScan.files.allSatisfy { $0.path != linkURL.path }, "scanner skips symlinks")
        let ancestor = root.appendingPathComponent("alias-dir")
        try FileManager.default.createSymbolicLink(at: ancestor, withDestinationURL: root)
        let ancestorRecord = MarkedFile(path: ancestor.appendingPathComponent("hello.txt").path, identity: hardRecord.identity, quarantine: hardRecord.quarantine)
        check(!SafeMutation.apply(ChangeRequest(file: ancestorRecord, restore: false), allowedRoots: [root.path]).success, "symlinked ancestor refused")
        let rootLinkScan = FileAttributes.scan(root: ancestor, isApp: false, cancellation: Cancellation()) { _ in }
        check(rootLinkScan.inspected == 0 && rootLinkScan.errors == 1, "symlinked scan root refused")
        let token = Cancellation(); token.cancel()
        let cancelled = FileAttributes.scan(root: root, isApp: false, cancellation: token) { _ in }
        check(cancelled.cancelled && cancelled.inspected == 0, "cancelled scan makes no progress")
        let directory = root.appendingPathComponent("marked-directory")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mark(directory.path)
        let dirRecord = try self.record(directory)
        check(SafeMutation.apply(ChangeRequest(file: dirRecord, restore: false), allowedRoots: [root.path]).success, "directory quarantine can be cleared")
        check(SafeMutation.apply(ChangeRequest(file: dirRecord, restore: true), allowedRoots: [root.path]).success, "directory quarantine can be restored")
        let unusual = root.appendingPathComponent("a 'quote' $dollar; space.txt")
        try Data("untouched".utf8).write(to: unusual)
        mark(unusual.path)
        let metadata = Data("preserve this".utf8)
        check(metadata.withUnsafeBytes { setxattr(unusual.path, "app.liberator.fixture", $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) } == 0, "unrelated attribute fixture written")
        let unusualRecord = try self.record(unusual)
        check(SafeMutation.apply(ChangeRequest(file: unusualRecord, restore: false), allowedRoots: [root.path]).success, "unusual filename is handled without a shell")
        check(try FileAttributes.read(unusual.path, "app.liberator.fixture") == metadata, "unrelated metadata preserved")
        let traversal = root.appendingPathComponent("traverse-only")
        try FileManager.default.createDirectory(at: traversal, withIntermediateDirectories: true)
        let nested = traversal.appendingPathComponent("selected.txt")
        try Data("selected file".utf8).write(to: nested)
        mark(nested.path)
        let nestedRecord = try self.record(nested)
        check(chmod(traversal.path, 0o100) == 0, "ancestor has search permission without read permission")
        let nestedOutcome = SafeMutation.apply(ChangeRequest(file: nestedRecord, restore: false), allowedRoots: [nested.path])
        let restoredPermissions = chmod(traversal.path, 0o700)
        check(nestedOutcome.success && restoredPermissions == 0, "selected file cleanup does not request ancestor directory read access")
        let wire = try JSONEncoder().encode(ChangeRequest(file: current, restore: false))
        let decoded = try JSONDecoder().decode(ChangeRequest.self, from: wire)
        check(decoded.file.identity == current.identity && decoded.file.quarantine == current.quarantine, "helper request retains exact metadata")
        print("\(passed) assertions passed")
    }
}
