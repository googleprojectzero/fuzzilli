import Foundation

final class OutputBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(newData)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return data.count
    }

    var currentData: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
