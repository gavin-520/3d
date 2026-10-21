import Foundation
import SwiftData

@MainActor
enum ProviderSettingsStore {
    static func configuration(for lottery: LotteryKind) -> APIProviderConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key(for: lottery)),
              let value = try? JSONDecoder().decode(APIProviderConfiguration.self, from: data) else {
            return .empty
        }
        return value
    }

    static func save(_ configuration: APIProviderConfiguration, for lottery: LotteryKind, token: String) {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: key(for: lottery))
        }
        SecureTokenStore.set(token, for: lottery)
    }

    static func provider(for lottery: LotteryKind) -> ConfigurableDrawProvider {
        var configuration = configuration(for: lottery)
        configuration.token = SecureTokenStore.get(for: lottery)
        return ConfigurableDrawProvider(lottery: lottery, configuration: configuration)
    }

    private static func key(for lottery: LotteryKind) -> String {
        "draw-provider-config-\(lottery.rawValue)"
    }
}

@MainActor
enum DrawRefreshService {
    static func refreshPending(context: ModelContext) async -> [String] {
        let pendingBets = ((try? context.fetch(FetchDescriptor<BetRecord>())) ?? [])
            .filter { $0.status == .pending }
        let uniquePairs = Set(pendingBets.map { "\($0.lotteryRaw)|\($0.period)" })
        var messages: [String] = []
        for key in uniquePairs {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let lottery = LotteryKind(rawValue: parts[0]),
                  !ProviderSettingsStore.configuration(for: lottery).endpointTemplate.isEmpty else { continue }
            do {
                let payload = try await ProviderSettingsStore.provider(for: lottery).fetchDraw(period: parts[1])
                try LedgerService(context: context).upsertDraw(payload, lottery: lottery)
                messages.append("\(lottery.displayName) \(payload.period)：已更新")
            } catch {
                messages.append("\(lottery.displayName) \(parts[1])：\(error.localizedDescription)")
            }
        }
        return messages
    }
}
