import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main View

struct ContentView: View {
    @ObservedObject var appState: AppState
    @State private var selectedPage: SidebarItem? = .dashboard
    @State private var isTitleModelSettingsExpanded = false
    @State private var activeSheet: ActiveSheet?
    @State private var titleSelection = Set<TitleRecord.ID>()
    @State private var taskSelection = Set<TaskRecord.ID>()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack(alignment: .bottom) {
                detailView
                statusBar
            }
        }
        .frame(minWidth: 1180, minHeight: 780)
        .task { await appState.performInitialUpdateCheckIfNeeded() }
        .sheet(item: $activeSheet) { sheetContent(for: $0) }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedPage) {
            Section("工作区") {
                ForEach(SidebarItem.allCases) { item in
                    Label {
                        Text(item.rawValue)
                    } icon: {
                        Image(systemName: item.icon)
                            .foregroundStyle(item.tint)
                    }
                    .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    SettingsLink {
                        Label("设置", systemImage: "gear")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Text("v\(appState.currentVersion)")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Detail Router

    @ViewBuilder
    private var detailView: some View {
        switch selectedPage {
        case .dashboard, .none:
            dashboardView
        case .titleGeneration:
            titleGenerationView
        case .taskGeneration:
            taskGenerationView
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.statusMessage.contains("失败") || appState.statusMessage.contains("错误") ? .red : .green)
                .frame(width: 6, height: 6)
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
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

    // MARK: - Dashboard

    private var dashboardView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        dashboardCard(icon: "film.stack", title: "视频库", count: appState.videoRecords.count, color: .orange) {
                            activeSheet = .libraryDetail(.video)
                        }
                        dashboardCard(icon: "tag.fill", title: "标签库", count: appState.tagRecords.count, color: .green) {
                            activeSheet = .libraryDetail(.tag)
                        }
                        dashboardCard(icon: "text.quote", title: "标题库", count: appState.titleRecords.count, color: .blue) {
                            activeSheet = .libraryDetail(.title)
                        }
                        dashboardCard(icon: "checklist", title: "任务单", count: appState.taskRecords.count, color: .pink) {
                            activeSheet = .libraryDetail(.task)
                        }
                    }

                    importExportSection

                    GroupBox {
                        Table(appState.videoRecords) {
                            TableColumn("视频文件名", value: \.videoFileName)
                            TableColumn("SKU编码", value: \.skuCode)
                            TableColumn("SKU款式", value: \.skuStyle)
                            TableColumn("使用状态", value: \.useStatus)
                            TableColumn("发布日期", value: \.publishDate)
                            TableColumn("发布时间", value: \.publishTime)
                            TableColumn("热门款", value: \.popularFlag)
                        }
                        .frame(minHeight: 200)
                    } label: {
                        Label("视频库预览", systemImage: "film.stack")
                    }

                    GroupBox {
                        Table(appState.tagRecords) {
                            TableColumn("SKU编码", value: \.skuCode)
                            TableColumn("SKU款式名", value: \.skuStyleName)
                            TableColumn("标签1", value: \.tag1)
                            TableColumn("标签2", value: \.tag2)
                            TableColumn("标签3", value: \.tag3)
                        }
                        .frame(minHeight: 160)
                    } label: {
                        Label("标签库预览", systemImage: "tag")
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
        }
    }

    private func dashboardCard(icon: String, title: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.quaternary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var importExportSection: some View {
        VStack(spacing: 1) {
            ioRow(icon: "film.stack", iconColor: .orange, title: "视频库",
                  importAction: { importWorkbook(kind: .video) },
                  exportAction: { exportWorkbook(kind: .video) })
            ioRow(icon: "tag.fill", iconColor: .green, title: "标签库",
                  importAction: { importWorkbook(kind: .tag) },
                  exportAction: { exportWorkbook(kind: .tag) })
            ioRow(icon: "text.quote", iconColor: .blue, title: "标题库",
                  importAction: { importWorkbook(kind: .title) },
                  exportAction: { exportWorkbook(kind: .title) })
            ioRow(icon: "checklist", iconColor: .pink, title: "任务单",
                  importAction: nil,
                  exportAction: appState.taskRecords.isEmpty ? nil : { exportWorkbook(kind: .task) })
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.separator, lineWidth: 0.5))
    }

    private func ioRow(icon: String, iconColor: Color, title: String, importAction: (() -> Void)?, exportAction: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            if let importAction {
                Button("导入", systemImage: "square.and.arrow.down") { importAction() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if let exportAction {
                Button("导出", systemImage: "square.and.arrow.up") { exportAction() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background)
    }

    // MARK: - Title Generation

    private var titleGenerationView: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("标题生成")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 6) {
                        Label("生成 Prompt", systemImage: "text.bubble")
                            .font(.subheadline.weight(.medium))
                        TextEditor(text: $appState.titleSettings.generationPrompt)
                            .font(.body)
                            .frame(minHeight: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("打分 Prompt", systemImage: "star.bubble")
                            .font(.subheadline.weight(.medium))
                        TextEditor(text: $appState.titleSettings.scoringPrompt)
                            .font(.body)
                            .frame(minHeight: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                    }

                    Stepper("生成数量：\(appState.titleSettings.count)", value: $appState.titleSettings.count, in: 1...50)

                    DisclosureGroup(isExpanded: $isTitleModelSettingsExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("模型提供方", selection: $appState.titleSettings.provider) {
                                ForEach(TitleProviderPreset.allCases) { p in
                                    Text(p.displayName).tag(p)
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
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 8)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("模型设置")
                                    .font(.subheadline.weight(.medium))
                                Text("\(appState.titleSettings.provider.displayName) · \(appState.titleSettings.model.isEmpty ? "未设置" : appState.titleSettings.model)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "cpu")
                        }
                    }

                    Button {
                        Task { await appState.generateTitles() }
                    } label: {
                        HStack(spacing: 6) {
                            if appState.isGeneratingTitles {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(appState.isGeneratingTitles ? "生成中..." : "开始生成")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.isGeneratingTitles)

                    HStack {
                        Button("导入", systemImage: "square.and.arrow.down") { importWorkbook(kind: .title) }
                        Button("导出", systemImage: "square.and.arrow.up") { exportWorkbook(kind: .title) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Label("右键标题可编辑或删除，双击直接编辑", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
            }
            .frame(width: 340)
            .background(.background)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("标题库", systemImage: "text.quote")
                        .font(.headline)
                    Spacer()
                    Text("\(appState.titleRecords.count) 条")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                Table(appState.titleRecords, selection: $titleSelection) {
                    TableColumn("标题", value: \.title)
                    TableColumn("状态", value: \.useStatus)
                    TableColumn("次数") { r in Text("\(r.useCount)") }
                    TableColumn("爆款分") { r in
                        HStack(spacing: 4) {
                            Text("\(r.hotScore)")
                                .monospacedDigit()
                            if r.hotScore >= 80 {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    TableColumn("短标题", value: \.shortTitleWechat)
                }
                .contextMenu(forSelectionType: TitleRecord.ID.self) { ids in
                    titleContextMenuItems(for: ids)
                } primaryAction: { ids in
                    if let id = ids.first,
                       let r = appState.titleRecords.first(where: { $0.id == id }) {
                        activeSheet = .editTitle(r)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func titleContextMenuItems(for selectedIDs: Set<TitleRecord.ID>) -> some View {
        if let id = selectedIDs.first,
           let record = appState.titleRecords.first(where: { $0.id == id }) {
            Button("编辑", systemImage: "pencil") { activeSheet = .editTitle(record) }
        }
        if !selectedIDs.isEmpty {
            Divider()
            Button("删除所选 (\(selectedIDs.count))", systemImage: "trash", role: .destructive) {
                appState.titleRecords.removeAll { selectedIDs.contains($0.id) }
                titleSelection = []
            }
        }
    }

    // MARK: - Task Generation

    private var taskGenerationView: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("任务单")
                        .font(.title2.bold())

                    DatePicker("任务日期", selection: $appState.taskSettings.targetDate, displayedComponents: .date)

                    LabeledContent("视频状态") {
                        TextField("", text: $appState.taskSettings.allowedVideoStatus)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    LabeledContent("标题状态") {
                        TextField("", text: $appState.taskSettings.titleStatus)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("视频筛选").font(.subheadline.weight(.medium))
                        Picker("", selection: $appState.taskSettings.popularFilter) {
                            ForEach(PopularFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("标题筛选").font(.subheadline.weight(.medium))
                        Picker("", selection: $appState.taskSettings.titleFilterMode) {
                            ForEach(TitleFilterMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Stepper("爆款分阈值：\(appState.taskSettings.scoreThreshold)", value: $appState.taskSettings.scoreThreshold, in: 0...100)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("平台计划").font(.subheadline.weight(.medium))
                        ForEach(Array(appState.taskSettings.platformPlans.enumerated()), id: \.element.id) { index, _ in
                            HStack(spacing: 6) {
                                TextField("平台", text: $appState.taskSettings.platformPlans[index].platform)
                                TextField("账号", text: $appState.taskSettings.platformPlans[index].accountName)
                                TextField("原创", text: $appState.taskSettings.platformPlans[index].markOriginal)
                                    .frame(width: 40)
                                Button(role: .destructive) {
                                    appState.taskSettings.platformPlans.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .disabled(appState.taskSettings.platformPlans.count <= 1)
                            }
                            .textFieldStyle(.roundedBorder)
                        }
                        Button("添加平台", systemImage: "plus.circle") {
                            appState.taskSettings.platformPlans.append(
                                PlatformPlan(platform: "douyin", accountName: "新账号", markOriginal: "是")
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    GenerationFlowView(settings: appState.taskSettings)

                    Button {
                        appState.generateTasks()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text(appState.isGeneratingTasks ? "生成中..." : "生成任务单")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.isGeneratingTasks)

                    Button("导出任务单", systemImage: "square.and.arrow.up") { exportWorkbook(kind: .task) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(appState.taskRecords.isEmpty)

                    Label("右键任务可编辑或删除，双击直接编辑", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
            }
            .frame(width: 380)
            .background(.background)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("任务单", systemImage: "list.clipboard")
                        .font(.headline)
                    Spacer()
                    Text("\(appState.taskRecords.count) 条")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                Table(appState.taskRecords, selection: $taskSelection) {
                    TableColumn("ID", value: \.taskID)
                    TableColumn("平台", value: \.publishPlatform)
                    TableColumn("账号", value: \.accountName)
                    TableColumn("款式", value: \.skuStyleName)
                    TableColumn("标题", value: \.title)
                    TableColumn("短标题", value: \.shortTitleWechat)
                    TableColumn("看后搜", value: \.blueSearchTermDouyin)
                    TableColumn("发布时间", value: \.scheduledTime)
                    TableColumn("状态", value: \.taskStatus)
                }
                .contextMenu(forSelectionType: TaskRecord.ID.self) { ids in
                    taskContextMenuItems(for: ids)
                } primaryAction: { ids in
                    if let id = ids.first,
                       let r = appState.taskRecords.first(where: { $0.id == id }) {
                        activeSheet = .editTask(r)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskContextMenuItems(for selectedIDs: Set<TaskRecord.ID>) -> some View {
        if let id = selectedIDs.first,
           let record = appState.taskRecords.first(where: { $0.id == id }) {
            Button("编辑", systemImage: "pencil") { activeSheet = .editTask(record) }
        }
        if !selectedIDs.isEmpty {
            Divider()
            Button("删除所选 (\(selectedIDs.count))", systemImage: "trash", role: .destructive) {
                appState.taskRecords.removeAll { selectedIDs.contains($0.id) }
                taskSelection = []
            }
        }
    }

    // MARK: - File I/O

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
            case .video: try appState.importVideoLibrary(from: url)
            case .tag:   try appState.importTagLibrary(from: url)
            case .title: try appState.importTitleLibrary(from: url)
            case .task:  break
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
            case .video: try appState.exportVideoLibrary(to: url)
            case .tag:   try appState.exportTagLibrary(to: url)
            case .title: try appState.exportTitleLibrary(to: url)
            case .task:  try appState.exportTaskSheet(to: url)
            }
        } catch {
            appState.statusMessage = error.localizedDescription
        }
    }

    private func defaultFileName(for kind: WorkbookKind) -> String {
        switch kind {
        case .video: "video_library.xlsx"
        case .tag:   "tag_library.xlsx"
        case .title: "title_library.xlsx"
        case .task:  "tasks_\(TaskGenerationService.isoDateString(from: appState.taskSettings.targetDate)).xlsx"
        }
    }
}

// MARK: - Supporting Types

private enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "数据总览"
    case titleGeneration = "标题生成"
    case taskGeneration = "任务单"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .titleGeneration: "sparkles"
        case .taskGeneration: "list.clipboard"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard: .blue
        case .titleGeneration: .purple
        case .taskGeneration: .orange
        }
    }
}

private enum WorkbookKind { case video, tag, title, task }
private enum LibraryDetailKind: String { case video, tag, title, task }

private enum ActiveSheet: Identifiable {
    case libraryDetail(LibraryDetailKind)
    case editTitle(TitleRecord)
    case editTask(TaskRecord)

    var id: String {
        switch self {
        case .libraryDetail(let k): "detail-\(k.rawValue)"
        case .editTitle(let r):     "editTitle-\(r.id)"
        case .editTask(let r):      "editTask-\(r.id)"
        }
    }
}

// MARK: - Library Detail Sheet

private struct LibraryDetailView: View {
    let kind: LibraryDetailKind
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(sheetTitle, systemImage: sheetIcon)
                    .font(.title3.bold())
                Text("\(recordCount) 条")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.1), in: Capsule())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()
            tableContent
        }
        .frame(minWidth: 900, minHeight: 500)
    }

    private var sheetTitle: String {
        switch kind {
        case .video: "视频库"
        case .tag:   "标签库"
        case .title: "标题库"
        case .task:  "任务单"
        }
    }

    private var sheetIcon: String {
        switch kind {
        case .video: "film.stack"
        case .tag:   "tag.fill"
        case .title: "text.quote"
        case .task:  "checklist"
        }
    }

    private var recordCount: Int {
        switch kind {
        case .video: appState.videoRecords.count
        case .tag:   appState.tagRecords.count
        case .title: appState.titleRecords.count
        case .task:  appState.taskRecords.count
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
                TableColumn("看后搜", value: \.blueSearchTerm)
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
                TableColumn("短标题", value: \.shortTitleWechat)
            }
        case .task:
            Table(appState.taskRecords) {
                TableColumn("任务ID", value: \.taskID)
                TableColumn("平台", value: \.publishPlatform)
                TableColumn("账号", value: \.accountName)
                TableColumn("款式", value: \.skuStyleName)
                TableColumn("标题", value: \.title)
                TableColumn("短标题", value: \.shortTitleWechat)
                TableColumn("看后搜", value: \.blueSearchTermDouyin)
                TableColumn("发布时间", value: \.scheduledTime)
                TableColumn("状态", value: \.taskStatus)
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
        VStack(spacing: 0) {
            HStack {
                Label("编辑标题", systemImage: "pencil")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            Form {
                TextField("标题", text: $draft.title, axis: .vertical)
                    .lineLimit(2...4)
                TextField("使用状态", text: $draft.useStatus)
                Stepper("使用次数：\(draft.useCount)", value: $draft.useCount, in: 0...9999)
                LabeledContent("爆款分") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(draft.hotScore) },
                            set: { draft.hotScore = Int($0) }
                        ), in: 0...100, step: 1)
                        Text("\(draft.hotScore)")
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                            .foregroundStyle(draft.hotScore >= 80 ? .orange : .secondary)
                    }
                }
                TextField("短标题（视频号）", text: $draft.shortTitleWechat)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { onSave(draft); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 500)
    }
}

// MARK: - Task Edit Sheet

private struct TaskEditSheet: View {
    @State var draft: TaskRecord
    let onSave: (TaskRecord) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("编辑任务 \(draft.taskID)", systemImage: "pencil")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            Form {
                Section("调度") {
                    TextField("账号名称", text: $draft.accountName)
                    TextField("定时发布时间", text: $draft.scheduledTime)
                    TextField("任务状态", text: $draft.taskStatus)
                }
                Section("内容") {
                    TextField("标题", text: $draft.title, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("短标题（视频号）", text: $draft.shortTitleWechat)
                    TextField("标签1", text: $draft.tag1)
                    TextField("标签2", text: $draft.tag2)
                    TextField("标签3", text: $draft.tag3)
                    TextField("标签4", text: $draft.tag4)
                    TextField("标签5", text: $draft.tag5)
                }
                Section("平台字段") {
                    TextField("小黄车标题（抖音）", text: $draft.yellowCartTitleDouyin)
                    TextField("看后搜小蓝词", text: $draft.blueSearchTermDouyin)
                    TextField("位置信息", text: $draft.location)
                    TextField("标记原创", text: $draft.markOriginal)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { onSave(draft); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 560, height: 620)
    }
}

// MARK: - Generation Flow View

private struct GenerationFlowView: View {
    let settings: TaskGenerationSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            flowStep(n: 1, title: "视频筛选", detail: "日期 + 状态 + 热门款")
            flowStep(n: 2, title: "标题匹配", detail: "\(settings.titleFilterMode.rawValue)，阈值 \(settings.scoreThreshold)")
            flowStep(n: 3, title: "标签匹配", detail: "按 SKU 编码")
            flowStep(n: 4, title: "平台展开", detail: settings.platformPlans.map(\.platform).joined(separator: " / "))
            flowStep(n: 5, title: "回写状态", detail: "视频→已生成，标题次数+1", isLast: true)
        }
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func flowStep(n: Int, title: String, detail: String, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(n)")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 2, height: 20)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.bottom, isLast ? 0 : 4)
        }
    }
}

private extension UTType {
    static let spreadsheet = UTType(filenameExtension: "xlsx") ?? .data
}
