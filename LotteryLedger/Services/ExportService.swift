import Foundation
import SwiftData

struct ExportSnapshot: Codable {
    struct Draw: Codable {
        var id: UUID
        var lottery: String
        var period: String
        var digits: String
        var drawDate: Date
        var source: String
        var updatedAt: Date?
    }

    struct Bet: Codable {
        var id: UUID
        var lottery: String
        var period: String
        var betDate: Date
        var ruleCode: String
        var ruleName: String
        var ruleCategory: String
        var ruleInputStyle: String
        var ruleMatchMode: String
        var ruleInputHint: String
        var input: String
        var amountCents: Int64
        var unitStakeCents: Int64
        var unitPayoutCents: Int64
        var ruleVersion: Int
        var status: String
        var payoutCents: Int64
        var settlementDescription: String
        var createdAt: Date?
        var settledAt: Date?
    }

    struct Rule: Codable {
        var id: UUID
        var lottery: String
        var code: String
        var name: String
        var category: String
        var inputStyle: String
        var matchMode: String
        var fixedStakeCents: Int64
        var payoutCents: Int64
        var inputHint: String
        var enabled: Bool
        var version: Int
        var notes: String
    }

    var exportedAt: Date
    var draws: [Draw]
    var bets: [Bet]
    var rules: [Rule]
}

@MainActor
enum ExportService {
    static func export(context: ModelContext) -> Data {
        let draws = (try? context.fetch(FetchDescriptor<DrawRecord>())) ?? []
        let bets = (try? context.fetch(FetchDescriptor<BetRecord>())) ?? []
        let rules = (try? context.fetch(FetchDescriptor<RuleDefinitionRecord>())) ?? []
        let snapshot = ExportSnapshot(
            exportedAt: .now,
            draws: draws.map {
                .init(id: $0.id, lottery: $0.lotteryRaw, period: $0.period, digits: $0.digits, drawDate: $0.drawDate, source: $0.sourceRaw, updatedAt: $0.updatedAt)
            },
            bets: bets.map {
                .init(id: $0.id, lottery: $0.lotteryRaw, period: $0.period, betDate: $0.betDate, ruleCode: $0.ruleCode, ruleName: $0.ruleNameSnapshot, ruleCategory: $0.ruleCategoryRaw, ruleInputStyle: $0.ruleInputStyleRaw, ruleMatchMode: $0.ruleMatchModeRaw, ruleInputHint: $0.ruleInputHint, input: $0.input, amountCents: $0.amountCents, unitStakeCents: $0.unitStakeCents, unitPayoutCents: $0.unitPayoutCents, ruleVersion: $0.ruleVersion, status: $0.statusRaw, payoutCents: $0.payoutCents, settlementDescription: $0.settlementDescription, createdAt: $0.createdAt, settledAt: $0.settledAt)
            },
            rules: rules.map {
                .init(id: $0.id, lottery: $0.lotteryRaw, code: $0.code, name: $0.name, category: $0.categoryRaw, inputStyle: $0.inputStyleRaw, matchMode: $0.matchModeRaw, fixedStakeCents: $0.fixedStakeCents, payoutCents: $0.payoutCents, inputHint: $0.inputHint, enabled: $0.enabled, version: $0.version, notes: $0.notes)
            }
        )
        return (try? JSONEncoder.ledger.encode(snapshot)) ?? Data()
    }

    static func exportCSV(context: ModelContext) -> Data {
        let bets = (try? context.fetch(FetchDescriptor<BetRecord>())) ?? []
        let columns = [
            "id", "lottery", "period", "betDate", "ruleCode", "ruleName", "ruleCategory",
            "ruleInputStyle", "ruleMatchMode", "ruleInputHint", "input", "amountCents",
            "unitStakeCents", "unitPayoutCents", "ruleVersion", "status", "payoutCents",
            "settlementDescription", "createdAt", "settledAt"
        ]
        var lines = [columns.joined(separator: ",")]
        let formatter = ISO8601DateFormatter()
        for bet in bets {
            let fields = [
                bet.id.uuidString, bet.lotteryRaw, bet.period, formatter.string(from: bet.betDate),
                bet.ruleCode, bet.ruleNameSnapshot, bet.ruleCategoryRaw, bet.ruleInputStyleRaw,
                bet.ruleMatchModeRaw, bet.ruleInputHint, bet.input, String(bet.amountCents),
                String(bet.unitStakeCents), String(bet.unitPayoutCents), String(bet.ruleVersion),
                bet.statusRaw, String(bet.payoutCents), bet.settlementDescription,
                formatter.string(from: bet.createdAt), bet.settledAt.map(formatter.string(from:)) ?? ""
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        return (lines.joined(separator: "\r\n") + "\r\n").data(using: .utf8) ?? Data()
    }

    static func importData(_ data: Data, context: ModelContext) throws {
        let snapshot = try JSONDecoder.ledger.decode(ExportSnapshot.self, from: data)
        let currentRules = try context.fetch(FetchDescriptor<RuleDefinitionRecord>())
        let currentDraws = try context.fetch(FetchDescriptor<DrawRecord>())
        let currentBets = try context.fetch(FetchDescriptor<BetRecord>())
        var importedRuleKeys = Set<String>()
        var importedDrawKeys = Set(currentDraws.map { "\($0.lotteryRaw)|\($0.period)" })
        var importedDrawIDs = Set(currentDraws.map(\.id))
        var importedBetIDs = Set(currentBets.map(\.id))

        for value in snapshot.rules {
            guard let lottery = LotteryKind(rawValue: value.lottery) else { continue }
            let key = "\(lottery.rawValue)|\(value.code)"
            guard importedRuleKeys.insert(key).inserted else { continue }
            if let current = currentRules.first(where: { $0.lottery == lottery && $0.code == value.code }) {
                current.name = value.name
                current.categoryRaw = value.category
                current.inputStyleRaw = value.inputStyle
                current.matchModeRaw = value.matchMode
                current.fixedStakeCents = value.fixedStakeCents
                current.payoutCents = value.payoutCents
                current.inputHint = value.inputHint
                current.enabled = value.enabled
                current.version = value.version
                current.notes = value.notes
            } else {
                context.insert(RuleDefinitionRecord(
                    id: value.id,
                    lottery: lottery,
                    code: value.code,
                    name: value.name,
                    category: RuleCategory(rawValue: value.category) ?? .direct,
                    inputStyle: RuleInputStyle(rawValue: value.inputStyle) ?? .exactDigits,
                    matchMode: RuleMatchMode(rawValue: value.matchMode) ?? .exact,
                    fixedStakeCents: value.fixedStakeCents,
                    payoutCents: value.payoutCents,
                    inputHint: value.inputHint,
                    enabled: value.enabled,
                    version: value.version,
                    notes: value.notes
                ))
            }
        }

        for value in snapshot.draws {
            guard let lottery = LotteryKind(rawValue: value.lottery),
                  !value.period.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.digits.count == 3,
                  value.digits.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else { continue }
            if let current = currentDraws.first(where: { $0.lottery == lottery && $0.period == value.period }) {
                current.digits = value.digits
                current.drawDate = value.drawDate
                current.sourceRaw = value.source
                current.updatedAt = value.updatedAt ?? .now
            } else if importedDrawKeys.insert("\(lottery.rawValue)|\(value.period)").inserted {
                let id = importedDrawIDs.insert(value.id).inserted ? value.id : UUID()
                importedDrawIDs.insert(id)
                context.insert(DrawRecord(
                    id: id,
                    lottery: lottery,
                    period: value.period,
                    digits: value.digits,
                    drawDate: value.drawDate,
                    source: DrawSource(rawValue: value.source) ?? .imported,
                    updatedAt: value.updatedAt ?? .now
                ))
            }
        }

        for value in snapshot.bets {
            guard importedBetIDs.insert(value.id).inserted,
                  let lottery = LotteryKind(rawValue: value.lottery),
                  !value.period.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.amountCents > 0, value.unitStakeCents > 0, value.unitPayoutCents >= 0,
                  let status = BetStatus(rawValue: value.status) else { continue }
            let rule = snapshotRule(from: value, lottery: lottery)
            let record = BetRecord(
                id: value.id,
                lottery: lottery,
                period: value.period,
                betDate: value.betDate,
                rule: rule,
                input: value.input,
                amountCents: value.amountCents
            )
            record.status = status
            record.payoutCents = value.payoutCents
            record.settlementDescription = value.settlementDescription
            record.createdAt = value.createdAt ?? value.betDate
            record.settledAt = value.settledAt ?? (status == .pending ? nil : snapshot.exportedAt)
            context.insert(record)
        }
        try context.save()
        let importedDraws = try context.fetch(FetchDescriptor<DrawRecord>())
        let ledger = LedgerService(context: context)
        for draw in importedDraws {
            let hasPending = (try context.fetch(FetchDescriptor<BetRecord>()))
                .contains { $0.lottery == draw.lottery && $0.period == draw.period && $0.status == .pending }
            if hasPending {
                try ledger.settle(period: draw.period, lottery: draw.lottery, digits: draw.digits)
            }
        }
    }

    static func importCSV(_ data: Data, context: ModelContext) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw ImportError.invalidCSV }
        let rows = parseCSV(text)
        guard let header = rows.first, !header.isEmpty else { throw ImportError.invalidCSV }
        let index = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })
        let existing = try context.fetch(FetchDescriptor<BetRecord>())
        var existingIDs = Set(existing.map(\.id))
        let dateFormatter = ISO8601DateFormatter()

        for row in rows.dropFirst() {
            func value(_ key: String) -> String? {
                guard let offset = index[key], row.indices.contains(offset) else { return nil }
                return row[offset]
            }
            guard let lotteryRaw = value("lottery"),
                  let lottery = LotteryKind(rawValue: lotteryRaw),
                  let period = value("period"),
                  let dateText = value("betDate"),
                  let date = dateFormatter.date(from: dateText),
                  let ruleCode = value("ruleCode"),
                  let ruleName = value("ruleName"),
                  let input = value("input"),
                  let amount = value("amountCents").flatMap(Int64.init),
                  let unitStake = value("unitStakeCents").flatMap(Int64.init),
                  let unitPayout = value("unitPayoutCents").flatMap(Int64.init),
                  amount > 0, unitStake > 0, unitPayout >= 0 else { continue }
            let id = value("id").flatMap(UUID.init(uuidString:)) ?? UUID()
            guard existingIDs.insert(id).inserted else { continue }
            let category = value("ruleCategory") ?? RuleCategory.direct.rawValue
            let style = value("ruleInputStyle") ?? RuleInputStyle.exactDigits.rawValue
            let mode = value("ruleMatchMode") ?? RuleMatchMode.exact.rawValue
            let version = value("ruleVersion").flatMap(Int.init) ?? 1
            let rule = RuleDefinitionRecord(
                lottery: lottery,
                code: ruleCode,
                name: ruleName,
                category: RuleCategory(rawValue: category) ?? .direct,
                inputStyle: RuleInputStyle(rawValue: style) ?? .exactDigits,
                matchMode: RuleMatchMode(rawValue: mode) ?? .exact,
                fixedStakeCents: unitStake,
                payoutCents: unitPayout,
                inputHint: value("ruleInputHint") ?? "",
                version: version
            )
            let bet = BetRecord(id: id, lottery: lottery, period: period, betDate: date, rule: rule, input: input, amountCents: amount)
            let status = value("status").flatMap(BetStatus.init(rawValue:)) ?? .pending
            bet.status = status
            bet.payoutCents = value("payoutCents").flatMap(Int64.init) ?? 0
            bet.settlementDescription = value("settlementDescription") ?? ""
            bet.createdAt = value("createdAt").flatMap(dateFormatter.date(from:)) ?? date
            bet.settledAt = value("settledAt").flatMap(dateFormatter.date(from:))
            context.insert(bet)
        }
        try context.save()
    }

    private static func snapshotRule(from value: ExportSnapshot.Bet, lottery: LotteryKind) -> RuleDefinitionRecord {
        RuleDefinitionRecord(
            lottery: lottery,
            code: value.ruleCode,
            name: value.ruleName,
            category: RuleCategory(rawValue: value.ruleCategory) ?? .direct,
            inputStyle: RuleInputStyle(rawValue: value.ruleInputStyle) ?? .exactDigits,
            matchMode: RuleMatchMode(rawValue: value.ruleMatchMode) ?? .exact,
            fixedStakeCents: value.unitStakeCents,
            payoutCents: value.unitPayoutCents,
            inputHint: value.ruleInputHint,
            version: value.ruleVersion
        )
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r" {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
                row.append(field)
                field = ""
                if !row.allSatisfy(\.isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    enum ImportError: LocalizedError {
        case invalidCSV
        var errorDescription: String? { "CSV 文件格式无效" }
    }
}

private extension JSONEncoder {
    static let ledger: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let ledger: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
