import Foundation

enum LotteryKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case fucai3D = "fucai3D"
    case pl3 = "pl3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fucai3D: return "福彩3D"
        case .pl3: return "排列3"
        }
    }
}

enum BetStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case pending
    case won
    case lost
    case needsReview

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending: return "待开奖"
        case .won: return "已中奖"
        case .lost: return "未中奖"
        case .needsReview: return "待复核"
        }
    }
}

enum RuleCategory: String, Codable, CaseIterable, Hashable {
    case sum
    case span
    case direct
    case group
    case position
    case digit
    case multi
}

enum RuleInputStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case number
    case exactDigits
    case pair
    case tripleSet
    case digitSet
    case positionDigit
    case positionPair

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .number: return "数字"
        case .exactDigits: return "三位直选号码"
        case .pair: return "两位选码"
        case .tripleSet: return "三位组选号码"
        case .digitSet: return "不重复数字集合"
        case .positionDigit: return "单位置号码"
        case .positionPair: return "双位置号码"
        }
    }

    var hint: String {
        switch self {
        case .number: return "输入数字"
        case .exactDigits: return "输入3位号码，例如 012"
        case .pair: return "输入两个不同数字，例如 12"
        case .tripleSet: return "输入三个不同数字，例如 127"
        case .digitSet: return "输入选号集合，例如 012345"
        case .positionDigit: return "输入位置:数字，例如 1:7"
        case .positionPair: return "输入两组位置:数字，例如 1:7,3:2"
        }
    }
}

enum RuleMatchMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case sum
    case span
    case singleDigit
    case exact
    case groupSix
    case groupThree
    case containsSelected
    case position
    case sixPool
    case threePool
    case complexPool

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sum: return "和值相等"
        case .span: return "跨度相等"
        case .singleDigit: return "任一位置包含所选数字"
        case .exact: return "三位顺序完全一致"
        case .groupSix: return "组六：三位各不相同且号码相同"
        case .groupThree: return "组三：恰有一对且号码相同"
        case .containsSelected: return "开奖号码包含全部所选数字"
        case .position: return "指定位置逐位匹配"
        case .sixPool: return "组六复式：三位互异且都在选号集合"
        case .threePool: return "组三复式：恰有一对且数字都在选号集合"
        case .complexPool: return "复式：开奖号码数字均在选号集合"
        }
    }
}

enum DrawSource: String, Codable, Hashable {
    case api
    case manual
    case imported

    var displayName: String {
        switch self {
        case .api: return "接口"
        case .manual: return "手动"
        case .imported: return "导入"
        }
    }
}
