import Foundation

enum WorkbookSheetName {
    static let video = "视频库"
    static let tag = "标签库"
    static let title = "标题库"
    static let task = "任务单"
    static let summary = "汇总"
}

enum WorkbookColumn {
    static let videoFileName = "视频文件名"
    static let videoPath = "视频路径"
    static let coverPath = "封面路径"
    static let skuCode = "SKU编码"
    static let skuStyle = "SKU款式"
    static let skuStyleName = "SKU款式名"
    static let useStatus = "使用状态"
    static let publishDate = "发布日期"
    static let publishTime = "发布时间"
    static let scheduledTime = "定时发布时间"
    static let yellowCartTitle = "小黄车标题"
    static let yellowCartTitleDouyin = "小黄车标题（抖音）"
    static let blueSearchTerm = "看后搜小蓝词（抖音）"
    static let locationWechat = "位置信息（视频号）"
    static let location = "位置信息"
    static let popularFlag = "热门款"
    static let title = "标题"
    static let useCount = "使用次数"
    static let hotScore = "爆款分"
    static let shortTitleWechat = "短标题（视频号）"
    static let tag1 = "标签1"
    static let tag2 = "标签2"
    static let tag3 = "标签3"
    static let tag4 = "标签4"
    static let tag5 = "标签5"
    static let taskID = "任务ID"
    static let taskDate = "任务日期"
    static let publishPlatform = "发布平台"
    static let accountName = "账号名称"
    static let productName = "商品名称"
    static let markOriginal = "标记原创"
    static let taskStatus = "任务状态"
    static let summaryKey = "指标"
    static let summaryValue = "值"
}

let titleHeaders = [
    WorkbookColumn.title,
    WorkbookColumn.useStatus,
    WorkbookColumn.useCount,
    WorkbookColumn.hotScore,
    WorkbookColumn.shortTitleWechat,
]

let tagHeaders = [
    WorkbookColumn.skuCode,
    WorkbookColumn.skuStyleName,
    WorkbookColumn.tag1,
    WorkbookColumn.tag2,
    WorkbookColumn.tag3,
    WorkbookColumn.tag4,
    WorkbookColumn.tag5,
]

let videoHeaders = [
    WorkbookColumn.videoFileName,
    WorkbookColumn.videoPath,
    WorkbookColumn.coverPath,
    WorkbookColumn.skuCode,
    WorkbookColumn.skuStyle,
    WorkbookColumn.useStatus,
    WorkbookColumn.publishDate,
    WorkbookColumn.publishTime,
    WorkbookColumn.yellowCartTitle,
    WorkbookColumn.blueSearchTerm,
    WorkbookColumn.locationWechat,
    WorkbookColumn.popularFlag,
]

let taskHeaders = [
    WorkbookColumn.taskID,
    WorkbookColumn.taskDate,
    WorkbookColumn.scheduledTime,
    WorkbookColumn.publishPlatform,
    WorkbookColumn.accountName,
    WorkbookColumn.skuStyleName,
    WorkbookColumn.skuCode,
    WorkbookColumn.productName,
    WorkbookColumn.videoFileName,
    WorkbookColumn.videoPath,
    WorkbookColumn.coverPath,
    WorkbookColumn.title,
    WorkbookColumn.tag1,
    WorkbookColumn.tag2,
    WorkbookColumn.tag3,
    WorkbookColumn.tag4,
    WorkbookColumn.tag5,
    WorkbookColumn.markOriginal,
    WorkbookColumn.yellowCartTitleDouyin,
    WorkbookColumn.location,
    WorkbookColumn.taskStatus,
]

struct TitleRecord: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var useStatus: String
    var useCount: Int
    var hotScore: Int
    var shortTitleWechat: String

    var workbookRow: [String] {
        [
            title,
            useStatus,
            String(useCount),
            String(hotScore),
            shortTitleWechat,
        ]
    }
}

struct TagRecord: Identifiable, Hashable {
    let id = UUID()
    var skuCode: String
    var skuStyleName: String
    var tag1: String
    var tag2: String
    var tag3: String
    var tag4: String
    var tag5: String

    var workbookRow: [String] {
        [
            skuCode,
            skuStyleName,
            tag1,
            tag2,
            tag3,
            tag4,
            tag5,
        ]
    }
}

struct VideoRecord: Identifiable, Hashable {
    let id = UUID()
    var videoFileName: String
    var videoPath: String
    var coverPath: String
    var skuCode: String
    var skuStyle: String
    var useStatus: String
    var publishDate: String
    var publishTime: String
    var yellowCartTitle: String
    var blueSearchTerm: String
    var locationWechat: String
    var popularFlag: String

    var workbookRow: [String] {
        [
            videoFileName,
            videoPath,
            coverPath,
            skuCode,
            skuStyle,
            useStatus,
            publishDate,
            publishTime,
            yellowCartTitle,
            blueSearchTerm,
            locationWechat,
            popularFlag,
        ]
    }
}

struct TaskRecord: Identifiable, Hashable {
    let id = UUID()
    var taskID: String
    var taskDate: String
    var scheduledTime: String
    var publishPlatform: String
    var accountName: String
    var skuStyleName: String
    var skuCode: String
    var productName: String
    var videoFileName: String
    var videoPath: String
    var coverPath: String
    var title: String
    var tag1: String
    var tag2: String
    var tag3: String
    var tag4: String
    var tag5: String
    var markOriginal: String
    var yellowCartTitleDouyin: String
    var location: String
    var taskStatus: String

    var workbookRow: [String] {
        [
            taskID,
            taskDate,
            scheduledTime,
            publishPlatform,
            accountName,
            skuStyleName,
            skuCode,
            productName,
            videoFileName,
            videoPath,
            coverPath,
            title,
            tag1,
            tag2,
            tag3,
            tag4,
            tag5,
            markOriginal,
            yellowCartTitleDouyin,
            location,
            taskStatus,
        ]
    }
}

enum PopularFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case hot = "仅热门款"
    case normal = "仅普通款"

    var id: String { rawValue }
}

enum TitleFilterMode: String, CaseIterable, Identifiable {
    case all = "全部标题"
    case highScore = "高爆款分标题"
    case normalScore = "普通标题"

    var id: String { rawValue }
}

struct PlatformPlan: Identifiable, Hashable {
    let id = UUID()
    var platform: String
    var accountName: String
    var markOriginal: String
}

struct TitleGenerationSettings {
    var prompt: String = "多平台短视频带货标题"
    var count: Int = 12
    var apiKey: String = ""
    var baseURL: String = ""
    var model: String = ""
    var provider: String = "自定义兼容 OpenAI"
}

struct TaskGenerationSettings {
    var targetDate: Date = Date()
    var allowedVideoStatus: String = "待发布"
    var popularFilter: PopularFilter = .all
    var titleStatus: String = "可用"
    var titleFilterMode: TitleFilterMode = .highScore
    var scoreThreshold: Int = 80
    var platformPlans: [PlatformPlan] = [
        PlatformPlan(platform: "douyin", accountName: "抖音主号", markOriginal: "是"),
        PlatformPlan(platform: "shipinhao", accountName: "视频号主号", markOriginal: "是"),
    ]
}

struct UpdateSettings {
    static let officialRepoOwner = "indincys"
    static let officialRepoName = "poster-studio-macos"

    var repoOwner: String = UpdateSettings.officialRepoOwner
    var repoName: String = UpdateSettings.officialRepoName

    var trimmedOwner: String {
        repoOwner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRepoName: String {
        repoName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasRepository: Bool {
        !trimmedOwner.isEmpty && !trimmedRepoName.isEmpty
    }

    var releasesPageURL: URL? {
        guard hasRepository else { return nil }
        return URL(string: "https://github.com/\(trimmedOwner)/\(trimmedRepoName)/releases")
    }

    var normalizedOwner: String {
        trimmedOwner
    }

    var normalizedRepoName: String {
        trimmedRepoName
    }

    var isConfigured: Bool {
        hasRepository
    }

    var releasePageURL: URL? {
        releasesPageURL
    }

    static var official: UpdateSettings {
        UpdateSettings(repoOwner: officialRepoOwner, repoName: officialRepoName)
    }
}

struct ReleaseInfo: Hashable {
    var version: String
    var tagName: String
    var pageURL: URL
    var downloadURL: URL?
    var assetName: String?
    var publishedAt: Date?
}

struct UpdateCheckResult: Hashable {
    var latestRelease: ReleaseInfo
    var isUpdateAvailable: Bool
}
