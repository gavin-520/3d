import SwiftUI
import SwiftData

@main
struct LotteryLedgerApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: DrawRecord.self,
                BetRecord.self,
                RuleDefinitionRecord.self
            )
        } catch {
            fatalError("无法创建本地数据容器：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    RuleCatalog.seedIfNeeded(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
