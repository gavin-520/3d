import SwiftUI
import SwiftData
import Charts

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("概览", systemImage: "chart.bar.xaxis") }
            BetsListView()
                .tabItem { Label("投注", systemImage: "list.bullet.rectangle") }
            DrawsView()
                .tabItem { Label("开奖", systemImage: "number.circle") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(.indigo)
        .task {
            RuleCatalog.seedIfNeeded(context: modelContext)
            _ = await DrawRefreshService.refreshPending(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { _ = await DrawRefreshService.refreshPending(context: modelContext) }
        }
    }
}

private enum DateScope: String, CaseIterable, Identifiable, Hashable {
    case all = "全部时间"
    case today = "今天"
    case week = "近7天"
    case custom = "自定义"

    var id: String { rawValue }
}

private enum ChartGrouping: String, CaseIterable, Identifiable, Hashable {
    case day = "按日"
    case period = "按期"

    var id: String { rawValue }
}

struct DashboardView: View {
    @Query(sort: \BetRecord.betDate, order: .reverse) private var bets: [BetRecord]
    @State private var selectedLottery: LotteryKind?
    @State private var dateScope: DateScope = .all
    @State private var grouping: ChartGrouping = .day
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var toDate = Date.now

    private var filteredBets: [BetRecord] {
        var result = bets
        if let selectedLottery { result = result.filter { $0.lottery == selectedLottery } }
        switch dateScope {
        case .all:
            break
        case .today:
            result = result.filter { Calendar.current.isDateInToday($0.betDate) }
        case .week:
            let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
            result = result.filter { $0.betDate >= start }
        case .custom:
            let start = Calendar.current.startOfDay(for: fromDate)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: toDate)) ?? toDate
            result = result.filter { $0.betDate >= start && $0.betDate < end }
        }
        return result
    }

    private var totalBet: Int64 { filteredBets.reduce(0) { $0 + $1.amountCents } }
    private var totalPayout: Int64 { filteredBets.reduce(0) { $0 + $1.payoutCents } }
    private var settledBet: Int64 {
        filteredBets.filter { $0.status == .won || $0.status == .lost }.reduce(0) { $0 + $1.amountCents }
    }
    private var pending: Int64 {
        filteredBets.filter { $0.status == .pending || $0.status == .needsReview }.reduce(0) { $0 + $1.amountCents }
    }
    private var wonCount: Int { filteredBets.filter { $0.status == .won }.count }

    private var chartData: [DashboardPoint] {
        switch grouping {
        case .day:
            let grouped = Dictionary(grouping: filteredBets) { Calendar.current.startOfDay(for: $0.betDate) }
            return grouped.map { date, values in
                DashboardPoint(
                    id: "day-\(date.timeIntervalSince1970)",
                    label: date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)),
                    sortDate: date,
                    bet: values.reduce(0) { $0 + $1.amountCents },
                    payout: values.reduce(0) { $0 + $1.payoutCents },
                    settledBet: values.filter { $0.status == .won || $0.status == .lost }.reduce(0) { $0 + $1.amountCents },
                    pendingBet: values.filter { $0.status == .pending || $0.status == .needsReview }.reduce(0) { $0 + $1.amountCents }
                )
            }.sorted { $0.sortDate < $1.sortDate }.suffix(14).map { $0 }
        case .period:
            let grouped = Dictionary(grouping: filteredBets) { "\($0.lotteryRaw)|\($0.period)" }
            return grouped.map { key, values in
                DashboardPoint(
                    id: key,
                    label: values.first.map { "\($0.lottery.displayName.prefix(2)) \($0.period)" } ?? key,
                    sortDate: values.map(\.betDate).max() ?? .distantPast,
                    bet: values.reduce(0) { $0 + $1.amountCents },
                    payout: values.reduce(0) { $0 + $1.payoutCents },
                    settledBet: values.filter { $0.status == .won || $0.status == .lost }.reduce(0) { $0 + $1.amountCents },
                    pendingBet: values.filter { $0.status == .pending || $0.status == .needsReview }.reduce(0) { $0 + $1.amountCents }
                )
            }.sorted { $0.sortDate < $1.sortDate }.suffix(14).map { $0 }
        }
    }

    private var summaryRows: [DashboardPoint] {
        chartData.reversed()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("彩种", selection: $selectedLottery) {
                        Text("全部彩种").tag(LotteryKind?.none)
                        ForEach(LotteryKind.allCases) { lottery in
                            Text(lottery.displayName).tag(LotteryKind?.some(lottery))
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Menu {
                            Picker("统计周期", selection: $dateScope) {
                                ForEach(DateScope.allCases) { scope in
                                    Text(scope.rawValue).tag(scope)
                                }
                            }
                        } label: {
                            Label(dateScope.rawValue, systemImage: "calendar")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        Picker("分组", selection: $grouping) {
                            ForEach(ChartGrouping.allCases) { value in
                                Text(value.rawValue).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 170)
                    }

                    if dateScope == .custom {
                        HStack {
                            DatePicker("起始", selection: $fromDate, displayedComponents: .date)
                            DatePicker("结束", selection: $toDate, displayedComponents: .date)
                        }
                        .font(.caption)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                        StatCard(title: "投注总额", value: Money.format(cents: totalBet), tint: .indigo)
                        StatCard(title: "中奖总额", value: Money.format(cents: totalPayout), tint: .green)
                        StatCard(title: "已结算盈亏", value: Money.format(cents: totalPayout - settledBet, showSign: true), tint: (totalPayout - settledBet) >= 0 ? .green : .red)
                        StatCard(title: "待开奖/复核", value: Money.format(cents: pending), tint: .orange)
                    }

                    HStack {
                        Text(grouping == .day ? "投注与中奖金额" : "按期汇总")
                            .font(.headline)
                        Spacer()
                        Text("中奖 \(wonCount) 笔")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    if chartData.isEmpty {
                        ContentUnavailableView("没有统计数据", systemImage: "chart.bar.xaxis", description: Text("新增投注后，这里会展示金额趋势"))
                            .frame(height: 220)
                    } else {
                        Chart(chartData) { point in
                            BarMark(
                                x: .value(grouping.rawValue, point.label),
                                y: .value("投注", Double(point.bet) / 100.0)
                            )
                            .foregroundStyle(.indigo.gradient)
                            LineMark(
                                x: .value(grouping.rawValue, point.label),
                                y: .value("中奖", Double(point.payout) / 100.0)
                            )
                            .foregroundStyle(.green)
                            .symbol(Circle())
                        }
                        .frame(height: 240)
                        .chartYAxisLabel("金额（元）")
                    }

                    if !summaryRows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(grouping == .day ? "每日明细" : "每期明细")
                                .font(.headline)
                            ForEach(summaryRows) { row in
                                HStack {
                                    Text(row.label)
                                        .lineLimit(1)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("投 \(Money.format(cents: row.bet))")
                                        Text("中 \(Money.format(cents: row.payout))")
                                            .foregroundStyle(.green)
                                        Text("盈亏 \(Money.format(cents: row.payout - row.settledBet, showSign: true))")
                                            .foregroundStyle(row.payout - row.settledBet >= 0 ? .green : .red)
                                        if row.pendingBet > 0 {
                                            Text("待结算 \(Money.format(cents: row.pendingBet))")
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    .font(.caption)
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("投注概览")
        }
    }
}

private struct DashboardPoint: Identifiable {
    let id: String
    let label: String
    let sortDate: Date
    let bet: Int64
    let payout: Int64
    let settledBet: Int64
    let pendingBet: Int64
}

private struct StatCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}
