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

/// Write metadata without a payload — what sync needs to decide a merge.
public typealias WriteStamp = Versioned<Void>

extension Versioned where T == Void {
    public init(updatedAt: Date, deletedAt: Date?, writeID: UUID) {
        self.init(value: (), updatedAt: updatedAt, deletedAt: deletedAt, writeID: writeID)
    }
}

public enum MergeDecision: Sendable, Equatable {
    case keepLocal
    case applyRemote
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

    /// Pull-merge decision for one synced row.
    ///
    /// A row whose local and remote writeIDs match is already converged. A
    /// clean local row (no pending push) always takes the remote version —
    /// the server is authoritative for rows without local changes. A dirty
    /// local row goes through `resolve` (LWW + delete-wins + writeID
    /// tiebreaker); the local side only survives when it wins outright.
    public static func merge(
        local: WriteStamp,
        localIsDirty: Bool,
        remote: WriteStamp
    ) -> MergeDecision {
        if local.writeID == remote.writeID { return .keepLocal }
        guard localIsDirty else { return .applyRemote }
        let winner = resolve(local, remote)
        return winner.writeID == remote.writeID ? .applyRemote : .keepLocal
    }

    private static func tiebreakByWriteID<T>(_ a: Versioned<T>, _ b: Versioned<T>) -> Versioned<T> {
        a.writeID.uuidString >= b.writeID.uuidString ? a : b
    }
}
