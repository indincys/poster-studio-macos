import Foundation

enum TitleGenerationError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "标题生成返回格式无效"
        }
    }
}

enum TitleGenerationService {
    private static let allowedSpecials = "《》“”：:+?%℃"
    private static let hotWords = ["必备", "别错过", "闭眼入", "回购", "一定要", "实测", "真香", "省心", "推荐"]

    static func generateTitles(settings: TitleGenerationSettings) async throws -> [TitleRecord] {
        let requestedCount = max(settings.count, 1)
        let generatedTitles = await generateTitleStrings(settings: settings, requestedCount: requestedCount)
        let normalizedTitles = completedTitles(from: generatedTitles, settings: settings, requestedCount: requestedCount)

        let scoreMap: [String: Int]
        if settings.hasRemoteConfiguration, !normalizedTitles.isEmpty {
            scoreMap = (try? await requestAITitleScores(settings: settings, titles: normalizedTitles)) ?? [:]
        } else {
            scoreMap = [:]
        }

        return normalizedTitles.enumerated().map { index, title in
            let normalized = normalizeTitle(title)
            let score = scoreMap[normalized] ?? estimateHotScore(title: normalized, orderIndex: index)
            return TitleRecord(
                title: normalized,
                useStatus: "可用",
                useCount: 0,
                hotScore: min(100, max(0, score)),
                shortTitleWechat: buildShortTitle(from: normalized)
            )
        }
    }

    static func buildShortTitle(from title: String) -> String {
        var text = title.replacingOccurrences(of: "，", with: " ").replacingOccurrences(of: ",", with: " ")
        let allowed = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: allowedSpecials))
            .union(CharacterSet(charactersIn: "\u{4e00}"..."\u{9fff}"))

        text = String(text.unicodeScalars.filter { allowed.contains($0) })
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        if text.count > 16 {
            text = String(text.prefix(16)).trimmingCharacters(in: .whitespaces)
        }

        if text.count >= 6 {
            return text
        }

        let compact = text.replacingOccurrences(of: " ", with: "")
        return String(compact.prefix(16))
    }

    static func fallbackTitles(prompt: String, count: Int) -> [String] {
        let topic = fallbackTopic(from: prompt)
        let templates = [
            "\(topic)真的越用越顺手",
            "这条别滑走，\(topic)我想认真推荐",
            "\(topic)别乱选，这种更省心",
            "\(topic)用下来最想夸的是这点",
            "最近反复回购的\(topic)",
            "\(topic)实测后，我更愿意留这款",
            "\(topic)做得对不对，看这几个细节",
            "如果只留一款\(topic)，我会选它",
            "\(topic)不一定最贵，但真的更好用",
            "\(topic)为什么容易出单，这条说清楚",
            "\(topic)闭眼入之前，先看这一条",
            "\(topic)适不适合你，看完就知道",
        ]

        return (0..<max(count, 1)).map { templates[$0 % templates.count] }
    }

    static func estimateHotScore(title: String, orderIndex: Int) -> Int {
        var score = 68 + max(0, 12 - orderIndex)
        score += hotWords.filter { title.contains($0) }.count * 3
        score += min(8, title.count / 4)
        return min(99, max(50, score))
    }

    private static func generateTitleStrings(settings: TitleGenerationSettings, requestedCount: Int) async -> [String] {
        if settings.hasRemoteConfiguration,
           let aiTitles = try? await requestAITitles(settings: settings),
           !aiTitles.isEmpty {
            return aiTitles
        }

        return fallbackTitles(prompt: settings.trimmedGenerationPrompt, count: requestedCount)
    }

    private static func completedTitles(from titles: [String], settings: TitleGenerationSettings, requestedCount: Int) -> [String] {
        var results: [String] = []
        var seen: Set<String> = []

        for title in titles {
            let normalized = normalizeTitle(title)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            results.append(normalized)
            if results.count >= requestedCount {
                return results
            }
        }

        for fallback in fallbackTitles(prompt: settings.trimmedGenerationPrompt, count: requestedCount * 2) {
            let normalized = normalizeTitle(fallback)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            results.append(normalized)
            if results.count >= requestedCount {
                break
            }
        }

        return results
    }

    private static func fallbackTopic(from prompt: String) -> String {
        let lines = prompt
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let firstLine = lines.first else {
            return "商品短视频标题"
        }

        let candidates = firstLine
            .components(separatedBy: CharacterSet(charactersIn: "：:;；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return candidates.last ?? firstLine
    }

    private static func normalizeTitle(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "^[0-9]+[.)、\\s-]*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "^[-*•]+\\s*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
    }

    private static func requestAITitles(settings: TitleGenerationSettings) async throws -> [String] {
        let prompt = settings.trimmedGenerationPrompt.isEmpty ? "请生成适合短视频带货场景的中文标题。" : settings.trimmedGenerationPrompt
        let content = try await requestChatCompletion(
            settings: settings,
            messages: [
                ChatMessage(role: "system", content: "你是中文短视频标题策划，只输出 JSON。"),
                ChatMessage(
                    role: "user",
                    content: """
                    以下是标题生成要求：
                    \(prompt)

                    请生成 \(settings.count) 条中文标题。
                    输出要求：
                    1. 只输出 JSON 数组。
                    2. 每个元素是字符串标题。
                    3. 不要附加解释、Markdown 或代码块说明。
                    """
                ),
            ],
            temperature: 0.85
        )

        return parseGeneratedTitles(content)
    }

    private static func requestAITitleScores(settings: TitleGenerationSettings, titles: [String]) async throws -> [String: Int] {
        let prompt = settings.trimmedScoringPrompt.isEmpty ? "请给每个标题打 0-100 的整数分。" : settings.trimmedScoringPrompt
        let titleList = titles.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let content = try await requestChatCompletion(
            settings: settings,
            messages: [
                ChatMessage(role: "system", content: "你是中文短视频标题评审，只输出 JSON。"),
                ChatMessage(
                    role: "user",
                    content: """
                    以下是标题打分要求：
                    \(prompt)

                    请对下面的标题逐条打 0-100 的整数分：
                    \(titleList)

                    输出要求：
                    1. 只输出 JSON 数组。
                    2. 每个元素都包含 title 和 hotScore。
                    3. title 必须保持与输入一致。
                    4. 不要附加解释、Markdown 或代码块说明。
                    """
                ),
            ],
            temperature: 0.2
        )

        return parseScoreMap(content)
    }

    private static func requestChatCompletion(
        settings: TitleGenerationSettings,
        messages: [ChatMessage],
        temperature: Double
    ) async throws -> String {
        guard let url = completionURL(from: settings.trimmedBaseURL) else {
            throw TitleGenerationError.invalidResponse
        }

        let requestBody = ChatCompletionRequest(
            model: settings.trimmedModel,
            messages: messages,
            temperature: temperature
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(settings.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw TitleGenerationError.invalidResponse
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content else {
            throw TitleGenerationError.invalidResponse
        }
        return content
    }

    private static func completionURL(from baseURL: String) -> URL? {
        let normalized = baseURL.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        return URL(string: normalized + "/chat/completions")
    }

    private static func parseGeneratedTitles(_ content: String) -> [String] {
        let normalizedContent = normalizedJSONContent(from: content)

        if let data = normalizedContent.data(using: .utf8) {
            if let payload = try? JSONDecoder().decode([String].self, from: data) {
                return payload.map(normalizeTitle).filter { !$0.isEmpty }
            }

            if let payload = try? JSONDecoder().decode([TitlePayload].self, from: data) {
                return payload.map(\.title).map(normalizeTitle).filter { !$0.isEmpty }
            }

            if let wrapped = try? JSONDecoder().decode(TitleArrayEnvelope.self, from: data) {
                return wrapped.titles.map(normalizeTitle).filter { !$0.isEmpty }
            }

            if let wrapped = try? JSONDecoder().decode(TitleObjectEnvelope.self, from: data) {
                return wrapped.titles.map(\.title).map(normalizeTitle).filter { !$0.isEmpty }
            }
        }

        return normalizedContent
            .split(whereSeparator: \.isNewline)
            .map { normalizeTitle(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func parseScoreMap(_ content: String) -> [String: Int] {
        let normalizedContent = normalizedJSONContent(from: content)
        var results: [String: Int] = [:]

        if let data = normalizedContent.data(using: .utf8) {
            if let payload = try? JSONDecoder().decode([TitlePayload].self, from: data) {
                payload.forEach { item in
                    if let hotScore = item.hotScore ?? item.score {
                        results[normalizeTitle(item.title)] = hotScore
                    }
                }
                return results
            }

            if let wrapped = try? JSONDecoder().decode(TitleObjectEnvelope.self, from: data) {
                wrapped.titles.forEach { item in
                    if let hotScore = item.hotScore ?? item.score {
                        results[normalizeTitle(item.title)] = hotScore
                    }
                }
                return results
            }

            if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                payload.forEach { pair in
                    if let score = pair.value as? Int {
                        results[normalizeTitle(pair.key)] = score
                    }
                }
                return results
            }
        }

        for line in normalizedContent.split(whereSeparator: \.isNewline) {
            let text = String(line)
            let parts = text.components(separatedBy: CharacterSet(charactersIn: "|：:")).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count >= 2, let score = Int(parts[1]) {
                results[normalizeTitle(parts[0])] = score
            }
        }
        return results
    }

    private static func normalizedJSONContent(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        let lines = trimmed.split(whereSeparator: \.isNewline)
        guard lines.count >= 3 else { return trimmed }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }
}

private struct TitlePayload: Codable {
    var title: String
    var hotScore: Int?
    var score: Int?
}

private struct TitleArrayEnvelope: Codable {
    var titles: [String]
}

private struct TitleObjectEnvelope: Codable {
    var titles: [TitlePayload]
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionRequest: Codable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
}

private struct ChatChoice: Codable {
    var message: ChatMessage
}

private struct ChatCompletionResponse: Codable {
    var choices: [ChatChoice]
}
