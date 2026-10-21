import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RuleDefinitionRecord.name) private var rules: [RuleDefinitionRecord]
    @State private var selectedLottery: LotteryKind = .fucai3D
    @State private var showingAPI = false
    @State private var showingImporter = false
    @State private var exporting = false
    @State private var exportDocument = ExportFileDocument(data: Data(), contentType: .json)
    @State private var exportType: UTType = .json
    @State private var exportName = "彩票账本备份"
    @State private var message = ""

    var body: some View {
        NavigationStack {
            List {
                apiSettingsSection
                rulesSection
                dataManagementSection
                clearDataSection
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showingAPI) {
                APISettingsView(lottery: selectedLottery)
            }
            .fileExporter(
                isPresented: $exporting,
                document: exportDocument,
                contentType: exportType,
                defaultFilename: exportName
            ) { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
        }
    }

    private var apiSettingsSection: some View {
        Section("开奖接口") {
            ForEach(LotteryKind.allCases) { lottery in
                apiSettingsRow(for: lottery)
            }
        }
    }

    private func apiSettingsRow(for lottery: LotteryKind) -> some View {
        let configuration = ProviderSettingsStore.configuration(for: lottery)
        return Button {
            selectedLottery = lottery
            showingAPI = true
        } label: {
            HStack {
                Label(lottery.displayName, systemImage: "network")
                Spacer()
                Text(configuration.endpointTemplate.isEmpty ? "未配置" : "已配置")
                    .font(.caption)
                    .foregroundStyle(configuration.endpointTemplate.isEmpty ? .secondary : .green)
            }
        }
    }

    private var rulesSection: some View {
        Section("规则") {
            NavigationLink {
                RuleSettingsView()
            } label: {
                Label("玩法与赔率", systemImage: "slider.horizontal.3")
            }
            Text("\(enabledRuleCount) 条启用规则 · 每个彩种一套")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var enabledRuleCount: Int {
        rules.filter(\.enabled).count
    }

    private var dataManagementSection: some View {
        Section("数据管理") {
            Button {
                startExport(type: .json)
            } label: {
                Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
            }
            Button {
                startExport(type: .commaSeparatedText)
            } label: {
                Label("导出投注 CSV", systemImage: "tablecells")
            }
            importButton
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var importButton: some View {
        Button {
            showingImporter = true
        } label: {
            Label("导入 JSON / CSV", systemImage: "square.and.arrow.down")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, .commaSeparatedText]
        ) { result in
            handleImportResult(result)
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let data = try Data(contentsOf: url)
                if url.pathExtension.lowercased() == "csv" {
                    try ExportService.importCSV(data, context: modelContext)
                } else {
                    try ExportService.importData(data, context: modelContext)
                }
                message = "导入完成"
            } catch {
                message = error.localizedDescription
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    private var clearDataSection: some View {
        Section {
            Button(role: .destructive) {
                clearAll()
            } label: {
                Label("清空本机数据", systemImage: "trash")
            }
        } footer: {
            Text("投注与开奖记录仅保存在本机；接口 token 使用系统 Keychain 保存。")
        }
    }

    private func startExport(type: UTType) {
        exportType = type
        if type == .json {
            exportDocument = ExportFileDocument(data: ExportService.export(context: modelContext), contentType: .json)
            exportName = "彩票账本备份.json"
        } else {
            exportDocument = ExportFileDocument(data: ExportService.exportCSV(context: modelContext), contentType: .commaSeparatedText)
            exportName = "彩票投注记录.csv"
        }
        exporting = true
    }

    private func clearAll() {
        let bets = (try? modelContext.fetch(FetchDescriptor<BetRecord>())) ?? []
        let draws = (try? modelContext.fetch(FetchDescriptor<DrawRecord>())) ?? []
        bets.forEach(modelContext.delete)
        draws.forEach(modelContext.delete)
        try? modelContext.save()
    }
}

struct ExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    var contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct RuleSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RuleDefinitionRecord.name) private var rules: [RuleDefinitionRecord]
    @State private var selectedLottery: LotteryKind = .fucai3D
    @State private var showingEditor = false
    @State private var selectedRule: RuleDefinitionRecord?

    private var visibleRules: [RuleDefinitionRecord] {
        rules.filter { $0.lottery == selectedLottery }
    }

    var body: some View {
        List {
            Picker("彩种", selection: $selectedLottery) {
                ForEach(LotteryKind.allCases) { lottery in
                    Text(lottery.displayName).tag(lottery)
                }
            }
            .pickerStyle(.segmented)
            ForEach(visibleRules) { rule in
                Button {
                    selectedRule = rule
                    showingEditor = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.name).foregroundStyle(.primary)
                            Text("\(Money.format(cents: rule.fixedStakeCents)) → \(Money.format(cents: rule.payoutCents))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(rule.enabled ? .green : .secondary)
                    }
                }
            }
        }
        .navigationTitle("玩法与赔率")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") { RuleCatalog.restoreDefaults(context: modelContext) }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let selectedRule { RuleEditorView(rule: selectedRule) }
        }
    }
}

struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let rule: RuleDefinitionRecord
    @State private var name: String
    @State private var stake: String
    @State private var payout: String
    @State private var enabled: Bool
    @State private var notes: String
    @State private var inputHint: String
    @State private var inputStyle: RuleInputStyle
    @State private var matchMode: RuleMatchMode

    init(rule: RuleDefinitionRecord) {
        self.rule = rule
        _name = State(initialValue: rule.name)
        _stake = State(initialValue: String(format: "%.2f", Double(rule.fixedStakeCents) / 100))
        _payout = State(initialValue: String(format: "%.2f", Double(rule.payoutCents) / 100))
        _enabled = State(initialValue: rule.enabled)
        _notes = State(initialValue: rule.notes)
        _inputHint = State(initialValue: rule.inputHint)
        _inputStyle = State(initialValue: rule.inputStyle)
        _matchMode = State(initialValue: rule.matchMode)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("玩法名称", text: $name)
                TextField("单注本金（元）", text: $stake).keyboardType(.decimalPad)
                TextField("单注奖金（元）", text: $payout).keyboardType(.decimalPad)
                Picker("输入格式", selection: $inputStyle) {
                    ForEach(RuleInputStyle.allCases) { style in Text(style.displayName).tag(style) }
                }
                Picker("匹配方式", selection: $matchMode) {
                    ForEach(RuleMatchMode.allCases) { mode in Text(mode.displayName).tag(mode) }
                }
                TextField("投注输入提示", text: $inputHint)
                Toggle("启用", isOn: $enabled)
                TextField("规则说明", text: $notes, axis: .vertical)
            }
            .navigationTitle("编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let stakeCents = Money.parseCents(stake),
                              let payoutCents = Money.parseCents(payout),
                              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              stakeCents > 0 else { return }
                        rule.name = name
                        rule.fixedStakeCents = stakeCents
                        rule.payoutCents = payoutCents
                        rule.inputStyleRaw = inputStyle.rawValue
                        rule.matchModeRaw = matchMode.rawValue
                        rule.inputHint = inputHint
                        rule.enabled = enabled
                        rule.notes = notes
                        rule.version += 1
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct APISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let lottery: LotteryKind
    @State private var endpoint = ""
    @State private var periodPath = "data.period"
    @State private var digitsPath = "data.digits"
    @State private var datePath = "data.drawDate"
    @State private var headers = "{}"
    @State private var query = "{}"
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("接口") {
                    TextField("URL 模板，可用 {period}", text: $endpoint)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("期号字段路径", text: $periodPath)
                    TextField("开奖号码字段路径", text: $digitsPath)
                    TextField("开奖日期字段路径", text: $datePath)
                }
                Section("请求") {
                    TextField("查询参数 JSON", text: $query, axis: .vertical)
                    TextField("请求头 JSON", text: $headers, axis: .vertical)
                    SecureField("Authorization token", text: $token)
                }
                Section {
                    Text("接口返回 JSON 后，按字段路径读取期号、三位开奖号码和开奖日期。请求失败时不会覆盖已有结算结果。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("\(lottery.displayName)接口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        ProviderSettingsStore.save(
                            APIProviderConfiguration(
                                endpointTemplate: endpoint,
                                periodPath: periodPath,
                                digitsPath: digitsPath,
                                datePath: datePath,
                                headersJSON: headers,
                                queryJSON: query,
                                token: ""
                            ),
                            for: lottery,
                            token: token
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                let value = ProviderSettingsStore.configuration(for: lottery)
                endpoint = value.endpointTemplate
                periodPath = value.periodPath
                digitsPath = value.digitsPath
                datePath = value.datePath
                headers = value.headersJSON
                query = value.queryJSON
                token = SecureTokenStore.get(for: lottery)
            }
        }
    }
}
