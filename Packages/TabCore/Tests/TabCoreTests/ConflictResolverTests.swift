import Testing
import Foundation
@testable import TabCore

@Suite("ConflictResolver")
struct ConflictResolverTests {
    let lowerWriteID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let higherWriteID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: both alive

    @Test("both alive: later updatedAt wins")
    func bothAliveLaterWins() {
        let earlier = Versioned(value: "old", updatedAt: t0, deletedAt: nil, writeID: lowerWriteID)
        let later = Versioned(value: "new", updatedAt: t0.addingTimeInterval(60), deletedAt: nil, writeID: lowerWriteID)
        let winner = ConflictResolver.resolve(earlier, later)
        #expect(winner.value == "new")
    }

    @Test("both alive: identical updatedAt → higher writeID wins")
    func bothAliveTiebreakerWriteID() {
        let a = Versioned(value: "a-value", updatedAt: t0, deletedAt: nil, writeID: lowerWriteID)
        let b = Versioned(value: "b-value", updatedAt: t0, deletedAt: nil, writeID: higherWriteID)
        let winner = ConflictResolver.resolve(a, b)
        #expect(winner.value == "b-value")
    }

    @Test("both alive: identical updatedAt and writeID → deterministic (returns first)")
    func bothAliveFullTie() {
        let a = Versioned(value: "a-value", updatedAt: t0, deletedAt: nil, writeID: lowerWriteID)
        let b = Versioned(value: "b-value", updatedAt: t0, deletedAt: nil, writeID: lowerWriteID)
        let winner = ConflictResolver.resolve(a, b)
        #expect(winner.value == "a-value")
    }

    // MARK: delete-wins

    @Test("one deleted + one alive → deleted wins regardless of timestamps")
    func deletedWinsOverNewerEdit() {
        let alive = Versioned(value: "edited", updatedAt: t0.addingTimeInterval(3600), deletedAt: nil, writeID: higherWriteID)
        let deleted = Versioned(value: "tombstone", updatedAt: t0, deletedAt: t0, writeID: lowerWriteID)
        #expect(ConflictResolver.resolve(alive, deleted).value == "tombstone")
        #expect(ConflictResolver.resolve(deleted, alive).value == "tombstone")
    }

    @Test("both deleted: later deletedAt wins")
    func bothDeletedLaterWins() {
        let earlier = Versioned(value: "v1", updatedAt: t0, deletedAt: t0, writeID: lowerWriteID)
        let later = Versioned(value: "v2", updatedAt: t0, deletedAt: t0.addingTimeInterval(60), writeID: lowerWriteID)
        let winner = ConflictResolver.resolve(earlier, later)
        #expect(winner.value == "v2")
    }

    @Test("both deleted with identical deletedAt → higher writeID wins")
    func bothDeletedTiebreaker() {
        let a = Versioned(value: "a-tombstone", updatedAt: t0, deletedAt: t0, writeID: lowerWriteID)
        let b = Versioned(value: "b-tombstone", updatedAt: t0, deletedAt: t0, writeID: higherWriteID)
        let winner = ConflictResolver.resolve(a, b)
        #expect(winner.value == "b-tombstone")
    }

    // MARK: order independence

    @Test("resolve is order-independent for clear winners")
    func orderIndependent() {
        let earlier = Versioned(value: "old", updatedAt: t0, deletedAt: nil, writeID: lowerWriteID)
        let later = Versioned(value: "new", updatedAt: t0.addingTimeInterval(60), deletedAt: nil, writeID: lowerWriteID)
        #expect(ConflictResolver.resolve(earlier, later).value == "new")
        #expect(ConflictResolver.resolve(later, earlier).value == "new")
    }

    @Test("resolve is order-independent for writeID tiebreaker")
    func orderIndependentForTiebreaker() {
        let a = Versioned(value: "a", updatedAt: t0, deletedAt: nil, writeID: lowerWriteID)
        let b = Versioned(value: "b", updatedAt: t0, deletedAt: nil, writeID: higherWriteID)
        #expect(ConflictResolver.resolve(a, b).value == "b")
        #expect(ConflictResolver.resolve(b, a).value == "b")
    }

    // MARK: merge (sync pull decisions)

    @Test("merge: clean local row always takes the remote version")
    func mergeCleanLocalAppliesRemote() {
        // Local is clean (no pending push) but the server moved on — even an
        // older-looking remote stamp must apply, because a clean row has no
        // local change worth preserving.
        let local = WriteStamp(updatedAt: t0.addingTimeInterval(60), deletedAt: nil, writeID: higherWriteID)
        let remote = WriteStamp(updatedAt: t0, deletedAt: nil, writeID: lowerWriteID)
        #expect(ConflictResolver.merge(local: local, localIsDirty: false, remote: remote) == .applyRemote)
    }

    @Test("merge: dirty local edit newer than remote survives the pull")
    func mergeDirtyNewerLocalSurvives() {
        // The offline-edit-then-foreground scenario: the local pending write is
        // newer than the stale server row the pull returns. It must NOT be clobbered.
        let local = WriteStamp(updatedAt: t0.addingTimeInterval(60), deletedAt: nil, writeID: lowerWriteID)
        let remote = WriteStamp(updatedAt: t0, deletedAt: nil, writeID: higherWriteID)
        #expect(ConflictResolver.merge(local: local, localIsDirty: true, remote: remote) == .keepLocal)
    }

    @Test("merge: dirty local edit older than remote yields to the newer remote write")
    func mergeDirtyOlderLocalYields() {
        let local = WriteStamp(updatedAt: t0, deletedAt: nil, writeID: higherWriteID)
        let remote = WriteStamp(updatedAt: t0.addingTimeInterval(60), deletedAt: nil, writeID: lowerWriteID)
        #expect(ConflictResolver.merge(local: local, localIsDirty: true, remote: remote) == .applyRemote)
    }

    @Test("merge: remote delete beats a dirty local edit (delete-wins)")
    func mergeRemoteDeleteBeatsDirtyEdit() {
        let local = WriteStamp(updatedAt: t0.addingTimeInterval(3600), deletedAt: nil, writeID: higherWriteID)
        let remote = WriteStamp(updatedAt: t0, deletedAt: t0, writeID: lowerWriteID)
        #expect(ConflictResolver.merge(local: local, localIsDirty: true, remote: remote) == .applyRemote)
    }

    @Test("merge: dirty local delete beats a newer remote edit (delete-wins)")
    func mergeLocalDeleteBeatsNewerRemoteEdit() {
        let local = WriteStamp(updatedAt: t0, deletedAt: t0, writeID: lowerWriteID)
        let remote = WriteStamp(updatedAt: t0.addingTimeInterval(3600), deletedAt: nil, writeID: higherWriteID)
        #expect(ConflictResolver.merge(local: local, localIsDirty: true, remote: remote) == .keepLocal)
    }

    @Test("merge: identical writeIDs are already converged — keep local even when dirty-flagged")
    func mergeSameWriteIDKeepsLocal() {
        let local = WriteStamp(updatedAt: t0, deletedAt: nil, writeID: lowerWriteID)
        let remote = WriteStamp(updatedAt: t0.addingTimeInterval(60), deletedAt: nil, writeID: lowerWriteID)
        #expect(ConflictResolver.merge(local: local, localIsDirty: true, remote: remote) == .keepLocal)
    }
}
