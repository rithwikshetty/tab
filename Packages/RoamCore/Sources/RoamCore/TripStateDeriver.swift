import Foundation

public enum TripState: Sendable, Equatable {
    case active
    case completed
}

public enum TripStateDeriver {
    public static let defaultInactivityThreshold: TimeInterval = 30 * 24 * 60 * 60

    public static func derive(
        balances: [UserBalance],
        lastActivityAt: Date,
        now: Date,
        inactivityThreshold: TimeInterval = defaultInactivityThreshold
    ) -> TripState {
        if balances.contains(where: { $0.amount != 0 }) {
            return .active
        }
        if now.timeIntervalSince(lastActivityAt) >= inactivityThreshold {
            return .completed
        }
        return .active
    }
}
