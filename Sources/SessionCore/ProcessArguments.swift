import Foundation

/// What the system keeps of how a process was started, as `sysctl` hands it out under
/// `KERN_PROCARGS2`: the number of arguments, the path of the executable, padding, the arguments
/// and then the environment, each a string that ends in a zero.
public enum ProcessArguments {
    /// The environment the process was started with. Empty when the bytes are not of that shape.
    public static func environment(in bytes: [UInt8]) -> [String: String] {
        let countSize = MemoryLayout<Int32>.size
        guard bytes.count > countSize else { return [:] }
        let argumentCount = bytes.prefix(countSize).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        var index = countSize
        func string() -> String? {
            guard let end = bytes[index...].firstIndex(of: 0) else { return nil }
            defer { index = end + 1 }
            return String(decoding: bytes[index..<end], as: UTF8.self)
        }
        guard argumentCount >= 0, string() != nil else { return [:] }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        for _ in 0..<argumentCount {
            guard string() != nil else { return [:] }
        }
        var environment: [String: String] = [:]
        while let entry = string(), !entry.isEmpty {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        return environment
    }
}
