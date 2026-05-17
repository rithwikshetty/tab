import Testing
import Foundation
@testable import RoamCore

@Suite("TripStateDeriver")
struct TripStateDeriverTests {
    let alice = UUID()
    let bob = UUID()
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: settled trips

    @Test("no outstanding balances + recent activity → active")
    func settledRecentActivity() {
        let lastActivity = now.addingTimeInterval(-1 * 24 * 60 * 60)  // 1 day ago
        let state = TripStateDeriver.derive(
            balances: [],
            lastActivityAt: lastActivity,
            now: now
        )
        #expect(state == .active)
    }

    @Test("no outstanding balances + stale activity (>30d) → completed")
    func settledStaleActivity() {
        let lastActivity = now.addingTimeInterval(-31 * 24 * 60 * 60)
        let state = TripStateDeriver.derive(
            balances: [],
            lastActivityAt: lastActivity,
            now: now
        )
        #expect(state == .completed)
    }

    @Test("no outstanding balances + exactly 30d boundary → completed")
    func settledExactBoundary() {
        let lastActivity = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let state = TripStateDeriver.derive(
            balances: [],
            lastActivityAt: lastActivity,
            now: now
        )
        #expect(state == .completed)
    }

    @Test("no outstanding balances + just-under-30d → active")
    func settledJustUnderBoundary() {
        // 30 days minus 1 second
        let lastActivity = now.addingTimeInterval(-30 * 24 * 60 * 60 + 1)
        let state = TripStateDeriver.derive(
            balances: [],
            lastActivityAt: lastActivity,
            now: now
        )
        #expect(state == .active)
    }

    // MARK: outstanding balances

    @Test("non-zero balance + stale activity → active (balance dominates)")
    func unsettledStale() {
        let balance = UserBalance(forUser: alice, withUser: bob, currency: "EUR", amount: 50)
        let lastActivity = now.addingTimeInterval(-365 * 24 * 60 * 60)  // 1 year ago
        let state = TripStateDeriver.derive(
            balances: [balance],
            lastActivityAt: lastActivity,
            now: now
        )
        #expect(state == .active)
    }

    @Test("non-zero balance + recent activity → active")
    func unsettledRecent() {
        let balance = UserBalance(forUser: alice, withUser: bob, currency: "EUR", amount: -25)
        let state = TripStateDeriver.derive(
            balances: [balance],
            lastActivityAt: now,
            now: now
        )
        #expect(state == .active)
    }

    @Test("multi-currency: any non-zero in any currency → active")
    func multiCurrencyAnyNonZero() {
        // BalanceEngine never emits zero balances, but be defensive.
        let zero = UserBalance(forUser: alice, withUser: bob, currency: "EUR", amount: 0)
        let nonZero = UserBalance(forUser: alice, withUser: bob, currency: "USD", amount: 10)
        let lastActivity = now.addingTimeInterval(-100 * 24 * 60 * 60)
        let state = TripStateDeriver.derive(
            balances: [zero, nonZero],
            lastActivityAt: lastActivity,
            now: now
        )
        #expect(state == .active)
    }

    @Test("defensive: only zero-amount balances + stale → completed")
    func onlyZeroBalances() {
        let zero = UserBalance(forUser: alice, withUser: bob, currency: "EUR", amount: 0)
        let lastActivity = now.addingTimeInterval(-60 * 24 * 60 * 60)
        let state = TripStateDeriver.derive(
            balances: [zero],
            lastActivityAt: lastActivity,
            now: now
        )
        #expect(state == .completed)
    }

    // MARK: configurable threshold

    @Test("custom threshold: settled and beyond custom → completed")
    func customThresholdCompleted() {
        let lastActivity = now.addingTimeInterval(-8 * 24 * 60 * 60)
        let state = TripStateDeriver.derive(
            balances: [],
            lastActivityAt: lastActivity,
            now: now,
            inactivityThreshold: 7 * 24 * 60 * 60  // 7 days
        )
        #expect(state == .completed)
    }

    @Test("custom threshold: settled but within custom → active")
    func customThresholdActive() {
        let lastActivity = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let state = TripStateDeriver.derive(
            balances: [],
            lastActivityAt: lastActivity,
            now: now,
            inactivityThreshold: 7 * 24 * 60 * 60
        )
        #expect(state == .active)
    }
}
