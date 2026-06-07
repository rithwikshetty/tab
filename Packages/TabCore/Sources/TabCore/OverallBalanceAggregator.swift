import Foundation

/// The stable, cross-container identity of a person.
///
/// The ledger (`BalanceEngine`, payments, splits, settlements) is keyed on
/// `trip_person.id`, which is *container-scoped* — the same human has a different
/// `trip_person.id` in every trip and every non-group shadow group. To net balances
/// across containers we first collapse each ledger id to a `ClaimIdentity`: the
/// claimed `user_id` when the person has signed in, otherwise their normalised email
/// as a surrogate. A pending email and the user it later claims refer to the same
/// human, so balances accrued before and after sign-in net rather than double-count.
public enum ClaimIdentity: Hashable, Sendable {
    case user(UUID)
    case email(String)

    /// Resolve a `trip_people` row to its claim identity.
    public static func resolve(userID: UUID?, email: String) -> ClaimIdentity {
        if let userID { return .user(userID) }
        return .email(email.lowercased())
    }

    /// Deterministic ordering key (also used to form canonical identity pairs).
    public var canonicalKey: String {
        switch self {
        case .user(let id): return "u:" + id.uuidString
        case .email(let email): return "e:" + email
        }
    }
}

/// One container's pre-computed `BalanceEngine` output, tagged with its id.
public struct ContainerBalances: Sendable {
    public let containerID: UUID
    public let balances: [UserBalance]

    public init(containerID: UUID, balances: [UserBalance]) {
        self.containerID = containerID
        self.balances = balances
    }
}

/// A netted balance between two people across every container, in one currency.
/// Positive `amount` means `withIdentity` owes `forIdentity` (mirrors `UserBalance`).
public struct OverallBalance: Hashable, Sendable {
    public let forIdentity: ClaimIdentity
    public let withIdentity: ClaimIdentity
    public let currency: String
    public let amount: Decimal

    public init(forIdentity: ClaimIdentity, withIdentity: ClaimIdentity, currency: String, amount: Decimal) {
        self.forIdentity = forIdentity
        self.withIdentity = withIdentity
        self.currency = currency
        self.amount = amount
    }
}

/// One container's contribution to a specific pair's balance — drives the per-source
/// breakdown on the friend-detail screen. Positive `amount` means the `with` identity
/// owes the `for` identity in this source.
public struct SourceBalance: Hashable, Sendable {
    public let containerID: UUID
    public let currency: String
    public let amount: Decimal

    public init(containerID: UUID, currency: String, amount: Decimal) {
        self.containerID = containerID
        self.currency = currency
        self.amount = amount
    }
}

/// Pure cross-container netting for the [[Friends]] tab. Runs `BalanceEngine` per
/// container unchanged (callers pass its output in), collapses each container's
/// ledger ids to `ClaimIdentity`, and sums per `(identity-pair, currency)`. Never
/// re-implements netting; never blends currencies (no FX).
public enum OverallBalanceAggregator {

    /// Net every person-pair across all containers. Returns mirrored rows per non-zero
    /// `(pair, currency)`, deterministically ordered.
    public static func aggregate(
        _ containers: [ContainerBalances],
        identityMap: [UUID: ClaimIdentity]
    ) -> [OverallBalance] {
        var canonical: [IdentityPairKey: [String: Decimal]] = [:]

        for container in containers {
            for row in container.balances {
                guard let a = identityMap[row.forUser],
                      let b = identityMap[row.withUser],
                      a != b else { continue }
                let key = IdentityPairKey(a, b)
                // `BalanceEngine` emits both directions; take only the lo-perspective
                // row so a mirrored pair contributes its magnitude once.
                guard a == key.lo else { continue }
                canonical[key, default: [:]][row.currency, default: 0] += row.amount
            }
        }

        var result: [OverallBalance] = []
        let orderedKeys = canonical.keys.sorted {
            $0.lo.canonicalKey != $1.lo.canonicalKey
                ? $0.lo.canonicalKey < $1.lo.canonicalKey
                : $0.hi.canonicalKey < $1.hi.canonicalKey
        }
        for key in orderedKeys {
            let byCurrency = canonical[key] ?? [:]
            for currency in byCurrency.keys.sorted() {
                let amount = byCurrency[currency] ?? 0
                guard amount != 0 else { continue }
                result.append(OverallBalance(forIdentity: key.lo, withIdentity: key.hi, currency: currency, amount: amount))
                result.append(OverallBalance(forIdentity: key.hi, withIdentity: key.lo, currency: currency, amount: -amount))
            }
        }
        return result
    }

    /// Per-container balances between one specific pair, in the `for` identity's
    /// perspective. Sources with no shared balance are omitted.
    public static func breakdown(
        _ containers: [ContainerBalances],
        identityMap: [UUID: ClaimIdentity],
        for forIdentity: ClaimIdentity,
        with withIdentity: ClaimIdentity
    ) -> [SourceBalance] {
        guard forIdentity != withIdentity else { return [] }

        var result: [SourceBalance] = []
        for container in containers {
            var byCurrency: [String: Decimal] = [:]
            for row in container.balances {
                guard let a = identityMap[row.forUser],
                      let b = identityMap[row.withUser],
                      a == forIdentity, b == withIdentity else { continue }
                byCurrency[row.currency, default: 0] += row.amount
            }
            for currency in byCurrency.keys.sorted() {
                let amount = byCurrency[currency] ?? 0
                guard amount != 0 else { continue }
                result.append(SourceBalance(containerID: container.containerID, currency: currency, amount: amount))
            }
        }
        return result.sorted {
            $0.containerID.uuidString != $1.containerID.uuidString
                ? $0.containerID.uuidString < $1.containerID.uuidString
                : $0.currency < $1.currency
        }
    }
}

/// Canonical unordered identity pair, lo/hi by `canonicalKey` — mirrors `PairKey`.
struct IdentityPairKey: Hashable {
    let lo: ClaimIdentity
    let hi: ClaimIdentity

    init(_ a: ClaimIdentity, _ b: ClaimIdentity) {
        if a.canonicalKey < b.canonicalKey {
            lo = a; hi = b
        } else {
            lo = b; hi = a
        }
    }
}
