import Foundation
import SwiftData
import TabCore

enum TripExporter {

    struct ExportData: Sendable {
        let tripName: String
        let expenses: [ExpenseRow]
        let settlements: [SettlementRow]
        let summary: Summary
    }

    struct ExpenseRow: Sendable {
        let date: String
        let description: String
        let amount: Decimal
        let currency: String
        let category: String
        let paidBy: String
        let splitBetween: String
        let paymentMethod: String
        let createdBy: String
        let createdAt: String
        let lastEditedBy: String
        let lastEditedAt: String
    }

    struct SettlementRow: Sendable {
        let date: String
        let from: String
        let to: String
        let amount: Decimal
        let currency: String
        let note: String
    }

    struct CurrencyTotal: Sendable {
        let currency: String
        let total: Decimal
    }

    struct Summary: Sendable {
        let totalsByCurrency: [CurrencyTotal]
        let personSummaries: [PersonSummary]
        let pairBalances: [PairBalance]
    }

    struct PersonSummary: Sendable {
        let name: String
        let currency: String
        let totalPaid: Decimal
        let totalOwed: Decimal
    }

    struct PairBalance: Sendable {
        let from: String
        let to: String
        let currency: String
        let amount: Decimal
    }

    // MARK: - Data extraction

    @MainActor
    static func extractData(
        trip: TripEntity,
        categories: [UUID: CategoryEntity],
        peopleByID: [UUID: TripPersonEntity]
    ) -> ExportData {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        let activeExpenses = trip.expenses
            .filter { $0.deletedAt == nil }
            .sorted { $0.expenseDate < $1.expenseDate }

        let expenseRows: [ExpenseRow] = activeExpenses.map { expense in
            let paidByParts = expense.payments
                .sorted { $0.tripPersonID.uuidString < $1.tripPersonID.uuidString }
                .map { payment in
                    let name = peopleByID[payment.tripPersonID]?.displayName ?? "Unknown"
                    return "\(name) (\(formatDecimal(payment.amountPaid)))"
                }

            let splitParts = expense.splits
                .sorted { $0.tripPersonID.uuidString < $1.tripPersonID.uuidString }
                .map { split in
                    let name = peopleByID[split.tripPersonID]?.displayName ?? "Unknown"
                    return "\(name) (\(formatDecimal(split.amountOwed)))"
                }

            let categoryName = expense.categoryID
                .flatMap { categories[$0]?.name } ?? ""

            let createdByName = peopleByID.values
                .first(where: { $0.userID == expense.createdByID })?.displayName
                ?? expense.createdByID.uuidString

            let lastEditedByName: String
            if let editorID = expense.lastEditedByID {
                lastEditedByName = peopleByID.values
                    .first(where: { $0.userID == editorID })?.displayName
                    ?? editorID.uuidString
            } else {
                lastEditedByName = ""
            }

            return ExpenseRow(
                date: dateFormatter.string(from: expense.expenseDate),
                description: expense.descriptionText,
                amount: expense.amount,
                currency: expense.currency,
                category: categoryName,
                paidBy: paidByParts.joined(separator: "; "),
                splitBetween: splitParts.joined(separator: "; "),
                paymentMethod: expense.payments.first?.paymentModeRaw ?? "",
                createdBy: createdByName,
                createdAt: timestampFormatter.string(from: expense.createdAt),
                lastEditedBy: lastEditedByName,
                lastEditedAt: expense.lastEditedByID != nil
                    ? timestampFormatter.string(from: expense.updatedAt)
                    : ""
            )
        }

        let activeSettlements = trip.settlements
            .filter { $0.deletedAt == nil }
            .sorted { $0.settledAt < $1.settledAt }

        let settlementRows: [SettlementRow] = activeSettlements.map { settlement in
            let fromName = peopleByID[settlement.fromPersonID]?.displayName ?? "Unknown"
            let toName = peopleByID[settlement.toPersonID]?.displayName ?? "Unknown"
            return SettlementRow(
                date: dateFormatter.string(from: settlement.settledAt),
                from: fromName,
                to: toName,
                amount: settlement.amount,
                currency: settlement.currency,
                note: settlement.note ?? ""
            )
        }

        let coreExpenses = activeExpenses.map { $0.toCoreExpense() }
        let coreSettlements = activeSettlements.map { $0.toCoreSettlement() }

        // Totals by currency
        var currencyTotals: [String: Decimal] = [:]
        for expense in activeExpenses {
            currencyTotals[expense.currency, default: 0] += expense.amount
        }
        let totalsByCurrency = currencyTotals
            .sorted { $0.key < $1.key }
            .map { CurrencyTotal(currency: $0.key, total: $0.value) }

        // Per-person paid and owed
        var personPaid: [UUID: [String: Decimal]] = [:]
        var personOwed: [UUID: [String: Decimal]] = [:]
        for expense in activeExpenses {
            for payment in expense.payments {
                personPaid[payment.tripPersonID, default: [:]][expense.currency, default: 0] += payment.amountPaid
            }
            for split in expense.splits {
                personOwed[split.tripPersonID, default: [:]][expense.currency, default: 0] += split.amountOwed
            }
        }

        let allPersonIDs = Set(personPaid.keys).union(personOwed.keys)
        let allCurrencies = Set(currencyTotals.keys).sorted()

        var personSummaries: [PersonSummary] = []
        for personID in allPersonIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let name = peopleByID[personID]?.displayName ?? "Unknown"
            for currency in allCurrencies {
                let paid = personPaid[personID]?[currency] ?? 0
                let owed = personOwed[personID]?[currency] ?? 0
                if paid != 0 || owed != 0 {
                    personSummaries.append(PersonSummary(
                        name: name,
                        currency: currency,
                        totalPaid: paid,
                        totalOwed: owed
                    ))
                }
            }
        }

        // Net balances between pairs
        let balances = BalanceEngine.compute(expenses: coreExpenses, settlements: coreSettlements)
        var seenPairs: Set<String> = []
        var pairBalances: [PairBalance] = []
        for balance in balances where balance.amount > 0 {
            let pairKey = [balance.forUser.uuidString, balance.withUser.uuidString].sorted().joined(separator: "-")
            guard !seenPairs.contains(pairKey) else { continue }
            seenPairs.insert(pairKey)
            let fromName = peopleByID[balance.withUser]?.displayName ?? "Unknown"
            let toName = peopleByID[balance.forUser]?.displayName ?? "Unknown"
            pairBalances.append(PairBalance(
                from: fromName,
                to: toName,
                currency: balance.currency,
                amount: balance.amount
            ))
        }

        let summary = Summary(
            totalsByCurrency: totalsByCurrency,
            personSummaries: personSummaries,
            pairBalances: pairBalances
        )

        return ExportData(
            tripName: trip.name,
            expenses: expenseRows,
            settlements: settlementRows,
            summary: summary
        )
    }

    // MARK: - XLSX generation

    static func generateXLSX(from data: ExportData) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let xlsxDir = tempDir.appendingPathComponent("xlsx", isDirectory: true)
        try FileManager.default.createDirectory(
            at: xlsxDir.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: xlsxDir.appendingPathComponent("xl/_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: xlsxDir.appendingPathComponent("xl/worksheets"), withIntermediateDirectories: true)

        let sharedStrings = SharedStringTable()
        let sheet1 = buildExpensesSheet(data.expenses, strings: sharedStrings)
        let sheet2 = buildSettlementsSheet(data.settlements, strings: sharedStrings)
        let sheet3 = buildSummarySheet(data.summary, strings: sharedStrings)

        try writeContentTypes(to: xlsxDir)
        try writeRels(to: xlsxDir)
        try writeWorkbook(to: xlsxDir)
        try writeWorkbookRels(to: xlsxDir)
        try writeStyles(to: xlsxDir)
        try sharedStrings.write(to: xlsxDir)
        try sheet1.write(to: xlsxDir.appendingPathComponent("xl/worksheets/sheet1.xml"))
        try sheet2.write(to: xlsxDir.appendingPathComponent("xl/worksheets/sheet2.xml"))
        try sheet3.write(to: xlsxDir.appendingPathComponent("xl/worksheets/sheet3.xml"))

        let sanitizedName = data.tripName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let outputURL = tempDir.appendingPathComponent("\(sanitizedName) Expenses.xlsx")
        try zipDirectory(xlsxDir, to: outputURL)

        let documentsDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let finalURL = documentsDir.appendingPathComponent("\(sanitizedName) Expenses.xlsx")
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.copyItem(at: outputURL, to: finalURL)

        return finalURL
    }

    // MARK: - Sheet builders

    private static func buildExpensesSheet(
        _ rows: [ExpenseRow],
        strings: SharedStringTable
    ) -> SheetBuilder {
        let builder = SheetBuilder()
        builder.addRow([
            "Date", "Description", "Amount", "Currency", "Category",
            "Paid By", "Split Between", "Payment Method",
            "Created By", "Created At", "Last Edited By", "Last Edited At"
        ].map { .string(strings.index(for: $0)) })

        for row in rows {
            builder.addRow([
                .string(strings.index(for: row.date)),
                .string(strings.index(for: row.description)),
                .number(row.amount),
                .string(strings.index(for: row.currency)),
                .string(strings.index(for: row.category)),
                .string(strings.index(for: row.paidBy)),
                .string(strings.index(for: row.splitBetween)),
                .string(strings.index(for: row.paymentMethod)),
                .string(strings.index(for: row.createdBy)),
                .string(strings.index(for: row.createdAt)),
                .string(strings.index(for: row.lastEditedBy)),
                .string(strings.index(for: row.lastEditedAt)),
            ])
        }
        return builder
    }

    private static func buildSettlementsSheet(
        _ rows: [SettlementRow],
        strings: SharedStringTable
    ) -> SheetBuilder {
        let builder = SheetBuilder()
        builder.addRow([
            "Date", "From", "To", "Amount", "Currency", "Note"
        ].map { .string(strings.index(for: $0)) })

        for row in rows {
            builder.addRow([
                .string(strings.index(for: row.date)),
                .string(strings.index(for: row.from)),
                .string(strings.index(for: row.to)),
                .number(row.amount),
                .string(strings.index(for: row.currency)),
                .string(strings.index(for: row.note)),
            ])
        }
        return builder
    }

    private static func buildSummarySheet(
        _ summary: Summary,
        strings: SharedStringTable
    ) -> SheetBuilder {
        let builder = SheetBuilder()

        // Section: Total Spent
        builder.addRow([.string(strings.index(for: "Total Spent per Currency"))])
        builder.addRow([
            .string(strings.index(for: "Currency")),
            .string(strings.index(for: "Total")),
        ])
        for entry in summary.totalsByCurrency {
            builder.addRow([
                .string(strings.index(for: entry.currency)),
                .number(entry.total),
            ])
        }

        builder.addRow([])

        // Section: Per-person breakdown
        builder.addRow([.string(strings.index(for: "Per-Person Breakdown"))])
        builder.addRow([
            .string(strings.index(for: "Person")),
            .string(strings.index(for: "Currency")),
            .string(strings.index(for: "Total Paid")),
            .string(strings.index(for: "Total Owed")),
            .string(strings.index(for: "Net")),
        ])
        for ps in summary.personSummaries {
            let net = ps.totalPaid - ps.totalOwed
            builder.addRow([
                .string(strings.index(for: ps.name)),
                .string(strings.index(for: ps.currency)),
                .number(ps.totalPaid),
                .number(ps.totalOwed),
                .number(net),
            ])
        }

        builder.addRow([])

        // Section: Net Balances
        builder.addRow([.string(strings.index(for: "Net Balances Between Pairs"))])
        builder.addRow([
            .string(strings.index(for: "Owes (From)")),
            .string(strings.index(for: "Owed To")),
            .string(strings.index(for: "Currency")),
            .string(strings.index(for: "Amount")),
        ])
        for pb in summary.pairBalances {
            builder.addRow([
                .string(strings.index(for: pb.from)),
                .string(strings.index(for: pb.to)),
                .string(strings.index(for: pb.currency)),
                .number(pb.amount),
            ])
        }

        return builder
    }

    // MARK: - XLSX XML files

    private static func writeContentTypes(to dir: URL) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
          <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
        </Types>
        """
        try xml.write(to: dir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
    }

    private static func writeRels(to dir: URL) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try xml.write(to: dir.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
    }

    private static func writeWorkbook(to dir: URL) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Expenses" sheetId="1" r:id="rId1"/>
            <sheet name="Settlements" sheetId="2" r:id="rId2"/>
            <sheet name="Summary" sheetId="3" r:id="rId3"/>
          </sheets>
        </workbook>
        """
        try xml.write(to: dir.appendingPathComponent("xl/workbook.xml"), atomically: true, encoding: .utf8)
    }

    private static func writeWorkbookRels(to dir: URL) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
          <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
          <Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
        </Relationships>
        """
        try xml.write(to: dir.appendingPathComponent("xl/_rels/workbook.xml.rels"), atomically: true, encoding: .utf8)
    }

    private static func writeStyles(to dir: URL) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="2">
            <font><sz val="11"/><name val="Calibri"/></font>
            <font><b/><sz val="11"/><name val="Calibri"/></font>
          </fonts>
          <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
          </fills>
          <borders count="1">
            <border><left/><right/><top/><bottom/><diagonal/></border>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="2">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
          </cellXfs>
        </styleSheet>
        """
        try xml.write(to: dir.appendingPathComponent("xl/styles.xml"), atomically: true, encoding: .utf8)
    }

    // MARK: - ZIP

    private static func zipDirectory(_ sourceDir: URL, to outputURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var zipError: (any Error)?

        coordinator.coordinate(
            readingItemAt: sourceDir,
            options: .forUploading,
            error: &coordinatorError
        ) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: outputURL)
            } catch {
                zipError = error
            }
        }

        if let error = coordinatorError { throw error }
        if let error = zipError { throw error }
    }

    // MARK: - Helpers

    private static func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
}

// MARK: - Shared String Table

private final class SharedStringTable: @unchecked Sendable {
    private var strings: [String] = []
    private var lookup: [String: Int] = [:]

    func index(for value: String) -> Int {
        if let existing = lookup[value] { return existing }
        let idx = strings.count
        strings.append(value)
        lookup[value] = idx
        return idx
    }

    func write(to dir: URL) throws {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(strings.count)" uniqueCount="\(strings.count)">
        """
        for str in strings {
            xml += "<si><t>\(xmlEscape(str))</t></si>"
        }
        xml += "</sst>"
        try xml.write(to: dir.appendingPathComponent("xl/sharedStrings.xml"), atomically: true, encoding: .utf8)
    }

    private func xmlEscape(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
           .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Sheet Builder

private final class SheetBuilder: @unchecked Sendable {
    enum CellValue {
        case string(Int)
        case number(Decimal)
    }

    private var rows: [[CellValue]] = []

    func addRow(_ cells: [CellValue]) {
        rows.append(cells)
    }

    func write(to url: URL) throws {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>
        """

        for (rowIdx, row) in rows.enumerated() {
            let rowNum = rowIdx + 1
            xml += "<row r=\"\(rowNum)\">"
            for (colIdx, cell) in row.enumerated() {
                let colRef = columnLetter(colIdx)
                let cellRef = "\(colRef)\(rowNum)"
                switch cell {
                case .string(let idx):
                    xml += "<c r=\"\(cellRef)\" t=\"s\"><v>\(idx)</v></c>"
                case .number(let value):
                    let formatted = formatDecimalForXML(value)
                    xml += "<c r=\"\(cellRef)\"><v>\(formatted)</v></c>"
                }
            }
            xml += "</row>"
        }

        xml += "</sheetData></worksheet>"
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    private func columnLetter(_ index: Int) -> String {
        var result = ""
        var n = index
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    private func formatDecimalForXML(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 10
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
}
