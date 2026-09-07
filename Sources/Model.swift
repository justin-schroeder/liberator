import SwiftUI
import AppKit
import ExecutionPolicy
import ServiceManagement
import Security

struct ToolItem: Identifiable {
    let path: String
    let name: String
    let detail: String
    var id: String { path }
}
@MainActor final class AppModel: ObservableObject {
    @Published var page = 0
    @Published var apps: [ScanResult] = []
    @Published var folders: [ScanResult] = []
    @Published var selected = Set<String>()
    @Published var inspected = 0
    @Published var totalFiles = 0
    @Published var totalApps = 0
    @Published var totalUnreadable = 0
    @Published var scanFinished = false
    @Published var scanStopped = false
    @Published var scanLimited = false
    @Published var radar = RadarState()
    @Published var radarFound = 0
    var scanStartedAt: TimeInterval = 0
    private var administratorAttempted = false
    @Published var currentPath = ""
    @Published var isScanning = false
    @Published var isWorking = false
    @Published var completedApps = false
    @Published var status = "Ready when you are."
    @Published var query = ""
    @Published var onlyFlagged = false
    @Published var showReview = false
    @Published var showPermissions = false
    @Published var trusted = false
    @Published var errorMessage: String?
    @Published var journals: [Journal] = []
    @Published var developerAuthorized = false
    @Published var helperDescription = ""
    @Published var signatureDescriptions: [String: String] = [:]
    @Published var toolItems: [ToolItem] = []
    @Published var benchmarkBusy = false
    @Published var benchmarkResult: LaunchMeasurement?
    private var cancellation: Cancellation?
    let admin = PrivilegedClient()
    let home = FileManager.default.homeDirectoryForCurrentUser
    var results: [ScanResult] { page == 3 ? apps + folders : page == 0 ? apps : folders }
    var filtered: [ScanResult] {
        results.filter { (!onlyFlagged || $0.quarantined > 0 || $0.errors > 0) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query)) }
    }
    var flagged: Int { results.filter { $0.quarantined > 0 }.count }
    var quarantineCount: Int { results.reduce(0) { $0 + $1.quarantined } }
    var provenanceCount: Int { results.reduce(0) { $0 + $1.provenance } }
    var selectedFiles: [MarkedFile] {
        var seen = Set<String>()
        return results.filter { selected.contains($0.id) && !$0.isSystem }.flatMap(\.files).filter { seen.insert($0.path).inserted }
    }
    var liberatedCount: Int { journals.reduce(0) { $0 + $1.outcomes.filter { $0.success && $0.message == "Liberated" }.count } }
    private let journalOverride: URL?
    var journalFolder: URL { journalOverride ?? home.appendingPathComponent("Library/Application Support/Liberator/Undo", isDirectory: true) }

    init(journalDirectory: URL? = nil) {
        journalOverride = journalDirectory
        if let urls = try? FileManager.default.contentsOfDirectory(at: journalFolder, includingPropertiesForKeys: nil) {
            journals = urls.filter { $0.pathExtension == "json" }.compactMap { try? JSONDecoder().decode(Journal.self, from: Data(contentsOf: $0)) }.sorted { $0.date > $1.date }
        }
        refreshPermissions()
        let candidates = [
            ("/Applications/Ghostty.app", "Ghostty", "Terminal app"),
            ("/System/Applications/Utilities/Terminal.app", "Terminal", "Built-in terminal"),
            ("/Applications/iTerm.app", "iTerm", "Terminal app"),
            ("/Applications/Visual Studio Code.app", "Visual Studio Code", "Editor and integrated terminal"),
            ("/Applications/Cursor.app", "Cursor", "Editor and integrated terminal"),
            ("/Applications/Zed.app", "Zed", "Editor and integrated terminal"),
            ("/Applications/ChatGPT.app", "ChatGPT / Codex", "Agent and build host"),
            ("/opt/homebrew/bin/tmux", "tmux", "Restart the server after granting access"),
            ("/usr/local/bin/tmux", "tmux (Intel)", "Restart the server after granting access"),
            ("/opt/homebrew/bin/zellij", "Zellij", "Terminal multiplexer"),
            (home.appendingPathComponent("Applications/Standard Code Daemon.app").path, "Standard Code Daemon", "Background build host")
        ]
        toolItems = candidates.filter { FileManager.default.fileExists(atPath: $0.0) }.map { ToolItem(path: FileAttributes.canonicalPath($0.0), name: $0.1, detail: $0.2) }
        discoverMultiplexers()
    }
    private func discoverMultiplexers() {
        let capacity = min(65_536, max(1024, Int(proc_listallpids(nil, 0)) * 2))
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { Int(proc_listallpids($0.baseAddress, Int32($0.count))) }
        for pid in pids.prefix(max(0, min(count, capacity))) where pid > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size, info.pbi_uid == getuid() else { continue }
            var buffer = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            let path = String(cString: buffer)
            let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            guard name == "tmux" || name.hasPrefix("tmux-") || name == "zellij" else { continue }
            let physical = FileAttributes.canonicalPath(path)
            guard !toolItems.contains(where: { $0.path == physical }) else { continue }
            toolItems.append(ToolItem(path: physical, name: name.hasPrefix("tmux") ? "tmux · running runtime" : "Zellij · running runtime", detail: "Exact running binary · restart after permission changes"))
        }
    }
    func runBenchmark() {
        guard !benchmarkBusy else { return }
        benchmarkBusy = true
        let owner = self
        Task.detached {
            do { let result = try LaunchBenchmark.run(); await MainActor.run { owner.benchmarkResult = result; owner.benchmarkBusy = false } }
            catch { await MainActor.run { owner.errorMessage = error.localizedDescription; owner.benchmarkBusy = false } }
        }
    }
    func refreshPermissions() {
        developerAuthorized = EPDeveloperTool().authorizationStatus == .authorized
        if !admin.releaseEnabled { helperDescription = "Developer ID release required" }
        else {
            switch admin.status {
            case .enabled: helperDescription = "Ready for administrator-approved changes"
            case .requiresApproval: helperDescription = "Approve in Login Items & Extensions"
            default: helperDescription = "Not installed"
            }
        }
    }
    func requestDeveloperAccess() {
        EPDeveloperTool().requestAccess { [weak self] _ in Task { @MainActor in self?.refreshPermissions(); self?.openSettings("Privacy_DevTools") } }
    }
    func openSettings(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") { NSWorkspace.shared.open(url) }
    }
    func revealTool(_ tool: ToolItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tool.path)])
        openSettings("Privacy_DevTools")
    }
    func selectAllFlagged() { selected = Set(filtered.filter { $0.quarantined > 0 && !$0.isSystem }.map(\.id)) }
    func toggle(_ row: ScanResult) {
        guard row.quarantined > 0 && !row.isSystem else { return }
        if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
    }
    func scanApps() {
        guard !isScanning && !isWorking && !benchmarkBusy else { return }
        page = 0; apps = []; selected = []; completedApps = false
        startScan(roots: nil, appScan: true)
    }
    func scanEverything(roots override: [URL]? = nil) {
        guard !isScanning && !isWorking else { return }
        page = 3; apps = []; folders = []; selected = []
        inspected = 0; totalFiles = 0; totalApps = 0; totalUnreadable = 0
        radar = RadarState(); radarFound = 0; scanStartedAt = ProcessInfo.processInfo.systemUptime
        scanFinished = false; scanStopped = false; scanLimited = false; isScanning = true
        status = "Scanning your apps and files…"
        let token = Cancellation(); cancellation = token
        let roots = override ?? [URL(fileURLWithPath: "/Applications"), home,
            URL(fileURLWithPath: "/opt/homebrew"), URL(fileURLWithPath: "/usr/local"),
            URL(fileURLWithPath: "/System/Applications")].filter { FileManager.default.fileExists(atPath: $0.path) }
        let owner = self
        Task.detached(priority: .utility) {
            var all: [MarkedFile] = []
            var entries = 0
            var found = 0
            for root in roots {
                if token.isCancelled { break }
                let base = entries
                let foundBase = found
                let result = FileAttributes.scan(root: root, isApp: false, cancellation: token, includeProvenance: false) { update in
                    Task { @MainActor in
                        guard owner.isScanning, owner.cancellation === token else { return }
                        owner.inspected = base + update.inspected; owner.currentPath = update.path
                        owner.radarFound = foundBase + update.quarantined
                        owner.radar.ingest(update.foundPaths, at: ProcessInfo.processInfo.systemUptime)
                    }
                }
                entries += result.inspected; found += result.quarantined; all += result.files
                await MainActor.run {
                    owner.totalFiles += result.inspectedFiles; owner.totalApps += result.inspectedApps
                    owner.totalUnreadable += result.errors; owner.scanLimited = owner.scanLimited || result.limited
                }
            }
            let rows = FindingList.rows(all)
            let count = entries
            let finalFound = found
            await MainActor.run {
                owner.apps = rows.filter(\.isApp); owner.folders = rows.filter { !$0.isApp }
                owner.selected = Set(rows.filter { !$0.isSystem }.map(\.id))
                owner.inspected = count; owner.isScanning = false; owner.scanFinished = true; owner.cancellation = nil
                owner.radarFound = finalFound; owner.radar = RadarState()
                owner.scanStopped = token.isCancelled
                owner.status = token.isCancelled ? "Scan stopped. Showing what was found so far." : "Scan complete."
                if owner.scanLimited { owner.status += " More results remain; clean this pass and scan again." }
                if owner.totalUnreadable > 0 { owner.status += " \(owner.totalUnreadable.formatted()) items could not be inspected." }
            }
        }
    }
    func cleanSelected() {
        guard !selectedFiles.isEmpty else { return }
        trusted = true
        liberate()
    }
    var cleanupNeedsAccess: Bool {
        journals.first?.outcomes.contains { !$0.success && ($0.errorCode == EPERM || $0.errorCode == EACCES) } == true
    }
    var latestUndo: Journal? { journals.first { !$0.restored && $0.outcomes.contains { $0.success && $0.message == "Liberated" } } }
    func allowCleanupAccess() {
        let rootOwned = selectedFiles.contains { file in
            var info = stat()
            return lstat(file.path, &info) == 0 && info.st_uid != getuid()
        }
        if rootOwned && !administratorAttempted && admin.releaseEnabled {
            do {
                if admin.status != .enabled { try admin.register() }
                if admin.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                else if let journal = journals.first { administratorAttempted = true; retryAdmin(journal) }
            } catch { errorMessage = error.localizedDescription }
        } else if results.contains(where: { $0.isApp && $0.quarantined > 0 && selected.contains($0.id) }) {
            openSettings("Privacy_AppBundles")
        } else if rootOwned && !admin.releaseEnabled {
            errorMessage = "These items need administrator access. Install the signed release to clean them up."
        } else {
            openSettings("Privacy_AllFiles")
        }
    }
    func scanDeveloperFolders() {
        let project = home.appendingPathComponent("Projects")
        let roots = [project, home.appendingPathComponent(".cargo"), home.appendingPathComponent(".rustup")].filter { FileManager.default.fileExists(atPath: $0.path) }
        scanFolders(roots)
    }
    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.title = "Choose folders to inspect"
        panel.prompt = "Scan folders"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.directoryURL = home
        if panel.runModal() == .OK { scanFolders(panel.urls) }
    }
    func scanFolders(_ roots: [URL]) {
        guard !isScanning && !isWorking && !benchmarkBusy, !roots.isEmpty else { return }
        page = 1; folders = []; selected = []
        // De-duplicate overlapping roots so no file is cleaned twice.
        let ordered = roots.map { $0.standardizedFileURL }.sorted { $0.path.count < $1.path.count }
        var unique: [URL] = []
        for url in ordered where !unique.contains(where: { url.path == $0.path || url.path.hasPrefix($0.path + "/") }) { unique.append(url) }
        startScan(roots: unique, appScan: false)
    }
    private func startScan(roots: [URL]?, appScan: Bool) {
        isScanning = true; inspected = 0; currentPath = "Discovering applications…"; status = "Scanning metadata. Your file contents stay private."
        let token = Cancellation(); cancellation = token
        let owner = self
        Task.detached(priority: .utility) {
            let directories = roots ?? FileAttributes.appRoots()
            var total = 0
            for root in directories {
                if token.isCancelled { break }
                let base = total
                let result = FileAttributes.scan(root: root, isApp: appScan, cancellation: token) { progress in
                    Task { @MainActor in if owner.isScanning { owner.inspected = base + progress.inspected; owner.currentPath = progress.path } }
                }
                total += result.inspected
                await MainActor.run {
                    if appScan { owner.apps.append(result) } else { owner.folders.append(result) }
                }
            }
            let finalTotal = total
            await MainActor.run {
                owner.isScanning = false; owner.inspected = finalTotal; owner.currentPath = ""; owner.cancellation = nil
                if appScan { owner.completedApps = !token.isCancelled }
                owner.status = token.isCancelled ? "Scan stopped. Partial results are shown." : "Scan complete. Review what you trust before making changes."
            }
        }
    }
    func stopScan() { cancellation?.cancel() }
    func prepareReview() {
        guard !selectedFiles.isEmpty else { return }
        trusted = false; showReview = true
        for row in results where selected.contains(row.id) && row.isApp {
            let path = row.path
            Task.detached {
                var code: SecStaticCode?
                let created = SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code)
                let status = created == errSecSuccess && code != nil ? SecStaticCodeCheckValidity(code!, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil) : created
                let text = status == errSecSuccess ? "Signature valid · not a malware assessment" : "Signature not verified · review the source carefully"
                await MainActor.run { [weak self] in self?.signatureDescriptions[path] = text }
            }
        }
    }
    private func save(_ journal: Journal) throws {
        try FileManager.default.createDirectory(at: journalFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = journalFolder.appendingPathComponent(journal.id.uuidString + ".json")
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func liberate() {
        guard trusted && !isWorking else { return }
        let files = selectedFiles
        showReview = false; isWorking = true
        var journal = Journal(id: UUID(), date: Date(), files: files, outcomes: [], restored: false)
        do { try save(journal) } catch { isWorking = false; errorMessage = "No changes made: the undo record could not be saved. \(error.localizedDescription)"; return }
        journals.insert(journal, at: 0)
        let roots = results.filter { selected.contains($0.id) && !$0.isSystem }.map(\.path)
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcomes = files.map { SafeMutation.apply(ChangeRequest(file: $0, restore: false), allowedRoots: roots) }
            journal.outcomes = outcomes
            await MainActor.run { [weak self] in
                guard let self else { return }
                do { try self.save(journal) } catch { self.errorMessage = "Changes completed, but their results could not be saved. The original undo record is preserved." }
                self.journals[0] = journal
                let cleared = Set(outcomes.filter(\.success).map(\.path))
                self.applyCleared(cleared)
                self.isWorking = false
                let failures = outcomes.filter { !$0.success }
                self.selected = self.page == 3 ? Set(self.results.filter { $0.quarantined > 0 && self.selected.contains($0.id) }.map(\.id)) : []
                self.status = "\(cleared.count.formatted()) \(cleared.count == 1 ? "file" : "files") cleaned. \(failures.count.formatted()) unchanged."
                if !failures.isEmpty { self.errorMessage = "\(failures.count.formatted()) items could not be cleaned.\n\n\(failures.prefix(3).map { $0.path + ": " + $0.message }.joined(separator: "\n"))" }
            }
        }
    }
    private func applyCleared(_ cleared: Set<String>) {
        for index in apps.indices { let before = apps[index].files.count; apps[index].files.removeAll { cleared.contains($0.path) }; apps[index].quarantined -= before - apps[index].files.count }
        for index in folders.indices { let before = folders[index].files.count; folders[index].files.removeAll { cleared.contains($0.path) }; folders[index].quarantined -= before - folders[index].files.count }
    }
    func retryAdmin(_ journal: Journal) {
        guard !isWorking else { return }
        guard admin.releaseEnabled && admin.status == .enabled else { showPermissions = true; return }
        let failed = Set(journal.outcomes.filter { !$0.success && ($0.errorCode == EPERM || $0.errorCode == EACCES) }.map(\.path))
        let files = journal.files.filter { failed.contains($0.path) }
        guard !files.isEmpty else { return }
        do {
            let authorization = try AdminAuthorization()
            isWorking = true
            Task {
                do {
                    var updated = journal
                    for offset in stride(from: 0, to: files.count, by: 500) {
                        let chunk = Array(files[offset..<min(files.count, offset + 500)])
                        let outcomes = try await admin.apply(chunk.map { ChangeRequest(file: $0, restore: false) }, authorization: authorization)
                        let paths = Set(outcomes.map(\.path)); updated.outcomes.removeAll { paths.contains($0.path) }; updated.outcomes += outcomes
                        try save(updated)
                    }
                    if let index = journals.firstIndex(where: { $0.id == journal.id }) { journals[index] = updated }
                    applyCleared(Set(updated.outcomes.filter { $0.success && $0.message != "Restored" }.map(\.path)))
                    status = "Administrator cleanup finished. Review the results in Activity."
                } catch { errorMessage = error.localizedDescription }
                isWorking = false
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func undo(_ journal: Journal, administrator: Bool = false, recover: Bool = false) {
        guard !isWorking && !journal.restored else { return }
        let changed = Set(journal.outcomes.filter { $0.success && $0.message == "Liberated" }.map(\.path))
        let recorded = Set(journal.outcomes.map(\.path))
        let files = journal.files.filter { changed.contains($0.path) || (recover && !recorded.contains($0.path)) }
        guard !files.isEmpty else { return }
        if administrator {
            guard admin.releaseEnabled && admin.status == .enabled else { showPermissions = true; return }
            do {
                let authorization = try AdminAuthorization()
                isWorking = true
                Task {
                    do {
                        var updated = journal
                        for offset in stride(from: 0, to: files.count, by: 500) {
                            let chunk = Array(files[offset..<min(files.count, offset + 500)])
                            let outcomes = try await admin.apply(chunk.map { ChangeRequest(file: $0, restore: true) }, authorization: authorization)
                            let restored = Set(outcomes.filter(\.success).map(\.path))
                            for i in updated.outcomes.indices where restored.contains(updated.outcomes[i].path) { updated.outcomes[i] = ChangeOutcome(path: updated.outcomes[i].path, success: true, message: "Restored", errorCode: 0) }
                            for path in restored where !recorded.contains(path) { updated.outcomes.append(ChangeOutcome(path: path, success: true, message: "Restored", errorCode: 0)) }
                            if let failure = outcomes.first(where: { !$0.success }) { errorMessage = failure.message }
                            try save(updated)
                        }
                        updated.restored = !updated.outcomes.contains { $0.success && $0.message == "Liberated" }
                        try save(updated)
                        if let index = journals.firstIndex(where: { $0.id == journal.id }) { journals[index] = updated }
                        status = "Administrator restore finished. Rescan to refresh results."
                    } catch { errorMessage = error.localizedDescription }
                    isWorking = false
                }
            } catch { errorMessage = error.localizedDescription }
            return
        }
        isWorking = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcomes = files.map { SafeMutation.apply(ChangeRequest(file: $0, restore: true), allowedRoots: [$0.path]) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let failed = outcomes.filter { !$0.success }
                var updated = journal
                let restored = Set(outcomes.filter(\.success).map(\.path))
                for i in updated.outcomes.indices where restored.contains(updated.outcomes[i].path) { updated.outcomes[i] = ChangeOutcome(path: updated.outcomes[i].path, success: true, message: "Restored", errorCode: 0) }
                for path in restored where !recorded.contains(path) { updated.outcomes.append(ChangeOutcome(path: path, success: true, message: "Restored", errorCode: 0)) }
                updated.restored = failed.isEmpty
                do { try self.save(updated) } catch { self.errorMessage = error.localizedDescription }
                if let i = self.journals.firstIndex(where: { $0.id == journal.id }) { self.journals[i] = updated }
                if self.page == 3 {
                    let rows = FindingList.rows(self.results.flatMap(\.files) + files.filter { restored.contains($0.path) })
                    self.apps = rows.filter(\.isApp); self.folders = rows.filter { !$0.isApp }
                }
                self.isWorking = false; self.status = "\(restored.count.formatted()) flags restored. Rescan to refresh your results."
                if !failed.isEmpty { self.errorMessage = "Some files changed or require additional permission. They were left untouched.\n" + failed.prefix(3).map(\.message).joined(separator: "\n") }
            }
        }
    }
    func exportReport() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Liberator report.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Export counts and paths, not attribute values or file contents.
            let rows = (apps + folders).map { ["path": $0.path, "inspected": $0.inspected, "quarantine": $0.quarantined, "provenance": $0.provenance, "unreadable": $0.errors, "partial": $0.cancelled, "cleanupPassLimited": $0.limited] as [String: Any] }
            try JSONSerialization.data(withJSONObject: ["generated": ISO8601DateFormatter().string(from: Date()), "results": rows], options: [.prettyPrinted, .sortedKeys]).write(to: url)
        } catch { errorMessage = error.localizedDescription }
    }
    func installHelper() {
        do { try admin.register(); refreshPermissions(); if admin.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() } }
        catch { errorMessage = error.localizedDescription }
    }
    func removeHelper() {
        Task { do { try await admin.unregister(); refreshPermissions() } catch { errorMessage = error.localizedDescription } }
    }
}
