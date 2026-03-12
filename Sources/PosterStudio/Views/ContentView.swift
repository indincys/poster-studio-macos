import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var appState: AppState
    @State private var isTitleModelSettingsExpanded = false
    @State private var activeSheet: ActiveSheet?
    @State private var titleSelection = Set<TitleRecord.ID>()
    @State private var taskSelection = Set<TaskRecord.ID>()

    var body: some View {
        TabView {
            librariesTab
                .tabItem { Text("数据源") }
            titleGenerationTab
                .tabItem { Text("标题生成") }
            taskGenerationTab
                .tabItem { Text("任务单生成") }
        }
        .padding(18)
        .frame(minWidth: 1180, minHeight: 780)
        .task {
            await appState.performInitialUpdateCheckIfNeeded()
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    // MARK: - Sheet Router

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .libraryDetail(let kind):
            LibraryDetailView(kind: kind, appState: appState)
        case .editTitle(let record):
            TitleEditSheet(draft: record) { updated in
                if let i = appState.titleRecords.firstIndex(where: { $0.id == updated.id }) {
                    appState.titleRecords[i] = updated
                }
            }
        case .editTask(let record):
            TaskEditSheet(draft: record) { updated in
                if let i = appState.taskRecords.firstIndex(where: { $0.id == updated.id }) {
                    appState.taskRecords[i] = updated
                }
            }
        }
    }

    // MARK: - Libraries Tab

    private var librariesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("载入仓库样本") {
                    appState.loadRepositorySamplesIfAvailable()
                }
                Button("恢复内置样本") {
                    appState.loadBuiltInSamples()
                }
                Spacer()
                Text(appState.statusMessage)
                    .foregroundStyle(.secondary)
                SettingsLink {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("设置 (⌘,)")
            }

            HStack(spacing: 16) {
                summaryCardButton(title: "视频库", value: "\(appState.videoRecords.count) 条", color: .orange) {
                    activeSheet = .libraryDetail(.video)
                }
                summaryCardButton(title: "标签库", value: "\(appState.tagRecords.count) 条", color: .green) {
                    activeSheet = .libraryDetail(.tag)
                }
                summaryCardButton(title: "标题库", value: "\(appState.titleRecords.count) 条", color: .blue) {
                    activeSheet = .libraryDetail(.title)
                }
                summaryCardButton(title: "任务单", value: "\(appState.taskRecords.count) 条", color: .pink) {
                    activeSheet = .libraryDetail(.task)
                }
            }

            HStack(spacing: 12) {
                Button("导入视频库") { importWorkbook(kind: .video) }
                Button("导出视频库") { exportWorkbook(kind: .video) }
                Button("导入标签库") { importWorkbook(kind: .tag) }
                Button("导出标签库") { exportWorkbook(kind: .tag) }
                Button("导入标题库") { importWorkbook(kind: .title) }
                Button("导出标题库") { exportWorkbook(kind: .title) }
                Button("导出任务单") { exportWorkbook(kind: .task) }
                    .disabled(appState.taskRecords.isEmpty)
            }

            GroupBox("视频库预览（点击上方卡片查看完整内容）") {
                Table(appState.videoRecords) {
                    TableColumn("视频文件名", value: \.videoFileName)
                    TableColumn("SKU编码", value: \.skuCode)
                    TableColumn("SKU款式", value: \.skuStyle)
                    TableColumn("使用状态", value: \.useStatus)
                    TableColumn("发布日期", value: \.publishDate)
                    TableColumn("发布时间", value: \.publishTime)
                    TableColumn("热门款", value: \.popularFlag)
                }
                .frame(minHeight: 220)
            }

            GroupBox("标签库预览") {
                Table(appState.tagRecords) {
                    TableColumn("SKU编码", value: \.skuCode)
                    TableColumn("SKU款式名", value: \.skuStyleName)
                    TableColumn("标签1", value: \.tag1)
                    TableColumn("标签2", value: \.tag2)
                    TableColumn("标签3", value: \.tag3)
                }
                .frame(minHeight: 170)
            }
        }
    }

    // MARK: - Title Generation Tab

    private var titleGenerationTab: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("标题生成组件")
                        .font(.title3.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        Text("标题生成 Prompt")
                            .font(.headline)
                        TextEditor(text: $appState.titleSettings.generationPrompt)
                            .font(.body)
                            .frame(minHeight: 150)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.25)))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("标题打分 Prompt")
                            .font(.headline)
                        TextEditor(text: $appState.titleSettings.scoringPrompt)
                            .font(.body)
                            .frame(minHeight: 130)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.25)))
                    }

                    Stepper("生成数量：\(appState.titleSettings.count)", value: $appState.titleSettings.count, in: 1...50)

                    GroupBox {
                        DisclosureGroup(isExpanded: $isTitleModelSettingsExpanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("模型提供方", selection: $appState.titleSettings.provider) {
                                    ForEach(TitleProviderPreset.allCases) { provider in
                                        Text(provider.displayName).tag(provider)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: appState.titleSettings.provider) { _, _ in
                                    appState.titleSettings.applyProviderPreset()
                                }

                                SecureField("API Key（可选）", text: $appState.titleSettings.apiKey)
                                TextField("Base URL", text: $appState.titleSettings.baseURL)
                                TextField("模型名", text: $appState.titleSettings.model)

                                Text(appState.titleSettings.provider.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                Text("API Key 可以留空；若当前网关允许匿名访问会直接调用，否则自动回退到内置生成和估分。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .textFieldStyle(.roundedBorder)
                            .padding(.top, 8)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("模型设置")
                                    .font(.headline)
                                Text("\(appState.titleSettings.provider.displayName) · \(appState.titleSettings.model.isEmpty ? "未设置模型" : appState.titleSettings.model)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack {
                        Button(appState.isGeneratingTitles ? "生成中..." : "开始生成") {
                            Task { await appState.generateTitles() }
                        }
                        .disabled(appState.isGeneratingTitles)

                        Button("导入标题库") { importWorkbook(kind: .title) }
                        Button("导出标题库") { exportWorkbook(kind: .title) }
                    }

                    Text("右键标题可编辑或删除，双击直接进入编辑。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            .frame(width: 360)

            GroupBox("标题库预览") {
                Table(appState.titleRecords, selection: $titleSelection) {
                    TableColumn("标题", value: \.title)
                    TableColumn("使用状态", value: \.useStatus)
                    TableColumn("使用次数") { record in Text("\(record.useCount)") }
                    TableColumn("爆款分") { record in Text("\(record.hotScore)") }
                    TableColumn("短标题（视频号）", value: \.shortTitleWechat)
                }
                .contextMenu(forSelectionType: TitleRecord.ID.self) { selectedIDs in
                    titleContextMenuItems(for: selectedIDs)
                } primaryAction: { selectedIDs in
                    if let id = selectedIDs.first,
                       let record = appState.titleRecords.first(where: { $0.id == id }) {
                        activeSheet = .editTitle(record)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func titleContextMenuItems(for selectedIDs: Set<TitleRecord.ID>) -> some View {
        if let id = selectedIDs.first,
           let record = appState.titleRecords.first(where: { $0.id == id }) {
            Button("编辑") {
                activeSheet = .editTitle(record)
            }
        }
        if !selectedIDs.isEmpty {
            Divider()
            Button("删除所选 (\(selectedIDs.count))", role: .destructive) {
                appState.titleRecords.removeAll { selectedIDs.contains($0.id) }
                titleSelection = []
            }
        }
    }

    // MARK: - Task Generation Tab

    private var taskGenerationTab: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("任务单生成组件")
                        .font(.title3.bold())

                    DatePicker(
                        "任务日期",
                        selection: $appState.taskSettings.targetDate,
                        displayedComponents: .date
                    )

                    TextField("视频可用状态", text: $appState.taskSettings.allowedVideoStatus)
                        .textFieldStyle(.roundedBorder)
                    TextField("标题可用状态", text: $appState.taskSettings.titleStatus)
                        .textFieldStyle(.roundedBorder)

                    Picker("视频筛选", selection: $appState.taskSettings.popularFilter) {
                        ForEach(PopularFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("标题筛选", selection: $appState.taskSettings.titleFilterMode) {
                        ForEach(TitleFilterMode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Stepper("爆款分阈值：\(appState.taskSettings.scoreThreshold)", value: $appState.taskSettings.scoreThreshold, in: 0...100)

                    GroupBox("平台计划") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(appState.taskSettings.platformPlans.enumerated()), id: \.element.id) { index, _ in
                                HStack {
                                    TextField("平台", text: $appState.taskSettings.platformPlans[index].platform)
                                    TextField("账号名称", text: $appState.taskSettings.platformPlans[index].accountName)
                                    TextField("标记原创", text: $appState.taskSettings.platformPlans[index].markOriginal)
                                    Button(role: .destructive) {
                                        appState.taskSettings.platformPlans.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(appState.taskSettings.platformPlans.count <= 1)
                                }
                            }

                            Button("新增平台计划") {
                                appState.taskSettings.platformPlans.append(
                                    PlatformPlan(platform: "douyin", accountName: "新账号", markOriginal: "是")
                                )
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                    }

                    GenerationFlowView(settings: appState.taskSettings)

                    HStack {
                        Button(appState.isGeneratingTasks ? "生成中..." : "生成任务单") {
                            appState.generateTasks()
                        }
                        .disabled(appState.isGeneratingTasks)
                        Button("导出任务单") { exportWorkbook(kind: .task) }
                            .disabled(appState.taskRecords.isEmpty)
                    }

                    Text("右键任务可编辑或删除，双击直接进入编辑。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            .frame(width: 400)
            .frame(maxHeight: .infinity, alignment: .top)

            GroupBox("任务单预览") {
                Table(appState.taskRecords, selection: $taskSelection) {
                    TableColumn("任务ID", value: \.taskID)
                    TableColumn("平台", value: \.publishPlatform)
                    TableColumn("账号名称", value: \.accountName)
                    TableColumn("SKU款式名", value: \.skuStyleName)
                    TableColumn("标题", value: \.title)
                    TableColumn("短标题", value: \.shortTitleWechat)
                    TableColumn("看后搜", value: \.blueSearchTermDouyin)
                    TableColumn("定时发布时间", value: \.scheduledTime)
                    TableColumn("任务状态", value: \.taskStatus)
                }
                .contextMenu(forSelectionType: TaskRecord.ID.self) { selectedIDs in
                    taskContextMenuItems(for: selectedIDs)
                } primaryAction: { selectedIDs in
                    if let id = selectedIDs.first,
                       let record = appState.taskRecords.first(where: { $0.id == id }) {
                        activeSheet = .editTask(record)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskContextMenuItems(for selectedIDs: Set<TaskRecord.ID>) -> some View {
        if let id = selectedIDs.first,
           let record = appState.taskRecords.first(where: { $0.id == id }) {
            Button("编辑") {
                activeSheet = .editTask(record)
            }
        }
        if !selectedIDs.isEmpty {
            Divider()
            Button("删除所选 (\(selectedIDs.count))", role: .destructive) {
                appState.taskRecords.removeAll { selectedIDs.contains($0.id) }
                taskSelection = []
            }
        }
    }

    // MARK: - Helpers

    private func summaryCardButton(title: String, value: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func importWorkbook(kind: WorkbookKind) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.spreadsheet]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch kind {
            case .video:
                try appState.importVideoLibrary(from: url)
            case .tag:
                try appState.importTagLibrary(from: url)
            case .title:
                try appState.importTitleLibrary(from: url)
            case .task:
                break
            }
        } catch {
            appState.statusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func exportWorkbook(kind: WorkbookKind) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.spreadsheet]
        panel.nameFieldStringValue = defaultFileName(for: kind)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch kind {
            case .video:
                try appState.exportVideoLibrary(to: url)
            case .tag:
                try appState.exportTagLibrary(to: url)
            case .title:
                try appState.exportTitleLibrary(to: url)
            case .task:
                try appState.exportTaskSheet(to: url)
            }
        } catch {
            appState.statusMessage = error.localizedDescription
        }
    }

    private func defaultFileName(for kind: WorkbookKind) -> String {
        switch kind {
        case .video:
            return "video_library.xlsx"
        case .tag:
            return "tag_library.xlsx"
        case .title:
            return "title_library.xlsx"
        case .task:
            return "tasks_\(TaskGenerationService.isoDateString(from: appState.taskSettings.targetDate)).xlsx"
        }
    }
}

// MARK: - Supporting Types

private enum WorkbookKind {
    case video, tag, title, task
}

private enum LibraryDetailKind: String {
    case video, tag, title, task
}

private enum ActiveSheet: Identifiable {
    case libraryDetail(LibraryDetailKind)
    case editTitle(TitleRecord)
    case editTask(TaskRecord)

    var id: String {
        switch self {
        case .libraryDetail(let kind): "detail-\(kind.rawValue)"
        case .editTitle(let r): "editTitle-\(r.id)"
        case .editTask(let r): "editTask-\(r.id)"
        }
    }
}

// MARK: - Library Detail View

private struct LibraryDetailView: View {
    let kind: LibraryDetailKind
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(sheetTitle).font(.title2.bold())
                Text("\(recordCount) 条").foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            tableContent
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 500)
    }

    private var sheetTitle: String {
        switch kind {
        case .video: "视频库详情"
        case .tag: "标签库详情"
        case .title: "标题库详情"
        case .task: "任务单详情"
        }
    }

    private var recordCount: Int {
        switch kind {
        case .video: appState.videoRecords.count
        case .tag: appState.tagRecords.count
        case .title: appState.titleRecords.count
        case .task: appState.taskRecords.count
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        switch kind {
        case .video:
            Table(appState.videoRecords) {
                TableColumn("视频文件名", value: \.videoFileName)
                TableColumn("SKU编码", value: \.skuCode)
                TableColumn("SKU款式", value: \.skuStyle)
                TableColumn("使用状态", value: \.useStatus)
                TableColumn("发布日期", value: \.publishDate)
                TableColumn("发布时间", value: \.publishTime)
                TableColumn("小黄车标题", value: \.yellowCartTitle)
                TableColumn("看后搜小蓝词", value: \.blueSearchTerm)
                TableColumn("位置信息", value: \.locationWechat)
                TableColumn("热门款", value: \.popularFlag)
            }
        case .tag:
            Table(appState.tagRecords) {
                TableColumn("SKU编码", value: \.skuCode)
                TableColumn("SKU款式名", value: \.skuStyleName)
                TableColumn("标签1", value: \.tag1)
                TableColumn("标签2", value: \.tag2)
                TableColumn("标签3", value: \.tag3)
                TableColumn("标签4", value: \.tag4)
                TableColumn("标签5", value: \.tag5)
            }
        case .title:
            Table(appState.titleRecords) {
                TableColumn("标题", value: \.title)
                TableColumn("使用状态", value: \.useStatus)
                TableColumn("使用次数") { r in Text("\(r.useCount)") }
                TableColumn("爆款分") { r in Text("\(r.hotScore)") }
                TableColumn("短标题（视频号）", value: \.shortTitleWechat)
            }
        case .task:
            Table(appState.taskRecords) {
                TableColumn("任务ID", value: \.taskID)
                TableColumn("平台", value: \.publishPlatform)
                TableColumn("账号名称", value: \.accountName)
                TableColumn("SKU款式名", value: \.skuStyleName)
                TableColumn("标题", value: \.title)
                TableColumn("短标题", value: \.shortTitleWechat)
                TableColumn("看后搜", value: \.blueSearchTermDouyin)
                TableColumn("定时发布时间", value: \.scheduledTime)
                TableColumn("任务状态", value: \.taskStatus)
            }
        }
    }
}

// MARK: - Title Edit Sheet

private struct TitleEditSheet: View {
    @State var draft: TitleRecord
    let onSave: (TitleRecord) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑标题").font(.title3.bold())
            Form {
                TextField("标题", text: $draft.title)
                TextField("使用状态", text: $draft.useStatus)
                Stepper("使用次数：\(draft.useCount)", value: $draft.useCount, in: 0...9999)
                Stepper("爆款分：\(draft.hotScore)", value: $draft.hotScore, in: 0...100)
                TextField("短标题（视频号）", text: $draft.shortTitleWechat)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

// MARK: - Task Edit Sheet

private struct TaskEditSheet: View {
    @State var draft: TaskRecord
    let onSave: (TaskRecord) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑任务 \(draft.taskID)").font(.title3.bold())
            ScrollView {
                Form {
                    Section("调度") {
                        TextField("账号名称", text: $draft.accountName)
                        TextField("定时发布时间", text: $draft.scheduledTime)
                        TextField("任务状态", text: $draft.taskStatus)
                    }
                    Section("内容") {
                        TextField("标题", text: $draft.title)
                        TextField("短标题（视频号）", text: $draft.shortTitleWechat)
                        TextField("标签1", text: $draft.tag1)
                        TextField("标签2", text: $draft.tag2)
                        TextField("标签3", text: $draft.tag3)
                        TextField("标签4", text: $draft.tag4)
                        TextField("标签5", text: $draft.tag5)
                    }
                    Section("平台字段") {
                        TextField("小黄车标题（抖音）", text: $draft.yellowCartTitleDouyin)
                        TextField("看后搜小蓝词（抖音）", text: $draft.blueSearchTermDouyin)
                        TextField("位置信息", text: $draft.location)
                        TextField("标记原创", text: $draft.markOriginal)
                    }
                }
                .formStyle(.grouped)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 600)
    }
}

// MARK: - Generation Flow View

private struct GenerationFlowView: View {
    let settings: TaskGenerationSettings

    var body: some View {
        GroupBox("业务流程可视化") {
            VStack(alignment: .leading, spacing: 10) {
                flowRow(title: "1. 从视频库提取", detail: "按日期 + 使用状态 + 热门款筛选")
                flowRow(title: "2. 从标题库提取", detail: "\(settings.titleFilterMode.rawValue)，阈值 \(settings.scoreThreshold)")
                flowRow(title: "3. 从标签库匹配", detail: "按 SKU 编码匹配标签1-标签5")
                flowRow(title: "4. 按平台展开任务", detail: settings.platformPlans.map(\.platform).joined(separator: " / "))
                flowRow(title: "5. 回写状态", detail: "视频改为已生成任务，标题使用次数 +1")
            }
        }
    }

    private func flowRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension UTType {
    static let spreadsheet = UTType(filenameExtension: "xlsx") ?? .data
}
