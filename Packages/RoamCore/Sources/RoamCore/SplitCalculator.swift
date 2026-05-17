import Foundation

public enum SplitCalculatorError: Error, Equatable, Sendable {
    case emptyParticipants
    case unsupportedSplitType(SplitType)
    case exactAmountsRequired
    case missingAmountForParticipant(UUID)
    case extraAmountForNonParticipant(UUID)
    case amountsDoNotSumToTotal(expected: Decimal, actual: Decimal)
}

public enum SplitCalculator {
    public static func calculate(
        totalAmount: Decimal,
        currency: String,
        participants: [UUID],
        splitType: SplitType,
        exactAmounts: [UUID: Decimal]? = nil
    ) throws -> [ExpenseSplit] {
        guard !participants.isEmpty else {
            throw SplitCalculatorError.emptyParticipants
        }

        switch splitType {
        case .equal:
            return calculateEqual(total: totalAmount, participants: participants)
        case .exact:
            guard let amounts = exactAmounts else {
                throw SplitCalculatorError.exactAmountsRequired
            }
            return try calculateExact(total: totalAmount, participants: participants, amounts: amounts)
        case .percentage, .shares, .adjustment:
            throw SplitCalculatorError.unsupportedSplitType(splitType)
        }
    }

    // Distributes `total` evenly across participants, rounded to 2 decimals.
    // Any 1-cent remainder is assigned to the participants with the lowest sorted UUIDs.
    private static func calculateEqual(total: Decimal, participants: [UUID]) -> [ExpenseSplit] {
        let n = Decimal(participants.count)
        let totalCents = roundToInteger(total * 100)
        let baseCents = roundDownToInteger(totalCents / n)
        let baseShare = baseCents / 100
        let remainderCents = totalCents - baseCents * n

        let extraCount = (remainderCents as NSDecimalNumber).intValue
        let sortedIDs = participants.sorted { $0.uuidString < $1.uuidString }
        let bonusIDs = Set(sortedIDs.prefix(extraCount))

        let oneCent = Decimal(1) / Decimal(100)
        return participants.map { id in
            let owed = bonusIDs.contains(id) ? (baseShare + oneCent) : baseShare
            return ExpenseSplit(participantID: id, amountOwed: owed, splitType: .equal)
        }
    }

    private static func calculateExact(
        total: Decimal,
        participants: [UUID],
        amounts: [UUID: Decimal]
    ) throws -> [ExpenseSplit] {
        let participantSet = Set(participants)

        for key in amounts.keys where !participantSet.contains(key) {
            throw SplitCalculatorError.extraAmountForNonParticipant(key)
        }
        for participant in participants where amounts[participant] == nil {
            throw SplitCalculatorError.missingAmountForParticipant(participant)
        }

        let sum = amounts.values.reduce(Decimal(0), +)
        if sum != total {
            throw SplitCalculatorError.amountsDoNotSumToTotal(expected: total, actual: sum)
        }

        return participants.map { id in
            ExpenseSplit(participantID: id, amountOwed: amounts[id]!, splitType: .exact)
        }
    }

    private static func roundToInteger(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }

    private static func roundDownToInteger(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .down)
        return result
    }
}
