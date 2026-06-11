import Foundation

public enum SplitCalculatorError: Error, Equatable, Sendable {
    case emptyParticipants
    case duplicateParticipant(UUID)
    case unsupportedSplitType(SplitType)
    case exactAmountsRequired
    case missingAmountForParticipant(UUID)
    case extraAmountForNonParticipant(UUID)
    case amountHasTooManyFractionDigits(currency: String, maximumFractionDigits: Int)
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

        var seen = Set<UUID>()
        for participant in participants where !seen.insert(participant).inserted {
            throw SplitCalculatorError.duplicateParticipant(participant)
        }

        try validatePrecision(totalAmount, currency: currency)

        switch splitType {
        case .equal:
            return calculateEqual(total: totalAmount, currency: currency, participants: participants)
        case .exact:
            guard let amounts = exactAmounts else {
                throw SplitCalculatorError.exactAmountsRequired
            }
            return try calculateExact(total: totalAmount, currency: currency, participants: participants, amounts: amounts)
        case .percentage, .shares, .adjustment:
            throw SplitCalculatorError.unsupportedSplitType(splitType)
        }
    }

    // Distributes `total` evenly at the smallest supported unit for the currency.
    // Any remainder is assigned one minor unit at a time to the lowest sorted UUIDs.
    private static func calculateEqual(total: Decimal, currency: String, participants: [UUID]) -> [ExpenseSplit] {
        let n = Decimal(participants.count)
        let multiplier = CurrencyCatalog.minorUnitMultiplier(for: currency)
        let totalMinorUnits = roundToInteger(total * multiplier)
        let baseMinorUnits = roundDownToInteger(totalMinorUnits / n)
        let baseShare = baseMinorUnits / multiplier
        let remainderUnits = totalMinorUnits - baseMinorUnits * n

        let extraCount = (remainderUnits as NSDecimalNumber).intValue
        let sortedIDs = participants.sorted { $0.uuidString < $1.uuidString }
        let bonusIDs = Set(sortedIDs.prefix(extraCount))

        let smallestUnit = Decimal(1) / multiplier
        return participants.map { id in
            let owed = bonusIDs.contains(id) ? (baseShare + smallestUnit) : baseShare
            return ExpenseSplit(participantID: id, amountOwed: owed, splitType: .equal)
        }
    }

    private static func calculateExact(
        total: Decimal,
        currency: String,
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

        for amount in amounts.values {
            try validatePrecision(amount, currency: currency)
        }

        let sum = amounts.values.reduce(Decimal(0), +)
        if sum != total {
            throw SplitCalculatorError.amountsDoNotSumToTotal(expected: total, actual: sum)
        }

        return participants.map { id in
            ExpenseSplit(participantID: id, amountOwed: amounts[id]!, splitType: .exact)
        }
    }

    private static func validatePrecision(_ amount: Decimal, currency: String) throws {
        guard CurrencyCatalog.hasValidPrecision(amount, currency: currency) else {
            throw SplitCalculatorError.amountHasTooManyFractionDigits(
                currency: CurrencyCatalog.normalizedCode(currency),
                maximumFractionDigits: CurrencyCatalog.fractionDigits(for: currency)
            )
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
