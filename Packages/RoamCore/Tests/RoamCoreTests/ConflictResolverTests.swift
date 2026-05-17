import Testing
import Foundation
@testable import RoamCore

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
}
