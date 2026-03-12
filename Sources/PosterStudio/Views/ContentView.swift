import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var appState: AppState
    @State private var isTitleModelSettingsExpanded = false

    var body: some View {
        TabView {
            librariesTab
                .tabItem { Text("数据源") }

            titleGenerationTab
                .tabItem { Text("标题生成") }

            taskGenerationTab
                .tabItem { Text("任务单生成") }

            updateTab
                .tabItem { Text("更新") }
        }
        .padding(18)
        .frame(minWidth: 1180, minHeight: 780)
        .task {
            await appState.performInitialUpdateCheckIfNeeded()
        }
    }

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
            }

            HStack(spacing: 16) {
                summaryCard(title: "视频库", value: "\(appState.videoRecords.count) 条", color: .orange)
                summaryCard(title: "标签库", value: "\(appState.tagRecords.count) 条", color: .green)
                summaryCard(title: "标题库", value: "\(appState.titleRecords.count) 条", color: .blue)
                summaryCard(title: "任务单", value: "\(appState.taskRecords.count) 条", color: .pink)
            }

            HStack(spacing: 12) {
                Button("导入视频库") { importWorkbook(kind: .video) }
                Button("导出视频库") { exportWorkbook(kind: .video) }
                Button("导入标签库") { importWorkbook(kind: .tag) }
                Button("导出标签库") { exportWorkbook(kind: .tag) }
                Button("导入标题库") { importWorkbook(kind: .title) }
                Button("导出标题库") { exportWorkbook(kind: .title) }
                Button("导出任务单") { exportWorkbook(kind: .task) }
            }

            GroupBox("视频库预览") {
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

                    Text("执行顺序：先按“标题生成 Prompt”生成标题，再把生成结果串行传给“标题打分 Prompt”进行打分。短标题会按视频号规则自动裁切。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            .frame(width: 360)

            GroupBox("标题库预览") {
                Table(appState.titleRecords) {
                    TableColumn("标题", value: \.title)
                    TableColumn("使用状态", value: \.useStatus)
                    TableColumn("使用次数") { record in Text("\(record.useCount)") }
                    TableColumn("爆款分") { record in Text("\(record.hotScore)") }
                    TableColumn("短标题（视频号）", value: \.shortTitleWechat)
                }
            }
        }
    }

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

                    Text("左侧设置区已改为可滚动，平台计划较多时也能完整查看和编辑。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            .frame(width: 400)
            .frame(maxHeight: .infinity, alignment: .top)

            GroupBox("任务单预览") {
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

    private var updateTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GitHub 发布与更新")
                .font(.title3.bold())

            Text("应用默认指向官方 GitHub Releases，可直接检查最新版本、打开发布页，并下载 `.zip` 安装包自动替换当前应用。")
                .foregroundStyle(.secondary)

            HStack {
                TextField("GitHub Owner", text: $appState.updateSettings.repoOwner)
                TextField("Repo Name", text: $appState.updateSettings.repoName)
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button(appState.isCheckingUpdate ? "检查中..." : "手动检查更新") {
                    Task { await appState.checkForUpdate() }
                }
                .disabled(appState.isCheckingUpdate || appState.isInstallingUpdate || !appState.updateSettings.hasRepository)

                Button("恢复官方仓库") {
                    appState.restoreOfficialUpdateRepository()
                }
                .disabled(appState.isCheckingUpdate || appState.isInstallingUpdate)

                if let releasesPageURL = appState.updateSettings.releasesPageURL {
                    Link("打开 Releases 页面", destination: releasesPageURL)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("当前版本：\(appState.currentVersion)")
                Text(appState.updateStatusMessage)
                    .foregroundStyle(.secondary)
            }

            if let release = appState.latestRelease {
                GroupBox("最新发布") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("版本：\(release.version)")

                        if let assetName = release.assetName {
                            Text("安装包：\(assetName)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button(appState.isInstallingUpdate ? "安装中..." : "下载并安装更新") {
                                Task { await appState.installLatestRelease() }
                            }
                            .disabled(
                                appState.isCheckingUpdate ||
                                appState.isInstallingUpdate ||
                                !UpdateService.canInstall(release: release, currentVersion: appState.currentVersion)
                            )

                            Button("打开当前 Release") {
                                UpdateService.openReleasePage(release)
                            }
                        }

                        if !UpdateService.canInstall(release: release, currentVersion: appState.currentVersion) {
                            Text(release.downloadURL == nil ? "这个 release 缺少可安装的 `.zip` 资产。" : "当前已是最新版本，无需重复安装。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            GroupBox("发布要求") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 每次发版继续上传 arm64 的 `.app.zip` 到 GitHub Release。")
                    Text("2. 版本号要递增，例如 `v0.1.0`、`v0.1.1`。")
                    Text("3. 如果安装在 `/Applications`，更新时会请求系统授权后原位替换。")
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func summaryCard(title: String, value: String, color: Color) -> some View {
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

private enum WorkbookKind {
    case video
    case tag
    case title
    case task
}

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
