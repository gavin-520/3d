import Foundation

protocol DrawDataProvider {
    var lottery: LotteryKind { get }
    func fetchDraw(period: String?) async throws -> DrawPayload
}

struct DrawPayload: Codable, Equatable {
    var period: String
    var digits: String
    var drawDate: Date
    var source: DrawSource

    init(period: String, digits: String, drawDate: Date = .now, source: DrawSource) {
        self.period = period
        self.digits = digits
        self.drawDate = drawDate
        self.source = source
    }
}

enum DrawProviderError: LocalizedError {
    case invalidConfiguration
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "开奖接口配置不完整"
        case .invalidResponse: return "开奖接口返回格式无法识别"
        }
    }
}

struct APIProviderConfiguration: Codable, Equatable {
    var endpointTemplate: String
    var periodPath: String
    var digitsPath: String
    var datePath: String
    var headersJSON: String
    var queryJSON: String
    var token: String

    static var empty: APIProviderConfiguration {
        APIProviderConfiguration(
            endpointTemplate: "",
            periodPath: "data.period",
            digitsPath: "data.digits",
            datePath: "data.drawDate",
            headersJSON: "{}",
            queryJSON: "{}",
            token: ""
        )
    }
}

actor ConfigurableDrawProvider: DrawDataProvider {
    nonisolated let lottery: LotteryKind
    private let configuration: APIProviderConfiguration
    private let session: URLSession

    init(lottery: LotteryKind, configuration: APIProviderConfiguration, session: URLSession = .shared) {
        self.lottery = lottery
        self.configuration = configuration
        self.session = session
    }

    func fetchDraw(period: String?) async throws -> DrawPayload {
        guard !configuration.endpointTemplate.isEmpty else { throw DrawProviderError.invalidConfiguration }
        let endpoint = configuration.endpointTemplate.replacingOccurrences(of: "{period}", with: period ?? "")
        guard var components = URLComponents(string: endpoint) else { throw DrawProviderError.invalidConfiguration }

        if let queryData = configuration.queryJSON.data(using: .utf8),
           let query = try? JSONSerialization.jsonObject(with: queryData) as? [String: String], !query.isEmpty {
            let configured = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            components.queryItems = (components.queryItems ?? []) + configured
        }
        guard let url = components.url else { throw DrawProviderError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        if let data = configuration.headersJSON.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        }
        if !configuration.token.isEmpty {
            request.setValue(configuration.token, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DrawProviderError.invalidResponse
        }
        let periodValue = value(at: configuration.periodPath, in: json).map { String(describing: $0) } ?? period ?? ""
        let digitValue = normalizedDigits(value(at: configuration.digitsPath, in: json))
        guard !periodValue.isEmpty, let digitValue else {
            throw DrawProviderError.invalidResponse
        }
        let dateText = value(at: configuration.datePath, in: json).map { String(describing: $0) } ?? ""
        let date: Date
        if configuration.datePath.isEmpty {
            date = .now
        } else if let parsedDate = ISO8601DateFormatter().date(from: dateText)
                    ?? DateFormatter.isoDay.date(from: dateText) {
            date = parsedDate
        } else {
            throw DrawProviderError.invalidResponse
        }
        return DrawPayload(period: periodValue, digits: digitValue, drawDate: date, source: .api)
    }

    private func value(at path: String, in json: [String: Any]) -> Any? {
        path.split(separator: ".").reduce(json as Any?) { current, key in
            guard let dictionary = current as? [String: Any] else { return nil }
            return dictionary[String(key)]
        }
    }

    private func normalizedDigits(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count == 3,
                  trimmed.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else { return nil }
            return trimmed
        }
        if let values = value as? [Any] {
            let digits = values.compactMap { item -> Int? in
                if let number = item as? NSNumber { return number.intValue }
                if let text = item as? String { return Int(text) }
                return nil
            }
            guard digits.count == 3, digits.allSatisfy({ (0...9).contains($0) }) else { return nil }
            return digits.map(String.init).joined()
        }
        if let number = value as? NSNumber {
            let text = number.stringValue
            guard text.count == 3, text.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
            return text
        }
        return nil
    }
}

private extension DateFormatter {
    static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
