import Foundation
import SwiftData

struct RuleSeed: Identifiable {
    let id: String
    let code: String
    let name: String
    let category: RuleCategory
    let inputStyle: RuleInputStyle
    let matchMode: RuleMatchMode
    let fixedStakeCents: Int64
    let payoutCents: Int64
    let inputHint: String
    let notes: String

    init(
        code: String,
        name: String,
        category: RuleCategory,
        inputStyle: RuleInputStyle,
        matchMode: RuleMatchMode,
        fixedStakeYuan: Int64,
        payoutYuan: Int64,
        inputHint: String = "",
        notes: String = ""
    ) {
        self.id = code
        self.code = code
        self.name = name
        self.category = category
        self.inputStyle = inputStyle
        self.matchMode = matchMode
        self.fixedStakeCents = fixedStakeYuan * 100
        self.payoutCents = payoutYuan * 100
        self.inputHint = inputHint.isEmpty ? inputStyle.hint : inputHint
        self.notes = notes
    }
}

enum RuleCatalog {
    static func defaultSeeds() -> [RuleSeed] {
        var seeds: [RuleSeed] = []

        let sums = [9000, 3000, 1500, 900, 600, 430, 320, 250, 200, 160, 140, 130, 120, 120, 120, 120, 130, 140, 160, 200, 250, 320, 430, 600, 900, 1500, 3000, 9000]
        for (value, payout) in sums.enumerated() {
            seeds.append(RuleSeed(
                code: "sum_\(value)",
                name: "和值\(value)",
                category: .sum,
                inputStyle: .number,
                matchMode: .sum,
                fixedStakeYuan: 10,
                payoutYuan: Int64(payout),
                notes: "三位号码数字之和等于 \(value)"
            ))
        }

        let spans: [Int64] = [900, 160, 93, 72, 63, 58, 63, 72, 93, 170]
        for (value, payout) in spans.enumerated() {
            seeds.append(RuleSeed(
                code: "span_\(value)",
                name: "跨度\(value)",
                category: .span,
                inputStyle: .number,
                matchMode: .span,
                fixedStakeYuan: 10,
                 payoutYuan: payout,
                notes: "开奖号码最大值减最小值等于 \(value)"
            ))
        }

        seeds += [
            RuleSeed(code: "single", name: "独胆", category: .digit, inputStyle: .number, matchMode: .singleDigit, fixedStakeYuan: 10, payoutYuan: 34, inputHint: "输入一个数字，例如 7"),
            RuleSeed(code: "straight", name: "直选", category: .direct, inputStyle: .exactDigits, matchMode: .exact, fixedStakeYuan: 2, payoutYuan: 1800),
            RuleSeed(code: "six", name: "组六", category: .group, inputStyle: .tripleSet, matchMode: .groupSix, fixedStakeYuan: 2, payoutYuan: 300, inputHint: "输入三个不同数字，例如 127"),
            RuleSeed(code: "three", name: "组三", category: .group, inputStyle: .pair, matchMode: .groupThree, fixedStakeYuan: 2, payoutYuan: 600, inputHint: "输入两个不同数字，例如 12"),
            RuleSeed(code: "double_fly", name: "双飞", category: .digit, inputStyle: .pair, matchMode: .containsSelected, fixedStakeYuan: 10, payoutYuan: 160, inputHint: "输入两个不同数字，例如 12"),
            RuleSeed(code: "position_one", name: "一码定位", category: .position, inputStyle: .positionDigit, matchMode: .position, fixedStakeYuan: 10, payoutYuan: 90),
            RuleSeed(code: "position_two", name: "两码定位", category: .position, inputStyle: .positionPair, matchMode: .position, fixedStakeYuan: 10, payoutYuan: 900)
        ]

        let sixMultiples: [(Int, Int)] = [(4, 360), (5, 150), (6, 75), (7, 43), (8, 27), (9, 18)]
        for (count, payout) in sixMultiples {
            seeds.append(RuleSeed(
                code: "six_multi_\(count)",
                name: "组六\(count)码",
                category: .multi,
                inputStyle: .digitSet,
                matchMode: .sixPool,
                fixedStakeYuan: 10,
                payoutYuan: Int64(payout),
                inputHint: "输入 \(count) 个不同数字，例如 0123"
            ))
        }
        seeds.append(RuleSeed(code: "six_multi_all", name: "组六全包", category: .multi, inputStyle: .digitSet, matchMode: .sixPool, fixedStakeYuan: 10, payoutYuan: 12, inputHint: "输入 0-9 全部数字"))

        let threeMultiples: [(Int, Int)] = [(2, 1500), (3, 500), (4, 250), (5, 150), (6, 102), (7, 72), (8, 53), (9, 42)]
        for (count, payout) in threeMultiples {
            seeds.append(RuleSeed(
                code: "three_multi_\(count)",
                name: "组三\(count)码",
                category: .multi,
                inputStyle: .digitSet,
                matchMode: .threePool,
                fixedStakeYuan: 10,
                payoutYuan: Int64(payout),
                inputHint: "输入 \(count) 个不同数字"
            ))
        }
        seeds.append(RuleSeed(code: "three_multi_all", name: "组三全包", category: .multi, inputStyle: .digitSet, matchMode: .threePool, fixedStakeYuan: 10, payoutYuan: 33, inputHint: "输入 0-9 全部数字"))

        let complexMultiples: [(Int, Int)] = [(3, 330), (4, 140), (5, 72), (6, 41), (7, 25), (8, 17), (9, 12)]
        for (count, payout) in complexMultiples {
            seeds.append(RuleSeed(
                code: "complex_multi_\(count)",
                name: "复试\(count)码",
                category: .multi,
                inputStyle: .digitSet,
                matchMode: .complexPool,
                fixedStakeYuan: 10,
                payoutYuan: Int64(payout),
                inputHint: "输入 \(count) 个不同数字"
            ))
        }

        return seeds
    }

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<RuleDefinitionRecord>())) ?? []
        let existingKeys = Set(existing.map { "\($0.lotteryRaw)|\($0.code)" })
        for lottery in LotteryKind.allCases {
            for seed in defaultSeeds() where !existingKeys.contains("\(lottery.rawValue)|\(seed.code)") {
                context.insert(RuleDefinitionRecord(
                    lottery: lottery,
                    code: seed.code,
                    name: seed.name,
                    category: seed.category,
                    inputStyle: seed.inputStyle,
                    matchMode: seed.matchMode,
                    fixedStakeCents: seed.fixedStakeCents,
                    payoutCents: seed.payoutCents,
                    inputHint: seed.inputHint,
                    notes: seed.notes
                ))
            }
        }
        try? context.save()
    }

    @MainActor
    static func restoreDefaults(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<RuleDefinitionRecord>())) ?? []
        existing.forEach(context.delete)
        for lottery in LotteryKind.allCases {
            for seed in defaultSeeds() {
                context.insert(RuleDefinitionRecord(
                    lottery: lottery,
                    code: seed.code,
                    name: seed.name,
                    category: seed.category,
                    inputStyle: seed.inputStyle,
                    matchMode: seed.matchMode,
                    fixedStakeCents: seed.fixedStakeCents,
                    payoutCents: seed.payoutCents,
                    inputHint: seed.inputHint,
                    notes: seed.notes
                ))
            }
        }
        try? context.save()
    }
}
