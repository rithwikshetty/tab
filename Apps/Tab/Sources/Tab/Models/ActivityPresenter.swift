import Foundation

/// Where an Activity row navigates when tapped.
enum ActivityTarget: Hashable, Sendable {
    case trip(UUID)
    case expense(tripID: UUID, expenseID: UUID)
    case settlement(tripID: UUID, settlementID: UUID)
}

struct ActivityRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let icon: String
    let isNegative: Bool      // deletes/removals tint differently
    let title: String         // "Bo added Dinner"
    let detail: String?       // secondary line, e.g. "Bo → Cy"
    let trailing: String?     // money, e.g. "€80.00"
    let tripName: String
    let timeText: String      // "3:40 PM"
    let isUnread: Bool
    let target: ActivityTarget
}

struct ActivitySection: Identifiable, Hashable, Sendable {
    let id: String
    let dateLabel: String
    let rows: [ActivityRow]
}

enum ActivityPresenter {
    /// Build date-grouped feed sections. Own actions stay visible as history but
    /// are never marked unread. Muted trips still appear (silence, not hide) but
    /// are never marked unread.
    static func sections(
        from activities: [ActivityEntity],
        currentUserID: UUID,
        lastSeenAt: Date?,
        mutedTripIDs: Set<UUID>,
        myTripPersonIDs: Set<UUID>,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [ActivitySection] {
        let visible = activities.sorted { $0.timestamp > $1.timestamp }

        let since = lastSeenAt ?? .distantPast
        var order: [String] = []
        var grouped: [String: [ActivityRow]] = [:]

        for activity in visible {
            let isUnread = activity.actorID != currentUserID
                && activity.timestamp > since
                && !mutedTripIDs.contains(activity.tripID)
            let row = row(for: activity, myTripPersonIDs: myTripPersonIDs, isUnread: isUnread, calendar: calendar)
            let day = calendar.startOfDay(for: activity.timestamp)
            let key = ISO8601DateFormatter.dayKey.string(from: day)
            if grouped[key] == nil {
                grouped[key] = []
                order.append(key)
            }
            grouped[key]?.append(row)
        }

        return order.map { key in
            let day = ISO8601DateFormatter.dayKey.date(from: key) ?? now
            return ActivitySection(id: key, dateLabel: dateLabel(for: day, calendar: calendar, now: now), rows: grouped[key] ?? [])
        }
    }

    static func unreadCount(
        from activities: [ActivityEntity],
        currentUserID: UUID,
        lastSeenAt: Date?,
        mutedTripIDs: Set<UUID>
    ) -> Int {
        let since = lastSeenAt ?? .distantPast
        return activities.filter {
            $0.actorID != currentUserID && $0.timestamp > since && !mutedTripIDs.contains($0.tripID)
        }.count
    }

    // MARK: - Row mapping

    private static func row(
        for activity: ActivityEntity,
        myTripPersonIDs: Set<UUID>,
        isUnread: Bool,
        calendar: Calendar
    ) -> ActivityRow {
        let s = activity.snapshot
        let actor = s["actor_name"] ?? "Someone"
        let trip = s["trip_name"] ?? "a trip"
        let money = trailingMoney(s)

        var icon = "bell.fill"
        var negative = false
        var title = "\(actor) updated \(trip)"
        var detail: String? = nil
        var target: ActivityTarget = .trip(activity.tripID)

        switch activity.action {
        case "expense_created":
            icon = "plus.circle.fill"
            title = "\(actor) added \(s["description"] ?? "an expense")"
            target = .expense(tripID: activity.tripID, expenseID: activity.entityID)
        case "expense_updated":
            icon = "pencil.circle.fill"
            title = "\(actor) edited \(s["description"] ?? "an expense")"
            target = .expense(tripID: activity.tripID, expenseID: activity.entityID)
        case "expense_deleted":
            icon = "trash.circle.fill"
            negative = true
            title = "\(actor) deleted \(s["description"] ?? "an expense")"
        case "settlement_created":
            icon = "arrow.left.arrow.right.circle.fill"
            title = "\(actor) recorded a payment"
            detail = settlementDetail(s)
            target = .settlement(tripID: activity.tripID, settlementID: activity.entityID)
        case "settlement_updated":
            icon = "arrow.left.arrow.right.circle.fill"
            title = "\(actor) edited a payment"
            detail = settlementDetail(s)
            target = .settlement(tripID: activity.tripID, settlementID: activity.entityID)
        case "settlement_deleted":
            icon = "arrow.left.arrow.right.circle.fill"
            negative = true
            title = "\(actor) removed a payment"
            detail = settlementDetail(s)
        case "member_joined":
            icon = "person.crop.circle.badge.plus"
            if myTripPersonIDs.contains(activity.entityID) {
                title = "You were added to \(trip)"
            } else {
                title = "\(actor) added \(s["member_name"] ?? "someone")"
            }
        case "member_left":
            icon = "person.crop.circle.badge.minus"
            negative = true
            title = "\(actor) removed \(s["member_name"] ?? "someone")"
        case "trip_created":
            icon = "suitcase.fill"
            title = "\(actor) created \(trip)"
        case "trip_updated":
            icon = "pencil"
            title = "\(actor) renamed the trip to \(trip)"
        default:
            break
        }

        return ActivityRow(
            id: activity.id,
            icon: icon,
            isNegative: negative,
            title: title,
            detail: detail,
            trailing: money,
            tripName: trip,
            timeText: timeText(for: activity.timestamp),
            isUnread: isUnread,
            target: target
        )
    }

    private static func trailingMoney(_ s: [String: String]) -> String? {
        guard let amountRaw = s["amount"], let currency = s["currency"],
              let amount = MoneyFormatter.decimal(from: amountRaw) else { return nil }
        return MoneyFormatter.formatSymbol(amount, currency: currency)
    }

    private static func settlementDetail(_ s: [String: String]) -> String? {
        guard let from = s["from_name"], let to = s["to_name"] else { return nil }
        return "\(from) → \(to)"
    }

    // MARK: - Dates

    private static func dateLabel(for day: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = calendar.isDate(day, equalTo: now, toGranularity: .year) ? "EEEE, MMM d" : "MMM d, yyyy"
        return formatter.string(from: day)
    }

    private static func timeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

private extension ISO8601DateFormatter {
    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}
