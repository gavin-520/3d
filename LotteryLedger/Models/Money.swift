import Foundation

enum Money {
    static let currencySymbol = "¥"

    static func format(cents: Int64, showSign: Bool = false) -> String {
        let value = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currencySymbol
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        let result = formatter.string(from: NSNumber(value: value)) ?? "\(currencySymbol)\(value)"
        if showSign, cents > 0 { return "+\(result)" }
        return result
    }

    static func parseCents(_ text: String) -> Int64? {
        let cleaned = text
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: cleaned), decimal >= 0 else { return nil }
        var centsDecimal = decimal * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &centsDecimal, 0, .plain)
        guard rounded == centsDecimal else { return nil }
        let number = NSDecimalNumber(decimal: rounded)
        guard number.compare(NSDecimalNumber(value: Int64.max)) != .orderedDescending else { return nil }
        return number.int64Value
    }
}
