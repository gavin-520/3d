import Foundation
import SwiftData

@Model
final class DrawRecord {
    @Attribute(.unique) var id: UUID
    var lotteryRaw: String
    var period: String
    var digits: String
    var drawDate: Date
    var sourceRaw: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        lottery: LotteryKind,
        period: String,
        digits: String,
        drawDate: Date = .now,
        source: DrawSource = .manual,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.lotteryRaw = lottery.rawValue
        self.period = period
        self.digits = digits
        self.drawDate = drawDate
        self.sourceRaw = source.rawValue
        self.updatedAt = updatedAt
    }

    var lottery: LotteryKind {
        LotteryKind(rawValue: lotteryRaw) ?? .fucai3D
    }

    var source: DrawSource {
        DrawSource(rawValue: sourceRaw) ?? .manual
    }
}

@Model
final class RuleDefinitionRecord {
    @Attribute(.unique) var id: UUID
    var lotteryRaw: String
    var code: String
    var name: String
    var categoryRaw: String
    var inputStyleRaw: String
    var matchModeRaw: String
    var fixedStakeCents: Int64
    var payoutCents: Int64
    var inputHint: String
    var enabled: Bool
    var version: Int
    var notes: String

    init(
        id: UUID = UUID(),
        lottery: LotteryKind,
        code: String,
        name: String,
        category: RuleCategory,
        inputStyle: RuleInputStyle,
        matchMode: RuleMatchMode,
        fixedStakeCents: Int64,
        payoutCents: Int64,
        inputHint: String = "",
        enabled: Bool = true,
        version: Int = 1,
        notes: String = ""
    ) {
        self.id = id
        self.lotteryRaw = lottery.rawValue
        self.code = code
        self.name = name
        self.categoryRaw = category.rawValue
        self.inputStyleRaw = inputStyle.rawValue
        self.matchModeRaw = matchMode.rawValue
        self.fixedStakeCents = fixedStakeCents
        self.payoutCents = payoutCents
        self.inputHint = inputHint
        self.enabled = enabled
        self.version = version
        self.notes = notes
    }

    var lottery: LotteryKind {
        LotteryKind(rawValue: lotteryRaw) ?? .fucai3D
    }

    var category: RuleCategory {
        RuleCategory(rawValue: categoryRaw) ?? .direct
    }

    var inputStyle: RuleInputStyle {
        RuleInputStyle(rawValue: inputStyleRaw) ?? .exactDigits
    }

    var matchMode: RuleMatchMode {
        get { RuleMatchMode(rawValue: matchModeRaw) ?? .exact }
        set { matchModeRaw = newValue.rawValue }
    }
}

@Model
final class BetRecord {
    @Attribute(.unique) var id: UUID
    var lotteryRaw: String
    var period: String
    var betDate: Date
    var ruleCode: String
    var ruleNameSnapshot: String
    var ruleCategoryRaw: String
    var ruleInputStyleRaw: String
    var ruleMatchModeRaw: String
    var ruleInputHint: String
    var input: String
    var amountCents: Int64
    var unitStakeCents: Int64
    var unitPayoutCents: Int64
    var ruleVersion: Int
    var statusRaw: String
    var payoutCents: Int64
    var settlementDescription: String
    var settledAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        lottery: LotteryKind,
        period: String,
        betDate: Date = .now,
        rule: RuleDefinitionRecord,
        input: String,
        amountCents: Int64
    ) {
        self.id = id
        self.lotteryRaw = lottery.rawValue
        self.period = period
        self.betDate = betDate
        self.ruleCode = rule.code
        self.ruleNameSnapshot = rule.name
        self.ruleCategoryRaw = rule.categoryRaw
        self.ruleInputStyleRaw = rule.inputStyleRaw
        self.ruleMatchModeRaw = rule.matchModeRaw
        self.ruleInputHint = rule.inputHint
        self.input = input
        self.amountCents = amountCents
        self.unitStakeCents = rule.fixedStakeCents
        self.unitPayoutCents = rule.payoutCents
        self.ruleVersion = rule.version
        self.statusRaw = BetStatus.pending.rawValue
        self.payoutCents = 0
        self.settlementDescription = ""
        self.settledAt = nil
        self.createdAt = .now
    }

    var lottery: LotteryKind {
        LotteryKind(rawValue: lotteryRaw) ?? .fucai3D
    }

    var status: BetStatus {
        get { BetStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var profitCents: Int64 {
        payoutCents - amountCents
    }
}

struct SettlementResult: Codable, Equatable {
    var status: BetStatus
    var payoutCents: Int64
    var hitDescription: String
}

struct PeriodSummary: Identifiable, Equatable {
    let id: String
    let label: String
    let betCents: Int64
    let payoutCents: Int64
    let pendingCents: Int64

    var profitCents: Int64 { payoutCents - betCents }
}
