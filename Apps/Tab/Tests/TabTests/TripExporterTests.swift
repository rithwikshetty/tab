import Foundation
import Testing
@testable import Tab

@Suite("Trip export")
struct TripExporterTests {
    @Test("workbook keeps expense overview readable and adds normalized payment and split sheets")
    func workbookHasNormalizedExpensePaymentAndSplitSheets() {
        let expenseID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let aliceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let bobID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let caraID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let data = TripExporter.ExportData(
            tripName: "Barcelona",
            expenses: [
                TripExporter.ExpenseRow(
                    id: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    amount: 120,
                    currency: "EUR",
                    category: "Food",
                    paidBy: "Alice, Bob",
                    paidByDetail: "Alice: EUR 70.00; Bob: EUR 50.00",
                    splitBetween: "Alice, Bob, Cara",
                    splitDetail: "Alice: EUR 40.00; Bob: EUR 40.00; Cara: EUR 40.00",
                    paymentMethod: "equal",
                    createdBy: "Alice",
                    createdAt: "2026-05-22 20:30",
                    lastEditedBy: "Cara",
                    lastEditedAt: "2026-05-22 21:00"
                )
            ],
            expensePayments: [
                TripExporter.ExpensePaymentRow(
                    expenseID: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    payerID: aliceID.uuidString,
                    payerName: "Alice",
                    currency: "EUR",
                    amountPaid: 70,
                    paymentMethod: "equal"
                ),
                TripExporter.ExpensePaymentRow(
                    expenseID: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    payerID: bobID.uuidString,
                    payerName: "Bob",
                    currency: "EUR",
                    amountPaid: 50,
                    paymentMethod: "equal"
                )
            ],
            expenseSplits: [
                TripExporter.ExpenseSplitRow(
                    expenseID: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    participantID: aliceID.uuidString,
                    participantName: "Alice",
                    currency: "EUR",
                    amountOwed: 40,
                    splitType: "equal"
                ),
                TripExporter.ExpenseSplitRow(
                    expenseID: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    participantID: bobID.uuidString,
                    participantName: "Bob",
                    currency: "EUR",
                    amountOwed: 40,
                    splitType: "equal"
                ),
                TripExporter.ExpenseSplitRow(
                    expenseID: expenseID.uuidString,
                    date: "2026-05-22",
                    description: "Dinner",
                    participantID: caraID.uuidString,
                    participantName: "Cara",
                    currency: "EUR",
                    amountOwed: 40,
                    splitType: "equal"
                )
            ],
            settlements: [],
            summary: TripExporter.Summary(
                totalsByCurrency: [TripExporter.CurrencyTotal(currency: "EUR", total: 120)],
                personSummaries: [],
                pairBalances: []
            )
        )

        let workbook = TripExporter.buildWorkbook(from: data)

        #expect(workbook.sheets.map(\.name) == [
            "Expenses",
            "Expense Payments",
            "Expense Splits",
            "Settlements",
            "Summary"
        ])

        let expenses = workbook.sheets[0].rows
        #expect(expenses[0].strings == [
            "Expense ID", "Date", "Description", "Amount", "Currency", "Category",
            "Paid By", "Paid By Detail", "Split Between", "Split Detail", "Payment Method",
            "Created By", "Created At", "Last Edited By", "Last Edited At"
        ])
        #expect(expenses[1].strings[6] == "Alice, Bob")
        #expect(expenses[1].strings[7] == "Alice: EUR 70.00; Bob: EUR 50.00")
        #expect(expenses[1].strings[8] == "Alice, Bob, Cara")
        #expect(expenses[1].strings[9] == "Alice: EUR 40.00; Bob: EUR 40.00; Cara: EUR 40.00")

        let payments = workbook.sheets[1].rows
        #expect(payments.count == 3)
        #expect(payments[0].strings == [
            "Expense ID", "Date", "Description", "Payer ID", "Payer Name",
            "Currency", "Amount Paid", "Payment Method"
        ])
        #expect(payments[1].strings[3] == aliceID.uuidString)
        #expect(payments[1].strings[4] == "Alice")

        let splits = workbook.sheets[2].rows
        #expect(splits.count == 4)
        #expect(splits[0].strings == [
            "Expense ID", "Date", "Description", "Participant ID", "Participant Name",
            "Currency", "Amount Owed", "Split Type"
        ])
        #expect(splits[3].strings[3] == caraID.uuidString)
        #expect(splits[3].strings[4] == "Cara")
    }
}

private extension Array where Element == TripExporter.WorkbookCell {
    var strings: [String] {
        map { cell in
            switch cell {
            case .string(let value): value
            case .number(let value): value.description
            }
        }
    }
}
