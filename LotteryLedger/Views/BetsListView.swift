import SwiftUI
import SwiftData

private enum BetGrouping: String, CaseIterable, Identifiable, Hashable {
    case date = "按日期"
    case period = "按期号"

    var id: String { rawValue }
}

struct BetsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BetRecord.betDate, order: .reverse) private var bets: [BetRecord]
    @State private var searchText = ""
    @State private var statusFilter: BetStatus?
    @State private var lotteryFilter: LotteryKind?
    @State private var dateFilterEnabled = false
    @State private var filterStartDate = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var filterEndDate = Date.now
    @State private var showingFilters = false
    @State private var showingAdd = false
    @State private var selectedBet: BetRecord?
    @State private var grouping: BetGrouping = .date

    private var filteredBets: [BetRecord] {
        bets.filter { bet in
            (statusFilter.map { bet.status == $0 } ?? true) &&
            (lotteryFilter.map { bet.lottery == $0 } ?? true) &&
            (!dateFilterEnabled || (bet.betDate >= Calendar.current.startOfDay(for: filterStartDate) && bet.betDate < (Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: filterEndDate)) ?? filterEndDate))) &&
            (searchText.isEmpty || bet.period.localizedCaseInsensitiveContains(searchText) || bet.ruleNameSnapshot.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var groupedBets: [BetGroup] {
        let groups = Dictionary(grouping: filteredBets) { bet in
            switch grouping {
            case .date:
                return "date|\(Calendar.current.startOfDay(for: bet.betDate).timeIntervalSince1970)"
            case .period:
                return "period|\(bet.lotteryRaw)|\(bet.period)"
            }
        }
        return groups.map { key, bets in
            let label: String
            switch grouping {
            case .date:
                label = bets.first?.betDate.formatted(date: .abbreviated, time: .omitted) ?? key
            case .period:
                label = bets.first.map { "\($0.lottery.displayName) · \($0.period)" } ?? key
            }
            return BetGroup(id: key, label: label, bets: bets.sorted { $0.betDate > $1.betDate })
        }
        .sorted { lhs, rhs in
            (lhs.bets.first?.betDate ?? .distantPast) > (rhs.bets.first?.betDate ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredBets.isEmpty {
                    ContentUnavailableView("没有匹配的投注", systemImage: "magnifyingglass", description: Text("调整筛选条件或新增一笔投注"))
                } else {
                    ForEach(groupedBets) { group in
                        Section(group.label) {
                            ForEach(group.bets) { bet in
                                Button {
                                    selectedBet = bet
                                } label: {
                                    BetRow(bet: bet)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                offsets.map { group.bets[$0] }.forEach(modelContext.delete)
                                try? modelContext.save()
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索期号或玩法")
            .navigationTitle("投注记录")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingFilters = true } label: {
                        Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("分组方式", selection: $grouping) {
                            ForEach(BetGrouping.allCases) { value in
                                Text(value.rawValue).tag(value)
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.3.group")
                    }
                    .accessibilityLabel("选择分组方式")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新增投注")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddBetView()
            }
            .sheet(isPresented: $showingFilters) {
                BetFilterSheet(
                    status: $statusFilter,
                    lottery: $lotteryFilter,
                    dateEnabled: $dateFilterEnabled,
                    startDate: $filterStartDate,
                    endDate: $filterEndDate
                )
            }
            .sheet(item: $selectedBet) { bet in
                BetDetailView(bet: bet)
            }
        }
    }
}

private struct BetGroup: Identifiable {
    let id: String
    let label: String
    let bets: [BetRecord]
}

private struct BetFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var status: BetStatus?
    @Binding var lottery: LotteryKind?
    @Binding var dateEnabled: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date

    var body: some View {
        NavigationStack {
            Form {
                Picker("状态", selection: $status) {
                    Text("全部状态").tag(BetStatus?.none)
                    ForEach(BetStatus.allCases) { value in Text(value.displayName).tag(BetStatus?.some(value)) }
                }
                Picker("彩种", selection: $lottery) {
                    Text("全部彩种").tag(LotteryKind?.none)
                    ForEach(LotteryKind.allCases) { value in Text(value.displayName).tag(LotteryKind?.some(value)) }
                }
                Toggle("按日期范围", isOn: $dateEnabled)
                if dateEnabled {
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                }
            }
            .navigationTitle("筛选投注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        status = nil
                        lottery = nil
                        dateEnabled = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}

private struct BetRow: View {
    let bet: BetRecord

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(bet.lottery.displayName) · \(bet.period)")
                    .font(.headline)
                Text("\(bet.ruleNameSnapshot)  \(bet.input)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.format(cents: bet.amountCents))
                    .font(.subheadline)
                Text(bet.status.displayName)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                if bet.payoutCents > 0 {
                    Text(Money.format(cents: bet.payoutCents))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch bet.status {
        case .pending: return .orange
        case .won: return .green
        case .lost: return .secondary
        case .needsReview: return .red
        }
    }
}

struct BetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var draws: [DrawRecord]
    @State private var actionMessage = ""
    let bet: BetRecord

    private var draw: DrawRecord? {
        draws.first { $0.lottery == bet.lottery && $0.period == bet.period }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("投注") {
                    LabeledContent("彩种", value: bet.lottery.displayName)
                    LabeledContent("期号", value: bet.period)
                    LabeledContent("玩法", value: bet.ruleNameSnapshot)
                    LabeledContent("投注内容", value: bet.input)
                    LabeledContent("投注金额", value: Money.format(cents: bet.amountCents))
                    LabeledContent("投注时间", value: bet.betDate.formatted(date: .abbreviated, time: .shortened))
                }
                Section("结算") {
                    LabeledContent("状态", value: bet.status.displayName)
                    LabeledContent("中奖金额", value: Money.format(cents: bet.payoutCents))
                    LabeledContent("盈亏", value: Money.format(cents: bet.profitCents, showSign: true))
                    LabeledContent("基础本金", value: Money.format(cents: bet.unitStakeCents))
                    LabeledContent("基础奖金", value: Money.format(cents: bet.unitPayoutCents))
                    LabeledContent("规则版本", value: "\(bet.ruleVersion)")
                    if !bet.settlementDescription.isEmpty {
                        Text(bet.settlementDescription)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("开奖信息") {
                    if let draw {
                        LabeledContent("开奖号码", value: draw.digits)
                        LabeledContent("开奖日期", value: draw.drawDate.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("数据来源", value: draw.source.displayName)
                        LabeledContent("最近更新", value: draw.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        Button("按已保存规则重新结算") {
                            do {
                                try LedgerService(context: modelContext).settleBet(bet)
                                actionMessage = "已重新结算"
                            } catch {
                                actionMessage = error.localizedDescription
                            }
                        }
                    } else {
                        Text("等待该期开奖号码")
                            .foregroundStyle(.secondary)
                    }
                    if !actionMessage.isEmpty {
                        Text(actionMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("投注详情")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
