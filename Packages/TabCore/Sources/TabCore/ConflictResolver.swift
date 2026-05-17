import Foundation

public struct Versioned<T>: Sendable where T: Sendable {
    public let value: T
    public let updatedAt: Date
    public let deletedAt: Date?
    public let writeID: UUID

    public init(value: T, updatedAt: Date, deletedAt: Date?, writeID: UUID) {
        self.value = value
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.writeID = writeID
    }
}

public enum ConflictResolver {
    // Policy:
    // 1. If exactly one side is deleted, the deleted side wins.
    // 2. If both are deleted, the later deletedAt wins (writeID tiebreaker).
    // 3. Otherwise both are alive: later updatedAt wins (writeID tiebreaker).
    // 4. On full ties, the first argument wins (deterministic).
    public static func resolve<T>(_ a: Versioned<T>, _ b: Versioned<T>) -> Versioned<T> {
        switch (a.deletedAt, b.deletedAt) {
        case (let aDeleted?, let bDeleted?):
            if aDeleted != bDeleted {
                return aDeleted > bDeleted ? a : b
            }
            return tiebreakByWriteID(a, b)
        case (_?, nil):
            return a
        case (nil, _?):
            return b
        case (nil, nil):
            if a.updatedAt != b.updatedAt {
                return a.updatedAt > b.updatedAt ? a : b
            }
            return tiebreakByWriteID(a, b)
        }
    }

    private static func tiebreakByWriteID<T>(_ a: Versioned<T>, _ b: Versioned<T>) -> Versioned<T> {
        a.writeID.uuidString >= b.writeID.uuidString ? a : b
    }
}
