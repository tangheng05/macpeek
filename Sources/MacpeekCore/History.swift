/// The last `capacity` samples, oldest first. Small enough that trimming the front is free.
public struct History<Value: Sendable & Equatable>: Equatable, Sendable {
    public let capacity: Int
    public private(set) var values: [Value] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public var last: Value? { values.last }

    public mutating func append(_ value: Value) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    public mutating func removeAll() {
        values.removeAll(keepingCapacity: true)
    }
}
