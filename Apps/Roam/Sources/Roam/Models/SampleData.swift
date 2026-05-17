import Foundation

enum AvatarTone: CaseIterable {
    case terracotta, sage, sand, slate
}

struct DemoMember: Identifiable, Hashable {
    let id = UUID()
    let initial: String
    let name: String
    let tone: AvatarTone
}

struct DemoTrip: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let members: [DemoMember]
    let status: TripStatus
    let isCompleted: Bool

    enum TripStatus: Hashable {
        case owed(String)
        case owe(String)
        case settled(String)
    }
}

struct DemoExpense: Identifiable, Hashable {
    let id = UUID()
    let icon: String
    let name: String
    let payerName: String
    let payerIsYou: Bool
    let yourShare: String
    let totalAmount: String
}

struct DemoExpenseDay: Identifiable, Hashable {
    let id = UUID()
    let dateLabel: String
    let expenses: [DemoExpense]
}

struct DemoBalanceDetail: Identifiable, Hashable {
    let id = UUID()
    let counterparty: String
    let amount: String
}

struct DemoCategory: Identifiable, Hashable {
    let id = UUID()
    let icon: String
    let name: String
}

enum SampleData {
    static let you = DemoMember(initial: "T", name: "You", tone: .slate)
    static let anya = DemoMember(initial: "A", name: "Anya", tone: .terracotta)
    static let yara = DemoMember(initial: "Y", name: "Yara", tone: .sage)
    static let sam = DemoMember(initial: "S", name: "Sam", tone: .sand)

    static let lisbonMembers: [DemoMember] = [anya, yara, sam]

    static let trips: [DemoTrip] = [
        DemoTrip(
            name: "Lisbon w/ Anya & Sam",
            members: [anya, yara, sam],
            status: .owed("you're owed €42.50"),
            isCompleted: false
        ),
        DemoTrip(
            name: "Tokyo December",
            members: [
                DemoMember(initial: "M", name: "Mira", tone: .sage),
                DemoMember(initial: "K", name: "Kai", tone: .sand),
                DemoMember(initial: "R", name: "Rin", tone: .slate),
                DemoMember(initial: "N", name: "Noa", tone: .terracotta),
            ],
            status: .owe("you owe $128.00 + €15.20"),
            isCompleted: false
        ),
        DemoTrip(
            name: "Berlin Weekend",
            members: [
                DemoMember(initial: "J", name: "Jules", tone: .slate),
                DemoMember(initial: "L", name: "Liv", tone: .terracotta),
                DemoMember(initial: "P", name: "Pia", tone: .sage),
            ],
            status: .settled("settled · Mar 2026"),
            isCompleted: true
        ),
    ]

    static let lisbonBalance: (label: String, amount: String, details: [DemoBalanceDetail]) = (
        "You're owed",
        "€42.50",
        [
            DemoBalanceDetail(counterparty: "Anya owes you", amount: "€30.00"),
            DemoBalanceDetail(counterparty: "Sam owes you", amount: "€12.50"),
        ]
    )

    static let lisbonExpenseDays: [DemoExpenseDay] = [
        DemoExpenseDay(dateLabel: "May 14", expenses: [
            DemoExpense(icon: "🍽", name: "Dinner at Ramiro", payerName: "you", payerIsYou: true, yourShare: "€28.33", totalAmount: "€85.00"),
            DemoExpense(icon: "🚗", name: "Uber to Sintra", payerName: "Anya", payerIsYou: false, yourShare: "€7.47", totalAmount: "€22.40"),
        ]),
        DemoExpenseDay(dateLabel: "May 13", expenses: [
            DemoExpense(icon: "🍽", name: "Pastéis de Belém", payerName: "you", payerIsYou: true, yourShare: "€6.00", totalAmount: "€18.00"),
        ]),
        DemoExpenseDay(dateLabel: "May 12", expenses: [
            DemoExpense(icon: "🏨", name: "Airbnb (3 nights)", payerName: "Sam", payerIsYou: false, yourShare: "€140.00", totalAmount: "€420.00"),
            DemoExpense(icon: "🚗", name: "Train tickets", payerName: "you", payerIsYou: true, yourShare: "€18.67", totalAmount: "€56.00"),
        ]),
    ]

    static let categories: [DemoCategory] = [
        DemoCategory(icon: "🍽", name: "Food & Drink"),
        DemoCategory(icon: "🚗", name: "Transport"),
        DemoCategory(icon: "🏨", name: "Lodging"),
        DemoCategory(icon: "🎭", name: "Activities"),
        DemoCategory(icon: "🛍", name: "Shopping"),
        DemoCategory(icon: "⋯", name: "Other"),
    ]
}
