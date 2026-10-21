import XCTest
@testable import LotteryLedger

final class RuleEngineTests: XCTestCase {
    private func rule(_ code: String, _ name: String, _ category: RuleCategory, _ style: RuleInputStyle, _ mode: RuleMatchMode, stake: Int64 = 1_000, payout: Int64 = 10_000) -> RuleDefinitionRecord {
        RuleDefinitionRecord(
            lottery: .fucai3D,
            code: code,
            name: name,
            category: category,
            inputStyle: style,
            matchMode: mode,
            fixedStakeCents: stake,
            payoutCents: payout
        )
    }

    func testSumAndSpanBoundaries() {
        let sum = rule("sum_0", "和值0", .sum, .number, .sum, payout: 900_000)
        XCTAssertEqual(RuleEngine.settle(rule: sum, input: "0", amountCents: 1_000, draw: "000").status, .won)
        XCTAssertEqual(RuleEngine.settle(rule: sum, input: "0", amountCents: 1_000, draw: "001").status, .lost)

        let maxSum = rule("sum_27", "和值27", .sum, .number, .sum, payout: 900_000)
        XCTAssertEqual(RuleEngine.settle(rule: maxSum, input: "27", amountCents: 1_000, draw: "999").status, .won)

        let span = rule("span_9", "跨度9", .span, .number, .span, payout: 17_000)
        XCTAssertEqual(RuleEngine.settle(rule: span, input: "9", amountCents: 1_000, draw: "019").status, .won)
        XCTAssertEqual(RuleEngine.settle(rule: span, input: "9", amountCents: 1_000, draw: "123").status, .lost)
    }

    func testExactGroupsAndLeadingZero() {
        let direct = rule("straight", "直选", .direct, .exactDigits, .exact, stake: 200, payout: 180_000)
        let result = RuleEngine.settle(rule: direct, input: "012", amountCents: 400, draw: "012")
        XCTAssertEqual(result.status, .won)
        XCTAssertEqual(result.payoutCents, 360_000)

        let six = rule("six", "组六", .group, .tripleSet, .groupSix, stake: 200, payout: 30_000)
        XCTAssertEqual(RuleEngine.settle(rule: six, input: "127", amountCents: 200, draw: "721").status, .won)

        let three = rule("three", "组三", .group, .pair, .groupThree, stake: 200, payout: 60_000)
        XCTAssertEqual(RuleEngine.settle(rule: three, input: "12", amountCents: 200, draw: "211").status, .won)
        XCTAssertEqual(RuleEngine.settle(rule: three, input: "12", amountCents: 200, draw: "123").status, .lost)
    }

    func testPositionAndPools() {
        let position = rule("position_two", "两码定位", .position, .positionPair, .position, payout: 90_000)
        XCTAssertEqual(RuleEngine.settle(rule: position, input: "1:0,3:2", amountCents: 1_000, draw: "012").status, .won)

        let pool = rule("six_multi_4", "组六4码", .multi, .digitSet, .sixPool, payout: 36_000)
        XCTAssertEqual(RuleEngine.combinationCount(rule: pool, input: "0123"), 4)
        XCTAssertEqual(RuleEngine.requiredStakeCents(rule: pool, input: "0123"), 4_000)
        let result = RuleEngine.settle(rule: pool, input: "0123", amountCents: 4_000, draw: "230")
        XCTAssertEqual(result.status, .won)
        XCTAssertEqual(result.payoutCents, 36_000)

        let invalid = RuleEngine.validate(rule: pool, input: "0123", amountCents: 2_000)
        XCTAssertNotNil(invalid.error)
    }

    func testThreePoolStakeAndInvalidDraw() {
        let pool = rule("three_multi_3", "组三3码", .multi, .digitSet, .threePool, payout: 50_000)
        XCTAssertEqual(RuleEngine.combinationCount(rule: pool, input: "012"), 6)
        XCTAssertEqual(RuleEngine.requiredStakeCents(rule: pool, input: "012"), 6_000)
        XCTAssertEqual(RuleEngine.settle(rule: pool, input: "012", amountCents: 6_000, draw: "110").payoutCents, 50_000)
        XCTAssertEqual(RuleEngine.settle(rule: pool, input: "012", amountCents: 6_000, draw: "12").status, .needsReview)
    }

    func testValidationPreservesLeadingZerosAndRejectsUnicodeDigits() {
        let direct = rule("straight", "直选", .direct, .exactDigits, .exact, stake: 200, payout: 180_000)
        XCTAssertNil(RuleEngine.validate(rule: direct, input: "012", amountCents: 200).error)
        XCTAssertNotNil(RuleEngine.validate(rule: direct, input: "０１２", amountCents: 200).error)
    }

    func testDefaultRuleCatalogContainsEverySeedOnce() {
        let seeds = RuleCatalog.defaultSeeds()
        XCTAssertEqual(seeds.count, 68)
        XCTAssertEqual(Set(seeds.map(\.code)).count, 68)
        XCTAssertEqual(seeds.filter { $0.category == .sum }.count, 28)
        XCTAssertEqual(seeds.filter { $0.category == .span }.count, 10)
        XCTAssertTrue(seeds.contains { $0.code == "sum_0" && $0.payoutCents == 900_000 })
        XCTAssertTrue(seeds.contains { $0.code == "span_9" && $0.payoutCents == 17_000 })
    }
}
