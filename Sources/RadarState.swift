import Foundation

struct RadarContact: Identifiable, Sendable {
    let id: UInt64
    let filename: String
    let born: TimeInterval
    private var scatter: UInt64 {
        var value = id &+ 0x9e3779b97f4a7c15
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
    var bearing: Double { Double(scatter & 0xffff_ffff) / Double(UInt32.max) * .pi * 2 }
    func age(at time: TimeInterval) -> Double { max(0, time - born) }
    func opacity(at time: TimeInterval) -> Double { pow(0.5, age(at: time) / RadarState.halfLife) }
    func range(at time: TimeInterval) -> Double {
        let initial = 0.57 + Double(scatter >> 32) / Double(UInt32.max) * 0.39
        return initial - age(at: time) * 0.028
    }
    func isVisible(at time: TimeInterval) -> Bool { age(at: time) < RadarState.lifetime && range(at: time) > 0.12 }
}

struct RadarState: Sendable {
    static let capacity = 300
    static let halfLife: TimeInterval = 8
    static let lifetime: TimeInterval = 32
    private(set) var contacts: [RadarContact] = []
    private var nextID: UInt64 = 0

    mutating func ingest(_ paths: [String], at time: TimeInterval) {
        contacts.removeAll { !$0.isVisible(at: time) }
        let incoming = paths.suffix(Self.capacity)
        let excess = max(0, contacts.count + incoming.count - Self.capacity)
        if excess > 0 { contacts.removeFirst(excess) }
        for path in incoming {
            contacts.append(RadarContact(id: nextID, filename: String(URL(fileURLWithPath: path).lastPathComponent.prefix(64)), born: time))
            nextID &+= 1
        }
    }
}
