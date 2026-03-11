import Foundation

@MainActor
final class AppState: ObservableObject {
    private static let updateRepoOwnerDefaultsKey = "update.repoOwner"
    private static let updateRepoNameDefaultsKey = "update.repoName"
    private var hasPerformedInitialUpdateCheck = false

    @Published var titleRecords: [TitleRecord] = []
    @Published var tagRecords: [TagRecord] = []
    @Published var videoRecords: [VideoRecord] = []
    @Published var taskRecords: [TaskRecord] = []

    @Published var titleSettings = TitleGenerationSettings()
    @Published var taskSettings = TaskGenerationSettings()
    @Published var updateSettings: UpdateSettings {
        didSet { persistUpdateSettings() }
    }

    @Published var latestRelease: ReleaseInfo?
    @Published var currentVersion: String
    @Published var statusMessage = "准备就绪"
    @Published var updateStatusMessage = "应用已绑定官方 GitHub Release，可直接检查更新"
    @Published var isGeneratingTitles = false
    @Published var isCheckingUpdate = false
    @Published var isInstallingUpdate = false

    init() {
        updateSettings = Self.loadPersistedUpdateSettings()
        currentVersion = UpdateService.currentVersionDisplay()
        updateStatusMessage = "更新源：\(updateSettings.trimmedOwner)/\(updateSettings.trimmedRepoName)"
        loadBuiltInSamples()
    }

    func loadBuiltInSamples() {
        videoRecords = [
            VideoRecord(videoFileName: "thermos_commute_01.mp4", videoPath: "/Users/indincys/Videos/demo/thermos_commute_01.mp4", coverPath: "/Users/indincys/Pictures/demo/thermos_commute_01.jpg", skuCode: "SKU-THERMOS-001", skuStyle: "晨雾白保温杯", useStatus: "待发布", publishDate: TaskGenerationService.isoDateString(from: taskSettings.targetDate), publishTime: "09:30", yellowCartTitle: "316不锈钢保温杯", blueSearchTerm: "保温杯", locationWechat: "上海", popularFlag: "是"),
            VideoRecord(videoFileName: "thermos_office_02.mp4", videoPath: "/Users/indincys/Videos/demo/thermos_office_02.mp4", coverPath: "/Users/indincys/Pictures/demo/thermos_office_02.jpg", skuCode: "SKU-THERMOS-001", skuStyle: "晨雾白保温杯", useStatus: "待发布", publishDate: TaskGenerationService.isoDateString(from: taskSettings.targetDate), publishTime: "12:00", yellowCartTitle: "通勤保温杯", blueSearchTerm: "通勤杯", locationWechat: "上海", popularFlag: "否"),
            VideoRecord(videoFileName: "eyemask_break_01.mp4", videoPath: "/Users/indincys/Videos/demo/eyemask_break_01.mp4", coverPath: "/Users/indincys/Pictures/demo/eyemask_break_01.jpg", skuCode: "SKU-EYEMASK-002", skuStyle: "薰衣草蒸汽眼罩", useStatus: "待发布", publishDate: TaskGenerationService.isoDateString(from: taskSettings.targetDate), publishTime: "15:00", yellowCartTitle: "蒸汽眼罩", blueSearchTerm: "护眼", locationWechat: "杭州", popularFlag: "是"),
        ]

        tagRecords = [
            TagRecord(skuCode: "SKU-THERMOS-001", skuStyleName: "晨雾白保温杯", tag1: "#保温杯", tag2: "#通勤好物", tag3: "#办公室好物", tag4: "#上班族必备", tag5: "#实用好物"),
            TagRecord(skuCode: "SKU-EYEMASK-002", skuStyleName: "薰衣草蒸汽眼罩", tag1: "#蒸汽眼罩", tag2: "#睡前放松", tag3: "#护眼好物", tag4: "#午休好物", tag5: "#熬夜党"),
        ]

        titleRecords = [
            TitleRecord(title: "这条别滑走，这款真的越用越顺手", useStatus: "可用", useCount: 0, hotScore: 89, shortTitleWechat: "这款越用越顺手"),
            TitleRecord(title: "如果只留一款，我会先留它", useStatus: "可用", useCount: 0, hotScore: 83, shortTitleWechat: "如果只留一款"),
            TitleRecord(title: "别乱选，这种细节更省心", useStatus: "可用", useCount: 0, hotScore: 86, shortTitleWechat: "这种细节更省心"),
        ]

        statusMessage = "已加载内置样本"
    }

    func loadRepositorySamplesIfAvailable() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        do {
            try importVideoLibrary(from: root.appendingPathComponent("data/video_library.xlsx"))
            try importTagLibrary(from: root.appendingPathComponent("data/tag_library.xlsx"))
            try importTitleLibrary(from: root.appendingPathComponent("data/title_library.xlsx"))
            statusMessage = "已载入仓库里的样本 Excel"
        } catch {
            statusMessage = "未找到仓库样本，已保留内置样本"
        }
    }

    func generateTitles() async {
        isGeneratingTitles = true
        defer { isGeneratingTitles = false }
        statusMessage = "正在按 Prompt 生成标题并串行打分..."

        do {
            titleRecords = try await TitleGenerationService.generateTitles(settings: titleSettings)
            statusMessage = "已生成 \(titleRecords.count) 条标题，并完成串行打分"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func generateTasks() {
        var mutableVideos = videoRecords
        var mutableTitles = titleRecords
        taskRecords = TaskGenerationService.generateTasks(
            videos: &mutableVideos,
            titles: &mutableTitles,
            tags: tagRecords,
            settings: taskSettings
        )
        videoRecords = mutableVideos
        titleRecords = mutableTitles
        statusMessage = "已生成 \(taskRecords.count) 条任务"
    }

    func checkForUpdate() async {
        guard updateSettings.hasRepository else {
            let message = UpdateServiceError.missingRepository.localizedDescription
            statusMessage = message
            updateStatusMessage = message
            return
        }

        isCheckingUpdate = true
        updateStatusMessage = "正在检查 GitHub Releases..."
        defer { isCheckingUpdate = false }
        do {
            latestRelease = try await UpdateService.checkForLatestRelease(settings: updateSettings)
            if let latestRelease {
                if UpdateService.canInstall(release: latestRelease, currentVersion: currentVersion) {
                    let message = "发现新版本 \(latestRelease.version)，可直接下载安装"
                    statusMessage = message
                    updateStatusMessage = message
                } else if latestRelease.downloadURL == nil {
                    let message = "已获取最新发布 \(latestRelease.version)，但没有可安装的 .zip 包"
                    statusMessage = message
                    updateStatusMessage = message
                } else {
                    let message = "当前已是最新版本 \(currentVersion)"
                    statusMessage = message
                    updateStatusMessage = message
                }
            }
        } catch {
            statusMessage = error.localizedDescription
            updateStatusMessage = error.localizedDescription
        }
    }

    func performInitialUpdateCheckIfNeeded() async {
        guard !hasPerformedInitialUpdateCheck else { return }
        hasPerformedInitialUpdateCheck = true
        guard updateSettings.hasRepository else { return }
        await checkForUpdate()
    }

    func restoreOfficialUpdateRepository() {
        updateSettings = .official
        latestRelease = nil
        let message = "已恢复官方更新源：\(updateSettings.trimmedOwner)/\(updateSettings.trimmedRepoName)"
        statusMessage = message
        updateStatusMessage = message
    }

    func installLatestRelease() async {
        guard let latestRelease else {
            let message = "请先检查更新"
            statusMessage = message
            updateStatusMessage = message
            return
        }

        isInstallingUpdate = true
        let message = "正在下载并准备安装 \(latestRelease.version)..."
        statusMessage = message
        updateStatusMessage = message

        do {
            let targetURL = try await UpdateService.installRelease(latestRelease)
            let displayPath = targetURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            let installMessage = "安装包已准备完成，应用将自动重启并安装到 \(displayPath)"
            statusMessage = installMessage
            updateStatusMessage = installMessage
        } catch {
            isInstallingUpdate = false
            statusMessage = error.localizedDescription
            updateStatusMessage = error.localizedDescription
        }
    }

    func importTitleLibrary(from url: URL) throws {
        let rows = try XlsxService.readRows(from: url, sheetName: WorkbookSheetName.title)
        titleRecords = mapRows(rows).compactMap { row in
            TitleRecord(
                title: row[WorkbookColumn.title] ?? "",
                useStatus: row[WorkbookColumn.useStatus] ?? "",
                useCount: Int(row[WorkbookColumn.useCount] ?? "0") ?? 0,
                hotScore: Int(row[WorkbookColumn.hotScore] ?? "0") ?? 0,
                shortTitleWechat: row[WorkbookColumn.shortTitleWechat] ?? ""
            )
        }
        statusMessage = "已导入标题库"
    }

    func exportTitleLibrary(to url: URL) throws {
        let sheets = [
            WorkbookSheet(name: WorkbookSheetName.title, rows: [titleHeaders] + titleRecords.map(\.workbookRow)),
            WorkbookSheet(name: WorkbookSheetName.summary, rows: [
                [WorkbookColumn.summaryKey, WorkbookColumn.summaryValue],
                ["标题数量", "\(titleRecords.count)"],
            ]),
        ]
        try XlsxService.writeWorkbook(to: url, sheets: sheets)
        statusMessage = "已导出标题库"
    }

    func importTagLibrary(from url: URL) throws {
        let rows = try XlsxService.readRows(from: url, sheetName: WorkbookSheetName.tag)
        tagRecords = mapRows(rows).compactMap { row in
            TagRecord(
                skuCode: row[WorkbookColumn.skuCode] ?? "",
                skuStyleName: row[WorkbookColumn.skuStyleName] ?? "",
                tag1: row[WorkbookColumn.tag1] ?? "",
                tag2: row[WorkbookColumn.tag2] ?? "",
                tag3: row[WorkbookColumn.tag3] ?? "",
                tag4: row[WorkbookColumn.tag4] ?? "",
                tag5: row[WorkbookColumn.tag5] ?? ""
            )
        }
        statusMessage = "已导入标签库"
    }

    func exportTagLibrary(to url: URL) throws {
        let sheets = [WorkbookSheet(name: WorkbookSheetName.tag, rows: [tagHeaders] + tagRecords.map(\.workbookRow))]
        try XlsxService.writeWorkbook(to: url, sheets: sheets)
        statusMessage = "已导出标签库"
    }

    func importVideoLibrary(from url: URL) throws {
        let rows = try XlsxService.readRows(from: url, sheetName: WorkbookSheetName.video)
        videoRecords = mapRows(rows).compactMap { row in
            VideoRecord(
                videoFileName: row[WorkbookColumn.videoFileName] ?? "",
                videoPath: row[WorkbookColumn.videoPath] ?? "",
                coverPath: row[WorkbookColumn.coverPath] ?? "",
                skuCode: row[WorkbookColumn.skuCode] ?? "",
                skuStyle: row[WorkbookColumn.skuStyle] ?? "",
                useStatus: row[WorkbookColumn.useStatus] ?? "",
                publishDate: row[WorkbookColumn.publishDate] ?? "",
                publishTime: row[WorkbookColumn.publishTime] ?? "",
                yellowCartTitle: row[WorkbookColumn.yellowCartTitle] ?? "",
                blueSearchTerm: row[WorkbookColumn.blueSearchTerm] ?? "",
                locationWechat: row[WorkbookColumn.locationWechat] ?? "",
                popularFlag: row[WorkbookColumn.popularFlag] ?? ""
            )
        }
        statusMessage = "已导入视频库"
    }

    func exportVideoLibrary(to url: URL) throws {
        let sheets = [WorkbookSheet(name: WorkbookSheetName.video, rows: [videoHeaders] + videoRecords.map(\.workbookRow))]
        try XlsxService.writeWorkbook(to: url, sheets: sheets)
        statusMessage = "已导出视频库"
    }

    func exportTaskSheet(to url: URL) throws {
        let sheets = [
            WorkbookSheet(name: WorkbookSheetName.task, rows: [taskHeaders] + taskRecords.map(\.workbookRow)),
            WorkbookSheet(name: WorkbookSheetName.summary, rows: TaskGenerationService.summaryRows(for: taskRecords, settings: taskSettings)),
        ]
        try XlsxService.writeWorkbook(to: url, sheets: sheets)
        statusMessage = "已导出任务单"
    }

    private func mapRows(_ rows: [[String]]) -> [[String: String]] {
        guard let headers = rows.first else { return [] }
        return rows.dropFirst().map { row in
            var mapping: [String: String] = [:]
            for (index, header) in headers.enumerated() where index < row.count {
                mapping[header] = row[index]
            }
            return mapping
        }
    }

    private func persistUpdateSettings() {
        let defaults = UserDefaults.standard
        defaults.set(updateSettings.trimmedOwner, forKey: Self.updateRepoOwnerDefaultsKey)
        defaults.set(updateSettings.trimmedRepoName, forKey: Self.updateRepoNameDefaultsKey)
    }

    private static func loadPersistedUpdateSettings() -> UpdateSettings {
        let defaults = UserDefaults.standard
        let owner = defaults.string(forKey: updateRepoOwnerDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let repo = defaults.string(forKey: updateRepoNameDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !owner.isEmpty, !repo.isEmpty else {
            return .official
        }

        return UpdateSettings(repoOwner: owner, repoName: repo)
    }
}
