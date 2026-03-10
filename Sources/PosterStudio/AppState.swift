import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var titleRecords: [TitleRecord] = []
    @Published var tagRecords: [TagRecord] = []
    @Published var videoRecords: [VideoRecord] = []
    @Published var taskRecords: [TaskRecord] = []

    @Published var titleSettings = TitleGenerationSettings()
    @Published var taskSettings = TaskGenerationSettings()
    @Published var updateSettings = UpdateSettings()

    @Published var latestRelease: ReleaseInfo?
    @Published var statusMessage = "准备就绪"
    @Published var isGeneratingTitles = false
    @Published var isCheckingUpdate = false

    init() {
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

        do {
            titleRecords = try await TitleGenerationService.generateTitles(settings: titleSettings)
            statusMessage = "已生成 \(titleRecords.count) 条标题"
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
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        do {
            latestRelease = try await UpdateService.checkForLatestRelease(settings: updateSettings)
            statusMessage = "已检查更新"
        } catch {
            statusMessage = error.localizedDescription
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
}
