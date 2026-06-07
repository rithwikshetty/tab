import Testing
import Foundation
@testable import TabCore

@Suite("OverallBalanceAggregator")
struct OverallBalanceAggregatorTests {
    // Claim identities (the stable cross-container identity).
    let aliceU = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    let bobU   = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!
    let carolU = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!

    // Per-container ledger ids (trip_person.id) — distinct per container, even for the same human.
    let a1 = UUID(uuidString: "00000000-0000-0000-0001-0000000000A1")!
    let b1 = UUID(uuidString: "00000000-0000-0000-0001-0000000000B1")!
    let c1 = UUID(uuidString: "00000000-0000-0000-0001-0000000000C1")!
    let a2 = UUID(uuidString: "00000000-0000-0000-0002-0000000000A2")!
    let b2 = UUID(uuidString: "00000000-0000-0000-0002-0000000000B2")!
    let a3 = UUID(uuidString: "00000000-0000-0000-0003-0000000000A3")!
    let b3 = UUID(uuidString: "00000000-0000-0000-0003-0000000000B3")!

    let trip1 = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let trip2 = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    let nonGroup = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    /// Build the two mirrored UserBalance rows BalanceEngine would emit for "debtor owes creditor amount".
    private func mirrored(creditor: UUID, debtor: UUID, amount: Decimal, currency: String) -> [UserBalance] {
        [
            UserBalance(forUser: creditor, withUser: debtor, currency: currency, amount: amount),
            UserBalance(forUser: debtor, withUser: creditor, currency: currency, amount: -amount),
        ]
    }

    private func container(_ id: UUID, _ rows: [UserBalance]) -> ContainerBalances {
        ContainerBalances(containerID: id, balances: rows)
    }

    // MARK: - aggregate

    @Test("empty input → empty")
    func empty() {
        #expect(OverallBalanceAggregator.aggregate([], identityMap: [:]).isEmpty)
    }

    @Test("single container, single pair → one mirrored Overall pair")
    func singlePair() throws {
        let c = container(trip1, mirrored(creditor: a1, debtor: b1, amount: 15, currency: "EUR"))
        let map: [UUID: ClaimIdentity] = [a1: .user(aliceU), b1: .user(bobU)]

        let result = OverallBalanceAggregator.aggregate([c], identityMap: map)

        #expect(result.count == 2)
        let aliceSide = try #require(result.first { $0.forIdentity == .user(aliceU) && $0.withIdentity == .user(bobU) })
        let bobSide = try #require(result.first { $0.forIdentity == .user(bobU) && $0.withIdentity == .user(aliceU) })
        #expect(aliceSide.currency == "EUR")
        #expect(aliceSide.amount == 15)   // Bob owes Alice 15
        #expect(bobSide.amount == -15)
    }

    @Test("mirrored input rows are not double-counted")
    func noDoubleCount() throws {
        // Input already contains BOTH directions (as BalanceEngine emits). Magnitude must stay 15, not 30.
        let c = container(trip1, mirrored(creditor: a1, debtor: b1, amount: 15, currency: "EUR"))
        let result = OverallBalanceAggregator.aggregate([c], identityMap: [a1: .user(aliceU), b1: .user(bobU)])
        let aliceSide = try #require(result.first { $0.forIdentity == .user(aliceU) })
        #expect(aliceSide.amount == 15)
    }

    @Test("same human across two containers collapses to one netted line")
    func collapseAcrossContainers() throws {
        // Trip1: Bob owes Alice 20 GBP. Trip2: Alice owes Bob 5 GBP (different trip_person ids).
        let cA = container(trip1, mirrored(creditor: a1, debtor: b1, amount: 20, currency: "GBP"))
        let cB = container(trip2, mirrored(creditor: b2, debtor: a2, amount: 5, currency: "GBP"))
        let map: [UUID: ClaimIdentity] = [
            a1: .user(aliceU), b1: .user(bobU),
            a2: .user(aliceU), b2: .user(bobU),
        ]

        let result = OverallBalanceAggregator.aggregate([cA, cB], identityMap: map)

        // One pair, two mirrored rows. Net: Bob owes Alice 20 - 5 = 15.
        #expect(result.count == 2)
        let aliceSide = try #require(result.first { $0.forIdentity == .user(aliceU) })
        #expect(aliceSide.amount == 15)
    }

    @Test("multi-currency stays partitioned — no FX blending")
    func multiCurrency() throws {
        let c = container(trip1,
            mirrored(creditor: a1, debtor: b1, amount: 20, currency: "GBP")
            + mirrored(creditor: a1, debtor: b1, amount: 10, currency: "EUR"))
        let map: [UUID: ClaimIdentity] = [a1: .user(aliceU), b1: .user(bobU)]

        let result = OverallBalanceAggregator.aggregate([c], identityMap: map)

        #expect(result.count == 4) // 2 currencies × mirrored
        let gbp = try #require(result.first { $0.forIdentity == .user(aliceU) && $0.currency == "GBP" })
        let eur = try #require(result.first { $0.forIdentity == .user(aliceU) && $0.currency == "EUR" })
        #expect(gbp.amount == 20)
        #expect(eur.amount == 10)
    }

    @Test("net-zero pair drops out")
    func zeroNets() {
        let cA = container(trip1, mirrored(creditor: a1, debtor: b1, amount: 10, currency: "GBP"))
        let cB = container(trip2, mirrored(creditor: b2, debtor: a2, amount: 10, currency: "GBP"))
        let map: [UUID: ClaimIdentity] = [
            a1: .user(aliceU), b1: .user(bobU),
            a2: .user(aliceU), b2: .user(bobU),
        ]
        #expect(OverallBalanceAggregator.aggregate([cA, cB], identityMap: map).isEmpty)
    }

    @Test("pending email identity nets with claimed user identity after claim — no double count")
    func claimContinuity() throws {
        // Pre-claim: Bob is a pending email participant in the non-group container; claimed user in trip1.
        let nonGroupRows = container(nonGroup, mirrored(creditor: a3, debtor: b3, amount: 10, currency: "GBP"))
        let tripRows = container(trip1, mirrored(creditor: a1, debtor: b1, amount: 5, currency: "GBP"))

        let preClaim: [UUID: ClaimIdentity] = [
            a3: .user(aliceU), b3: .email("bob@x.com"),
            a1: .user(aliceU), b1: .user(bobU),
        ]
        let pre = OverallBalanceAggregator.aggregate([nonGroupRows, tripRows], identityMap: preClaim)
        // Two distinct counterpart identities → Alice has two separate lines (10 vs email, 5 vs user).
        #expect(pre.filter { $0.forIdentity == .user(aliceU) }.count == 2)

        // Post-claim: the pending row's identity flips to bobU. Both should net into one line = 15, not 30.
        let postClaim: [UUID: ClaimIdentity] = [
            a3: .user(aliceU), b3: .user(bobU),
            a1: .user(aliceU), b1: .user(bobU),
        ]
        let post = OverallBalanceAggregator.aggregate([nonGroupRows, tripRows], identityMap: postClaim)
        let aliceVsBob = post.filter { $0.forIdentity == .user(aliceU) }
        #expect(aliceVsBob.count == 1)
        #expect(aliceVsBob.first?.amount == 15)
    }

    @Test("unmapped ledger ids are skipped, not crashed")
    func unmappedSkipped() {
        let c = container(trip1, mirrored(creditor: a1, debtor: b1, amount: 15, currency: "EUR"))
        // b1 deliberately absent from the map.
        let result = OverallBalanceAggregator.aggregate([c], identityMap: [a1: .user(aliceU)])
        #expect(result.isEmpty)
    }

    @Test("three-person container + a two-person trip net correctly per pair")
    func threePersonPlusTrip() throws {
        // Non-group {A,B,C}: B owes A 10 GBP, C owes A 10 GBP (A paid 30, equal 3-way).
        let ng = container(nonGroup,
            mirrored(creditor: a3, debtor: b3, amount: 10, currency: "GBP")
            + mirrored(creditor: a3, debtor: UUID(uuidString: "00000000-0000-0000-0003-0000000000C3")!, amount: 10, currency: "GBP"))
        // Trip {A,B}: A owes B 4 GBP.
        let tr = container(trip1, mirrored(creditor: b1, debtor: a1, amount: 4, currency: "GBP"))
        let cTP = UUID(uuidString: "00000000-0000-0000-0003-0000000000C3")!
        let map: [UUID: ClaimIdentity] = [
            a3: .user(aliceU), b3: .user(bobU), cTP: .user(carolU),
            a1: .user(aliceU), b1: .user(bobU),
        ]

        let result = OverallBalanceAggregator.aggregate([ng, tr], identityMap: map)

        // Alice<->Bob nets 10 - 4 = 6 (Bob owes Alice). Alice<->Carol = 10. No Bob<->Carol.
        let aliceBob = try #require(result.first { $0.forIdentity == .user(aliceU) && $0.withIdentity == .user(bobU) })
        #expect(aliceBob.amount == 6)
        let aliceCarol = try #require(result.first { $0.forIdentity == .user(aliceU) && $0.withIdentity == .user(carolU) })
        #expect(aliceCarol.amount == 10)
        #expect(result.contains { $0.forIdentity == .user(bobU) && $0.withIdentity == .user(carolU) } == false)
    }

    // MARK: - breakdown (per-source for the friend detail)

    @Test("breakdown returns per-container amounts for a specific pair, friend's-perspective signs")
    func breakdownPerSource() throws {
        let goa = container(trip1, mirrored(creditor: a1, debtor: b1, amount: 20, currency: "GBP")) // Bob owes Alice 20
        let europe = container(trip2, mirrored(creditor: a2, debtor: b2, amount: 15, currency: "EUR")) // Bob owes Alice 15... flip below
        let ng = container(nonGroup, mirrored(creditor: b3, debtor: a3, amount: 8, currency: "GBP")) // Alice owes Bob 8
        let map: [UUID: ClaimIdentity] = [
            a1: .user(aliceU), b1: .user(bobU),
            a2: .user(aliceU), b2: .user(bobU),
            a3: .user(aliceU), b3: .user(bobU),
        ]

        let sources = OverallBalanceAggregator.breakdown(
            [goa, europe, ng], identityMap: map, for: .user(aliceU), with: .user(bobU)
        )

        // From Alice's perspective: Goa +20 (Bob owes her), Europe +15, non-group -8 (she owes Bob).
        #expect(sources.count == 3)
        #expect(sources.first { $0.containerID == trip1 }?.amount == 20)
        #expect(sources.first { $0.containerID == trip2 }?.amount == 15)
        #expect(sources.first { $0.containerID == nonGroup }?.amount == -8)
    }

    @Test("breakdown excludes containers with no shared balance")
    func breakdownExcludesUnrelated() {
        let withBob = container(trip1, mirrored(creditor: a1, debtor: b1, amount: 20, currency: "GBP"))
        let withCarolOnly = container(trip2, mirrored(creditor: a2, debtor: UUID(uuidString: "00000000-0000-0000-0002-0000000000C2")!, amount: 5, currency: "GBP"))
        let map: [UUID: ClaimIdentity] = [
            a1: .user(aliceU), b1: .user(bobU),
            a2: .user(aliceU), UUID(uuidString: "00000000-0000-0000-0002-0000000000C2")!: .user(carolU),
        ]
        let sources = OverallBalanceAggregator.breakdown(
            [withBob, withCarolOnly], identityMap: map, for: .user(aliceU), with: .user(bobU)
        )
        #expect(sources.count == 1)
        #expect(sources.first?.containerID == trip1)
    }
}
