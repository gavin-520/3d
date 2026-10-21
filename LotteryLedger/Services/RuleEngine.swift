import Foundation

struct RuleValidation {
    let normalizedInput: String
    let error: String?
}

enum RuleEngine {
    static func combinationCount(rule: RuleDefinitionRecord, input: String) -> Int {
        let selected = digitSetValues(input)
        switch rule.matchMode {
        case .sixPool:
            return choose(selected.count, 3)
        case .threePool:
            return choose(selected.count, 2) * 2
        case .complexPool:
            guard selected.count > 0 else { return 0 }
            return selected.count * selected.count * selected.count
        default:
            return 1
        }
    }

    static func requiredStakeCents(rule: RuleDefinitionRecord, input: String) -> Int64 {
        let count = max(1, combinationCount(rule: rule, input: input))
        let (amount, overflow) = rule.fixedStakeCents.multipliedReportingOverflow(by: Int64(count))
        return overflow ? Int64.max : amount
    }

    static func validate(rule: RuleDefinitionRecord, input: String, amountCents: Int64) -> RuleValidation {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amountCents > 0 else {
            return RuleValidation(normalizedInput: cleaned, error: "投注金额必须大于 0")
        }
        guard rule.fixedStakeCents > 0 else {
            return RuleValidation(normalizedInput: cleaned, error: "玩法单注本金必须大于 0")
        }

        if rule.matchMode == .sum || rule.matchMode == .span {
            let target = rule.code.split(separator: "_").last.flatMap { Int($0) }
            guard target != nil else { return RuleValidation(normalizedInput: cleaned, error: "玩法规则缺少目标值") }
            let unitStake = requiredStakeCents(rule: rule, input: "")
            guard amountCents % unitStake == 0 else {
                return RuleValidation(normalizedInput: String(target!), error: "投注金额必须是 \(Money.format(cents: unitStake)) 的整数倍")
            }
            return RuleValidation(normalizedInput: String(target!), error: nil)
        }

        guard !cleaned.isEmpty else {
            return RuleValidation(normalizedInput: cleaned, error: "请输入投注内容")
        }

        switch rule.inputStyle {
        case .number:
            let maxValue = rule.matchMode == .singleDigit ? 9 : 27
            guard isASCIIDigits(cleaned), let value = Int(cleaned), (0...maxValue).contains(value) else {
                return RuleValidation(normalizedInput: cleaned, error: "请输入 0 到 \(maxValue) 的整数")
            }
        case .exactDigits:
            guard cleaned.count == 3, isASCIIDigits(cleaned) else {
                return RuleValidation(normalizedInput: cleaned, error: "请输入一个三位号码，例如 012")
            }
        case .pair:
            guard isASCIIDigits(cleaned), digitSetValues(cleaned).count == 2, cleaned.count == 2 else {
                return RuleValidation(normalizedInput: cleaned, error: "请输入两个不同数字")
            }
        case .tripleSet:
            guard isASCIIDigits(cleaned), digitSetValues(cleaned).count == 3, cleaned.count == 3 else {
                return RuleValidation(normalizedInput: cleaned, error: "请输入三个不同数字")
            }
        case .digitSet:
            let compact = cleaned.filter { !$0.isWhitespace && $0 != "," && $0 != "，" }
            let selected = digitSetValues(compact)
            let expected = expectedDigitSetCount(for: rule.code)
            guard selected.count >= 2,
                  isASCIIDigits(compact), selected.count == compact.count,
                  expected.map({ selected.count == $0 }) ?? true else {
                let suffix = expected.map { "，需要恰好 \($0) 个" } ?? ""
                return RuleValidation(normalizedInput: cleaned, error: "请输入不重复的数字集合\(suffix)")
            }
        case .positionDigit:
            guard let pairs = parsePositionPairs(cleaned), pairs.count == 1 else {
                return RuleValidation(normalizedInput: cleaned, error: "请输入一个位置:数字，例如 1:7")
            }
        case .positionPair:
            guard let pairs = parsePositionPairs(cleaned), pairs.count == 2, Set(pairs.map { $0.0 }).count == 2 else {
                return RuleValidation(normalizedInput: cleaned, error: "请输入两个不同位置，例如 1:7,3:2")
            }
        }

        let unitStake = requiredStakeCents(rule: rule, input: cleaned)
        guard unitStake > 0, amountCents % unitStake == 0 else {
            return RuleValidation(normalizedInput: cleaned, error: "该投注展开为 \(combinationCount(rule: rule, input: cleaned)) 注，金额必须是 \(Money.format(cents: unitStake)) 的整数倍")
        }

        return RuleValidation(normalizedInput: cleaned, error: nil)
    }

    static func settle(rule: RuleDefinitionRecord, input: String, amountCents: Int64, draw: String) -> SettlementResult {
        let validation = validate(rule: rule, input: input, amountCents: amountCents)
        guard validation.error == nil else {
            return SettlementResult(status: .needsReview, payoutCents: 0, hitDescription: validation.error ?? "投注内容无效")
        }
        guard let digits = asciiDigitValues(draw), digits.count == 3 else {
            return SettlementResult(status: .needsReview, payoutCents: 0, hitDescription: "开奖号码必须是三位数字")
        }

        let selectedInput = validation.normalizedInput
        let drawn = Set(digits)
        let hits: Int
        switch rule.matchMode {
        case .sum:
            let target = Int(selectedInput) ?? -1
            hits = digits.reduce(0, +) == target ? 1 : 0
        case .span:
            let target = Int(selectedInput) ?? -1
            hits = digits.max()! - digits.min()! == target ? 1 : 0
        case .singleDigit:
            guard let digit = selectedInput.first?.wholeNumberValue else {
                return SettlementResult(status: .needsReview, payoutCents: 0, hitDescription: "独胆投注内容无效")
            }
            hits = digits.contains(digit) ? 1 : 0
        case .exact:
            hits = digits.map(String.init).joined() == selectedInput ? 1 : 0
        case .groupSix:
            hits = drawn.count == 3 && drawn == digitSetValues(selectedInput) ? 1 : 0
        case .groupThree:
            hits = drawn.count == 2 && drawn == digitSetValues(selectedInput) ? 1 : 0
        case .containsSelected:
            let selected = digitSetValues(selectedInput)
            hits = selected.count > 0 && selected.isSubset(of: drawn) ? 1 : 0
        case .position:
            let pairs = parsePositionPairs(selectedInput) ?? []
            hits = pairs.allSatisfy { position, digit in
                (1...3).contains(position) && digits[position - 1] == digit
            } ? 1 : 0
        case .sixPool:
            let selected = digitSetValues(selectedInput)
            hits = drawn.count == 3 && drawn.isSubset(of: selected) ? 1 : 0
        case .threePool:
            let selected = digitSetValues(selectedInput)
            hits = drawn.count == 2 && drawn.isSubset(of: selected) ? 1 : 0
        case .complexPool:
            let selected = digitSetValues(selectedInput)
            hits = drawn.allSatisfy(selected.contains) ? 1 : 0
        }

        let unitStake = requiredStakeCents(rule: rule, input: selectedInput)
        let units = unitStake > 0 ? amountCents / unitStake : 0
        let (perUnitPayout, payoutOverflow1) = rule.payoutCents.multipliedReportingOverflow(by: Int64(hits))
        let (payout, payoutOverflow2) = perUnitPayout.multipliedReportingOverflow(by: units)
        if payoutOverflow1 || payoutOverflow2 {
            return SettlementResult(status: .needsReview, payoutCents: 0, hitDescription: "结算金额超出可计算范围，请检查规则金额")
        }
        return SettlementResult(
            status: hits > 0 ? .won : .lost,
            payoutCents: payout,
            hitDescription: hits > 0 ? "命中 \(hits) 注组合，倍数 \(units)" : "未命中"
        )
    }

    private static func digitSetValues(_ input: String) -> Set<Int> {
        Set(input.unicodeScalars.compactMap { scalar -> Int? in
            guard scalar.value >= 48 && scalar.value <= 57 else { return nil }
            return Int(scalar.value - 48)
        })
    }

    private static func isASCIIDigits(_ input: String) -> Bool {
        !input.isEmpty && input.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }

    private static func asciiDigitValues(_ input: String) -> [Int]? {
        guard isASCIIDigits(input) else { return nil }
        return input.unicodeScalars.map { Int($0.value - 48) }
    }

    private static func choose(_ n: Int, _ k: Int) -> Int {
        guard n >= k, k >= 0 else { return 0 }
        if k == 0 { return 1 }
        return (0..<k).reduce(1) { value, index in value * (n - index) / (index + 1) }
    }

    private static func expectedDigitSetCount(for code: String) -> Int? {
        if code.hasSuffix("_all") { return 10 }
        guard let suffix = code.split(separator: "_").last,
              let value = Int(suffix), code.contains("multi") else { return nil }
        return value
    }

    private static func parsePositionPairs(_ input: String) -> [(Int, Int)]? {
        let tokens = input.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" || $0.isWhitespace })
        var pairs: [(Int, Int)] = []
        for token in tokens {
            let parts = token.split(whereSeparator: { $0 == ":" || $0 == "：" })
            guard parts.count == 2,
                  isASCIIDigits(String(parts[0])), isASCIIDigits(String(parts[1])),
                  let position = Int(parts[0]), (1...3).contains(position),
                  let digit = Int(parts[1]), (0...9).contains(digit) else { return nil }
            pairs.append((position, digit))
        }
        return pairs
    }
}
