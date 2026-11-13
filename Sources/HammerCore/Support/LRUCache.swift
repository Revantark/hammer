/// Small bounded cache that evicts the least recently used entry.
public struct LRUCache<Key: Hashable, Value> {
    public let capacity: Int
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []   // least recent first

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { storage.count }

    public mutating func value(for key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    public mutating func insert(_ value: Value, for key: Key) {
        storage[key] = value
        touch(key)
        while storage.count > capacity {
            storage[order.removeFirst()] = nil
        }
    }

    public mutating func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
