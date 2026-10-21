import Foundation
import SwiftData

@MainActor
final class LedgerService {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func addBet(lottery: LotteryKind, period: String, rule: RuleDefinitionRecord, input: String, amountCents: Int64, date: Date = .now) throws {
        let normalizedPeriod = period.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPeriod.isEmpty else {
            throw LedgerServiceError.validation("期号不能为空")
        }
        let validation = RuleEngine.validate(rule: rule, input: input, amountCents: amountCents)
        guard validation.error == nil else {
            throw LedgerServiceError.validation(validation.error ?? "投注内容无效")
        }
        let bet = BetRecord(
            lottery: lottery,
            period: normalizedPeriod,
            betDate: date,
            rule: rule,
            input: validation.normalizedInput,
            amountCents: amountCents
        )
        context.insert(bet)
        try context.save()
    }

    func upsertDraw(_ payload: DrawPayload, lottery: LotteryKind) throws {
        let records = try context.fetch(FetchDescriptor<DrawRecord>())
        if let existing = records.first(where: { $0.lottery == lottery && $0.period == payload.period }) {
            existing.digits = payload.digits
            existing.drawDate = payload.drawDate
            existing.sourceRaw = payload.source.rawValue
            existing.updatedAt = .now
        } else {
            context.insert(DrawRecord(
                lottery: lottery,
                period: payload.period,
                digits: payload.digits,
                drawDate: payload.drawDate,
                source: payload.source
            ))
        }
        try context.save()
        try settle(period: payload.period, lottery: lottery, digits: payload.digits)
    }

    func updateDraw(_ record: DrawRecord, with payload: DrawPayload, lottery: LotteryKind) throws {
        record.lotteryRaw = lottery.rawValue
        record.period = payload.period
        record.digits = payload.digits
        record.drawDate = payload.drawDate
        record.sourceRaw = payload.source.rawValue
        record.updatedAt = .now
        try context.save()
        try settle(period: payload.period, lottery: lottery, digits: payload.digits)
    }

    func settle(period: String, lottery: LotteryKind, digits: String) throws {
        let draws = try context.fetch(FetchDescriptor<DrawRecord>())
        guard draws.contains(where: { $0.lottery == lottery && $0.period == period }) else {
            throw LedgerServiceError.drawNotFound
        }
        let bets = try context.fetch(FetchDescriptor<BetRecord>())
            .filter { $0.lottery == lottery && $0.period == period }
        for bet in bets {
            let rule = RuleDefinitionRecord(
                lottery: bet.lottery,
                code: bet.ruleCode,
                name: bet.ruleNameSnapshot,
                category: RuleCategory(rawValue: bet.ruleCategoryRaw) ?? .direct,
                inputStyle: RuleInputStyle(rawValue: bet.ruleInputStyleRaw) ?? .exactDigits,
                matchMode: RuleMatchMode(rawValue: bet.ruleMatchModeRaw) ?? .exact,
                fixedStakeCents: bet.unitStakeCents,
                payoutCents: bet.unitPayoutCents,
                inputHint: bet.ruleInputHint,
                version: bet.ruleVersion
            )
            let result = RuleEngine.settle(rule: rule, input: bet.input, amountCents: bet.amountCents, draw: digits)
            bet.status = result.status
            bet.payoutCents = result.payoutCents
            bet.settlementDescription = result.hitDescription
            bet.settledAt = .now
        }
        try context.save()
    }

    func settleBet(_ bet: BetRecord) throws {
        guard let draw = try context.fetch(FetchDescriptor<DrawRecord>())
            .first(where: { $0.lottery == bet.lottery && $0.period == bet.period }) else {
            throw LedgerServiceError.drawNotFound
        }
        try settle(period: draw.period, lottery: draw.lottery, digits: draw.digits)
    }

    func summaries(lottery: LotteryKind? = nil, from start: Date? = nil, to end: Date? = nil) throws -> [PeriodSummary] {
        var bets = try context.fetch(FetchDescriptor<BetRecord>())
        if let lottery { bets = bets.filter { $0.lottery == lottery } }
        if let start { bets = bets.filter { $0.betDate >= start } }
        if let end { bets = bets.filter { $0.betDate <= end } }
        let grouped = Dictionary(grouping: bets) { "\($0.lotteryRaw)|\($0.period)" }
        return grouped.map { key, values in
            PeriodSummary(
                id: key,
                label: "\(values[0].lottery.displayName) · \(values[0].period)",
                betCents: values.reduce(0) { $0 + $1.amountCents },
                payoutCents: values.reduce(0) { $0 + $1.payoutCents },
                pendingCents: values.filter { $0.status == .pending }.reduce(0) { $0 + $1.amountCents }
            )
        }.sorted { $0.label > $1.label }
    }
}

enum LedgerServiceError: LocalizedError {
    case validation(String)
    case drawNotFound

    var errorDescription: String? {
        switch self {
        case .validation(let message): return message
        case .drawNotFound: return "找不到对应开奖记录"
        }
    }
}
