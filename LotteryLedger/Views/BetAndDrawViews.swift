import SwiftUI
import SwiftData

struct AddBetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RuleDefinitionRecord.name) private var allRules: [RuleDefinitionRecord]

    @State private var lottery: LotteryKind = .fucai3D
    @State private var period = ""
    @State private var selectedRuleCode = ""
    @State private var input = ""
    @State private var amount = ""
    @State private var betDate = Date.now
    @State private var errorMessage = ""
    @State private var amountManuallyChanged = false

    private var rules: [RuleDefinitionRecord] {
        allRules.filter { $0.lottery == lottery && $0.enabled }
    }

    private var selectedRule: RuleDefinitionRecord? {
        rules.first { $0.code == selectedRuleCode } ?? rules.first
    }

    private var combinationHint: String {
        guard let rule = selectedRule else { return "" }
        let count = RuleEngine.combinationCount(rule: rule, input: input)
        return count > 1 ? "本次选号展开为 \(count) 注，最低金额 \(Money.format(cents: RuleEngine.requiredStakeCents(rule: rule, input: input)))" : ""
    }

    private var amountBinding: Binding<String> {
        Binding(
            get: { amount },
            set: {
                amount = $0
                amountManuallyChanged = true
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    Picker("彩种", selection: $lottery) {
                        ForEach(LotteryKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .onChange(of: lottery) { _, _ in
                        selectedRuleCode = rules.first?.code ?? ""
                        input = ""
                        amountManuallyChanged = false
                        if let rule = rules.first {
                            amount = String(format: "%.2f", Double(rule.fixedStakeCents) / 100)
                        }
                    }
                    TextField("期号，例如 2026123", text: $period)
                        .keyboardType(.numbersAndPunctuation)
                    DatePicker("投注日期", selection: $betDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section("玩法") {
                    if rules.isEmpty {
                        Text("暂无可用规则，请在设置中恢复默认规则")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("玩法", selection: $selectedRuleCode) {
                            ForEach(rules) { rule in
                                Text(rule.name).tag(rule.code)
                            }
                        }
                        .onChange(of: selectedRuleCode) { _, _ in
                            input = ""
                            amountManuallyChanged = false
                            if let rule = selectedRule {
                                amount = String(format: "%.2f", Double(rule.fixedStakeCents) / 100)
                            }
                        }
                        if let rule = selectedRule {
                            Text(rule.inputHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if rule.matchMode == .sum || rule.matchMode == .span {
                                Label("目标值已包含在玩法名称中", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                TextField("投注内容", text: $input)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.numbersAndPunctuation)
                                    .onChange(of: input) { _, _ in
                                        guard !amountManuallyChanged, let rule = selectedRule else { return }
                                        amount = String(format: "%.2f", Double(RuleEngine.requiredStakeCents(rule: rule, input: input)) / 100)
                                    }
                            }
                            if !combinationHint.isEmpty {
                                Text(combinationHint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("金额") {
                    TextField("投注金额（元）", text: amountBinding)
                        .keyboardType(.decimalPad)
                    if let rule = selectedRule {
                        Text("基础单注本金 \(Money.format(cents: rule.fixedStakeCents)) · 单注奖金 \(Money.format(cents: rule.payoutCents)) · 金额需为 \(Money.format(cents: RuleEngine.requiredStakeCents(rule: rule, input: input))) 的整数倍")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("新增投注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(selectedRule == nil)
                }
            }
            .onAppear {
                selectedRuleCode = rules.first?.code ?? ""
                if amount.isEmpty, let rule = rules.first {
                    amount = String(format: "%.2f", Double(RuleEngine.requiredStakeCents(rule: rule, input: "")) / 100)
                }
            }
        }
    }

    private func save() {
        guard let rule = selectedRule else { return }
        guard !period.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请输入期号"
            return
        }
        guard let amountCents = Money.parseCents(amount) else {
            errorMessage = "请输入有效投注金额"
            return
        }
        do {
            try LedgerService(context: modelContext).addBet(
                lottery: lottery,
                period: period,
                rule: rule,
                input: input,
                amountCents: amountCents,
                date: betDate
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DrawsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DrawRecord.drawDate, order: .reverse) private var draws: [DrawRecord]
    @State private var showingManual = false
    @State private var selectedDraw: DrawRecord?
    @State private var refreshMessage = ""
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            List {
                if !refreshMessage.isEmpty {
                    Section {
                        Text(refreshMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if draws.isEmpty {
                    ContentUnavailableView("还没有开奖记录", systemImage: "number.circle", description: Text("可手动录入，或在设置中配置接口"))
                } else {
                    ForEach(draws) { draw in
                        Button {
                            selectedDraw = draw
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(draw.lottery.displayName) · \(draw.period)")
                                        .font(.headline)
                                    Spacer()
                                    Text(draw.source.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text(draw.digits.map(String.init).joined(separator: " "))
                                        .font(.title3.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.indigo)
                                    Spacer()
                                    Text(draw.drawDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        offsets.map { draws[$0] }.forEach(modelContext.delete)
                        try? modelContext.save()
                    }
                }
            }
            .navigationTitle("开奖中心")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                    .accessibilityLabel("刷新开奖号码")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingManual = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("手动录入开奖")
                }
            }
            .sheet(isPresented: $showingManual) {
                ManualDrawView()
            }
            .sheet(item: $selectedDraw) { draw in
                ManualDrawView(existing: draw)
            }
        }
    }

    private func refresh() async {
        isRefreshing = true
        let messages = await DrawRefreshService.refreshPending(context: modelContext)
        refreshMessage = messages.isEmpty ? "没有找到已配置接口的待开奖期号" : messages.joined(separator: "\n")
        isRefreshing = false
    }
}

struct ManualDrawView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var lottery: LotteryKind = .fucai3D
    @State private var period = ""
    @State private var digits = ""
    @State private var drawDate = Date.now
    @State private var errorMessage = ""
    let existing: DrawRecord?

    init(existing: DrawRecord? = nil) {
        self.existing = existing
        _lottery = State(initialValue: existing?.lottery ?? .fucai3D)
        _period = State(initialValue: existing?.period ?? "")
        _digits = State(initialValue: existing?.digits ?? "")
        _drawDate = State(initialValue: existing?.drawDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("彩种", selection: $lottery) {
                    ForEach(LotteryKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .disabled(existing != nil)
                TextField("期号", text: $period)
                    .keyboardType(.numbersAndPunctuation)
                TextField("开奖号码（3位）", text: $digits)
                    .keyboardType(.numberPad)
                DatePicker("开奖日期", selection: $drawDate, displayedComponents: [.date, .hourAndMinute])
                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(existing == nil ? "录入开奖" : "编辑开奖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
        }
    }

    private func save() {
        let normalized = digits.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !period.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入期号"; return }
        guard normalized.count == 3,
              normalized.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else {
            errorMessage = "开奖号码必须是三位数字"
            return
        }
        do {
            let service = LedgerService(context: modelContext)
            let payload = DrawPayload(period: period.trimmingCharacters(in: .whitespacesAndNewlines), digits: normalized, drawDate: drawDate, source: .manual)
            if let existing {
                try service.updateDraw(existing, with: payload, lottery: lottery)
            } else {
                try service.upsertDraw(payload, lottery: lottery)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
