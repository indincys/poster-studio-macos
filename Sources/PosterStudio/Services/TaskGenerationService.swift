import Foundation

enum TaskGenerationService {
    static func generateTasks(
        videos: inout [VideoRecord],
        titles: inout [TitleRecord],
        tags: [TagRecord],
        settings: TaskGenerationSettings
    ) -> [TaskRecord] {
        let targetDate = isoDateString(from: settings.targetDate)
        let filteredVideos = videos.indices.filter { index in
            let video = videos[index]
            guard video.publishDate == targetDate, video.useStatus == settings.allowedVideoStatus else {
                return false
            }

            switch settings.popularFilter {
            case .all:
                return true
            case .hot:
                return normalizeYesNo(video.popularFlag) == "是"
            case .normal:
                return normalizeYesNo(video.popularFlag) == "否"
            }
        }

        let filteredTitleIndexes = titleIndexes(for: titles, settings: settings)
        let tagMap = Dictionary(uniqueKeysWithValues: tags.map { ($0.skuCode, $0) })

        var tasks: [TaskRecord] = []
        var taskSequence = 1

        for videoIndex in filteredVideos {
            let video = videos[videoIndex]
            for plan in settings.platformPlans {
                let titleIndex = chooseTitleIndex(from: titles, candidateIndexes: filteredTitleIndexes)
                let title = titleIndex.flatMap { titles[$0] }

                if let titleIndex {
                    titles[titleIndex].useCount += 1
                }

                let tag = tagMap[video.skuCode]
                tasks.append(
                    TaskRecord(
                        taskID: String(format: "TASK-%04d", taskSequence),
                        taskDate: video.publishDate,
                        scheduledTime: video.publishTime,
                        publishPlatform: plan.platform,
                        accountName: plan.accountName,
                        skuStyleName: video.skuStyle,
                        skuCode: video.skuCode,
                        productName: video.skuStyle,
                        videoFileName: video.videoFileName,
                        videoPath: video.videoPath,
                        coverPath: video.coverPath,
                        title: title?.title ?? "",
                        tag1: tag?.tag1 ?? "",
                        tag2: tag?.tag2 ?? "",
                        tag3: tag?.tag3 ?? "",
                        tag4: tag?.tag4 ?? "",
                        tag5: tag?.tag5 ?? "",
                        markOriginal: plan.markOriginal,
                        yellowCartTitleDouyin: plan.platform == "douyin" ? video.yellowCartTitle : "",
                        location: plan.platform == "shipinhao" ? video.locationWechat : "",
                        taskStatus: "待执行"
                    )
                )
                taskSequence += 1
            }

            videos[videoIndex].useStatus = "已生成任务"
        }

        return tasks
    }

    static func titleIndexes(for titles: [TitleRecord], settings: TaskGenerationSettings) -> [Int] {
        let filtered = titles.indices.filter { index in
            let title = titles[index]
            guard title.useStatus == settings.titleStatus else { return false }
            switch settings.titleFilterMode {
            case .all:
                return true
            case .highScore:
                return title.hotScore >= settings.scoreThreshold
            case .normalScore:
                return title.hotScore < settings.scoreThreshold
            }
        }

        if !filtered.isEmpty {
            return filtered
        }

        return titles.indices.filter { titles[$0].useStatus == settings.titleStatus }
    }

    static func chooseTitleIndex(from titles: [TitleRecord], candidateIndexes: [Int]) -> Int? {
        candidateIndexes.min { lhs, rhs in
            let left = titles[lhs]
            let right = titles[rhs]
            if left.useCount != right.useCount {
                return left.useCount < right.useCount
            }
            if left.hotScore != right.hotScore {
                return left.hotScore > right.hotScore
            }
            return left.title < right.title
        }
    }

    static func summaryRows(for tasks: [TaskRecord], settings: TaskGenerationSettings) -> [[String]] {
        var counts: [String: Int] = [:]
        for task in tasks {
            counts[task.publishPlatform, default: 0] += 1
        }

        var rows: [[String]] = [
            [WorkbookColumn.summaryKey, WorkbookColumn.summaryValue],
            ["任务数量", "\(tasks.count)"],
            ["任务日期", isoDateString(from: settings.targetDate)],
            ["视频筛选", settings.popularFilter.rawValue],
            ["标题筛选", settings.titleFilterMode.rawValue],
        ]
        for key in counts.keys.sorted() {
            rows.append(["\(key)_任务数", "\(counts[key] ?? 0)"])
        }
        return rows
    }

    private static func normalizeYesNo(_ value: String) -> String {
        ["是", "yes", "true", "1"].contains(value.lowercased()) ? "是" : "否"
    }

    static func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
