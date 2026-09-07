import Foundation
import Darwin

let quarantineName = "com.apple.quarantine"
let provenanceName = "com.apple.provenance"
let serviceName = "app.liberator.mac.helper"

struct Identity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modified: Int64
    let nanos: Int64
    init(_ s: stat) {
        device = UInt64(s.st_dev); inode = UInt64(s.st_ino); size = s.st_size
        modified = Int64(s.st_mtimespec.tv_sec); nanos = Int64(s.st_mtimespec.tv_nsec)
    }
}
struct MarkedFile: Codable, Identifiable, Sendable {
    var id: String { path }
    let path: String
    let identity: Identity
    let quarantine: Data
}
struct ScanResult: Codable, Identifiable, Sendable {
    var id: String { path }
    let path: String
    var title: String
    var inspected = 0
    var inspectedFiles = 0
    var inspectedApps = 0
    var provenance = 0
    var quarantined = 0
    var errors = 0
    var examples: [String] = []
    var files: [MarkedFile] = []
    var cancelled = false
    var limited = false
    var isApp: Bool
    var isSystem: Bool { path.hasPrefix("/System/") }
}
final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
struct ScanProgress: Sendable {
    let inspected: Int
    let path: String
    var quarantined = 0
    var foundPaths: [String] = []
}

// Only the visual feed is bounded; ScanResult retains all reviewable findings.
private struct ContactBatch {
    var paths: [String] = []
    var cursor = 0
    mutating func append(_ path: String) {
        if paths.count < 300 { paths.append(path) }
        else { paths[cursor] = path; cursor = (cursor + 1) % 300 }
    }
    mutating func drain() -> [String] {
        let ordered = Array(paths[cursor...]) + Array(paths[..<cursor])
        paths.removeAll(keepingCapacity: true); cursor = 0
        return ordered
    }
}

enum FileAttributes {
    static func read(_ path: String, _ name: String) throws -> Data? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        if size < 0 {
            if errno == ENOATTR { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard size <= 65536 else { throw NSError(domain: "Liberator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Attribute is unexpectedly large."]) }
        var data = Data(count: size)
        let n = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        guard n >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return Data(data.prefix(n))
    }
    static func canonicalPath(_ path: String) -> String {
        guard let p = realpath(path, nil) else { return path }
        defer { free(p) }; return String(cString: p)
    }
    static func scan(root: URL, isApp: Bool, cancellation: Cancellation, includeProvenance: Bool = true, progress: @Sendable (ScanProgress) -> Void) -> ScanResult {
        let path = canonicalPath(root.standardizedFileURL.path)
        let physicalRoot = URL(fileURLWithPath: path)
        var result = ScanResult(path: path, title: root.deletingPathExtension().lastPathComponent, isApp: isApp)
        var contacts = ContactBatch()
        var lastProgress = ProcessInfo.processInfo.systemUptime
        func report(_ path: String) {
            progress(ScanProgress(inspected: result.inspected, path: path, quarantined: result.quarantined, foundPaths: contacts.drain()))
        }
        func visit(_ url: URL) {
            if cancellation.isCancelled { result.cancelled = true; return }
            var st = stat()
            guard lstat(url.path, &st) == 0 else { result.errors += 1; return }
            let kind = st.st_mode & S_IFMT
            guard kind == S_IFREG || kind == S_IFDIR else { return }
            result.inspected += 1
            if kind == S_IFREG { result.inspectedFiles += 1 }
            if kind == S_IFDIR && url.pathExtension == "app" { result.inspectedApps += 1 }
            do {
                if let data = try read(url.path, quarantineName) {
                    result.quarantined += 1
                    contacts.append(url.path)
                    if result.files.count < 100_000 { result.files.append(MarkedFile(path: url.path, identity: Identity(st), quarantine: data)) } else { result.limited = true }
                }
                if includeProvenance, try read(url.path, provenanceName) != nil { result.provenance += 1 }
            } catch {
                result.errors += 1
                if result.examples.count < 4 { result.examples.append(url.path) }
            }
            if result.inspected % 128 == 0 {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastProgress >= 0.1 { lastProgress = now; report(url.path) }
            }
        }
        var rootStat = stat()
        guard lstat(root.path, &rootStat) == 0, rootStat.st_mode & S_IFMT == S_IFDIR else { result.errors += 1; return result }
        visit(physicalRoot)
        if let e = FileManager.default.enumerator(at: physicalRoot, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { url, _ in
            result.errors += 1
            if result.examples.count < 4 { result.examples.append(url.path) }
            return !cancellation.isCancelled
        }) {
            while let url = e.nextObject() as? URL {
                if cancellation.isCancelled { result.cancelled = true; break }
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values?.isSymbolicLink == true { e.skipDescendants(); continue }
                visit(url)
            }
        }
        report(root.path)
        return result
    }
    static func appRoots() -> [URL] {
        let fm = FileManager.default
        let dirs = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"), URL(fileURLWithPath: "/System/Applications")]
        var found: [URL] = []
        for root in dirs {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { continue }
            while let url = e.nextObject() as? URL {
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { e.skipDescendants(); continue }
                if url.pathExtension == "app" { found.append(url); e.skipDescendants() }
            }
        }
        return found.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}

enum FindingList {
    // Keep each app together; ordinary files are individually selectable.
    static func rows(_ records: [MarkedFile]) -> [ScanResult] {
        var grouped: [String: [MarkedFile]] = [:]
        var seen = Set<String>()
        for file in records where seen.insert(file.path).inserted {
            let parts = file.path.split(separator: "/").map(String.init)
            let appIndex = parts.firstIndex { $0.hasSuffix(".app") }
            let group = appIndex.map { "/" + parts.prefix($0 + 1).joined(separator: "/") } ?? file.path
            grouped[group, default: []].append(file)
        }
        return grouped.map { path, files in
            let isApp = path.hasSuffix(".app")
            return ScanResult(path: path, title: URL(fileURLWithPath: path).lastPathComponent,
                quarantined: files.count, files: files, isApp: isApp)
        }.sorted { lhs, rhs in
            if lhs.isApp != rhs.isApp { return lhs.isApp }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }
}

struct ChangeRequest: Codable, Sendable {
    let file: MarkedFile
    let restore: Bool
}
struct ChangeOutcome: Codable, Sendable {
    let path: String
    let success: Bool
    let message: String
    let errorCode: Int32
}
struct Journal: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let files: [MarkedFile]
    var outcomes: [ChangeOutcome]
    var restored: Bool
}

enum SafeMutation {
    // Resolve each path component through directory descriptors. No symlink is followed,
    // including ancestors; all validation and xattr writes use the final open descriptor.
    static func openChecked(_ path: String) throws -> Int32 {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else { throw POSIXError(.EINVAL) }
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { throw POSIXError(.EPERM) }
        // Ancestors are traversed, never enumerated. Requesting read access here
        // needlessly prompts for all of Documents even when the user selected a subfolder.
        var fd = open("/", O_SEARCH | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(.EACCES) }
        for (index, part) in components.enumerated() {
            let access = index < components.count - 1 ? O_SEARCH | O_DIRECTORY : O_RDONLY
            let next = openat(fd, part, access | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            let saved = errno
            close(fd)
            guard next >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: saved) ?? .EIO) }
            fd = next
        }
        return fd
    }
    static func apply(_ request: ChangeRequest, allowedRoots: [String]) -> ChangeOutcome {
        let file = request.file
        do {
            let path = file.path
            guard allowedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }), !path.hasPrefix("/System/"), !path.hasPrefix("/Library/"), file.quarantine.count <= 65536 else { throw POSIXError(.EPERM) }
            let fd = try openChecked(path)
            defer { close(fd) }
            var st = stat()
            guard fstat(fd, &st) == 0 else { throw POSIXError(.EIO) }
            let type = st.st_mode & S_IFMT
            guard type == S_IFREG || type == S_IFDIR else { throw POSIXError(.EPERM) }
            guard type != S_IFREG || st.st_nlink == 1 else { throw NSError(domain: "Liberator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Hard-linked file skipped."]) }
            guard Identity(st) == file.identity else { throw NSError(domain: "Liberator", code: 3, userInfo: [NSLocalizedDescriptionKey: "File changed since the scan. Scan it again."]) }
            let size = fgetxattr(fd, quarantineName, nil, 0, 0, 0)
            if request.restore {
                guard size < 0 && errno == ENOATTR else { throw NSError(domain: "Liberator", code: 4, userInfo: [NSLocalizedDescriptionKey: "An attribute already exists; restore will not overwrite it."]) }
                let rc = file.quarantine.withUnsafeBytes { fsetxattr(fd, quarantineName, $0.baseAddress, $0.count, 0, XATTR_CREATE) }
                guard rc == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            } else {
                if size < 0 && errno == ENOATTR { return ChangeOutcome(path: path, success: true, message: "Already clear", errorCode: 0) }
                guard size >= 0 && size <= 65536 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                var old = Data(count: size)
                let count = old.withUnsafeMutableBytes { fgetxattr(fd, quarantineName, $0.baseAddress, size, 0, 0) }
                guard count == size && old == file.quarantine else { throw NSError(domain: "Liberator", code: 5, userInfo: [NSLocalizedDescriptionKey: "Quarantine changed since the scan. Scan it again."]) }
                guard fremovexattr(fd, quarantineName, 0) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                guard fgetxattr(fd, quarantineName, nil, 0, 0, 0) < 0 && errno == ENOATTR else { throw POSIXError(.EIO) }
            }
            return ChangeOutcome(path: path, success: true, message: request.restore ? "Restored" : "Liberated", errorCode: 0)
        } catch {
            let ns = error as NSError
            return ChangeOutcome(path: file.path, success: false, message: error.localizedDescription, errorCode: ns.domain == NSPOSIXErrorDomain ? Int32(ns.code) : 0)
        }
    }
}
