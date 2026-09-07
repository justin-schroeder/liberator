import Foundation

struct LaunchMeasurement: Sendable {
    let firstMilliseconds: Double
    let warmMilliseconds: Double
    let binaryCount: Int
    var description: String { String(format: "8 fresh Rust binaries: %.1f ms median first launch; %.1f ms warmed.", firstMilliseconds, warmMilliseconds) }
}
enum LaunchBenchmark {
    static func run() throws -> LaunchMeasurement {
        let fm = FileManager.default
        let choices = [fm.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/rustc").path, "/opt/homebrew/bin/rustc", "/usr/local/bin/rustc"]
        guard let compiler = choices.first(where: { fm.isExecutableFile(atPath: $0) }) else { throw NSError(domain: "Liberator", code: 31, userInfo: [NSLocalizedDescriptionKey: "Install a Rust toolchain to run this optional launch check. Scanning and cleanup do not require Rust."]) }
        let root = fm.temporaryDirectory.appendingPathComponent("LiberatorLaunchCheck-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var binaries: [URL] = []
        for i in 0..<8 {
            let src = root.appendingPathComponent("tiny\(i).rs")
            let binary = root.appendingPathComponent("tiny\(i)")
            try "fn main() { std::process::exit(\(i) - \(i)); }\n".write(to: src, atomically: true, encoding: .utf8)
            let p = Process(); p.executableURL = URL(fileURLWithPath: compiler); p.arguments = [src.path, "-o", binary.path]; p.currentDirectoryURL = root
            let log = root.appendingPathComponent("compiler.log"); _ = fm.createFile(atPath: log.path, contents: nil)
            let output = try FileHandle(forWritingTo: log); p.standardError = output; p.standardOutput = output
            try p.run(); p.waitUntilExit(); try output.close()
            guard p.terminationStatus == 0 else { throw NSError(domain: "Liberator", code: 32, userInfo: [NSLocalizedDescriptionKey: "Rust could not compile the launch check. Confirm that your compiler and Apple Command Line Tools work."]) }
            binaries.append(binary)
        }
        func measure() throws -> Double {
            let storage = Timings()
            DispatchQueue.concurrentPerform(iterations: binaries.count) { i in
                do {
                    let p = Process(); p.executableURL = binaries[i]
                    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                    let start = DispatchTime.now().uptimeNanoseconds
                    try p.run(); p.waitUntilExit()
                    guard p.terminationStatus == 0 else { throw POSIXError(.EIO) }
                    storage.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                } catch { storage.failed() }
            }
            let values = storage.values.sorted()
            guard values.count == binaries.count else { throw NSError(domain: "Liberator", code: 33, userInfo: [NSLocalizedDescriptionKey: "macOS prevented one of the test binaries from running. No system protection setting was changed."]) }
            return (values[3] + values[4]) / 2
        }
        return try LaunchMeasurement(firstMilliseconds: measure(), warmMilliseconds: measure(), binaryCount: binaries.count)
    }
}
private final class Timings: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [Double] = []
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return data }
    func append(_ value: Double) { lock.lock(); data.append(value); lock.unlock() }
    func failed() {}
}
