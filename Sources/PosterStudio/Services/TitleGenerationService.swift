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
        let rawTitles: [(String, Int?)]
        if !settings.apiKey.isEmpty, !settings.baseURL.isEmpty, !settings.model.isEmpty {
            do {
                rawTitles = try await requestAITitles(settings: settings)
            } catch {
                rawTitles = fallbackTitles(prompt: settings.prompt, count: settings.count).enumerated().map { index, title in
                    (title, estimateHotScore(title: title, orderIndex: index))
                }
            }
        } else {
            rawTitles = fallbackTitles(prompt: settings.prompt, count: settings.count).enumerated().map { index, title in
                (title, estimateHotScore(title: title, orderIndex: index))
            }
        }

        var results: [TitleRecord] = []
        var seen: Set<String> = []
        for (index, pair) in rawTitles.enumerated() {
            let normalized = normalizeTitle(pair.0)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)

            let score = pair.1 ?? estimateHotScore(title: normalized, orderIndex: index)
            results.append(
                TitleRecord(
                    title: normalized,
                    useStatus: "可用",
                    useCount: 0,
                    hotScore: min(100, max(0, score)),
                    shortTitleWechat: buildShortTitle(from: normalized)
                )
            )
            if results.count >= settings.count {
                break
            }
        }
        return results
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
        let topic = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "商品短视频标题" : prompt
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

    private static func normalizeTitle(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "^[0-9]+[.)、\\s-]*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
    }

    private static func requestAITitles(settings: TitleGenerationSettings) async throws -> [(String, Int?)] {
        guard let url = URL(string: settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) + "/chat/completions") else {
            throw TitleGenerationError.invalidResponse
        }

        let systemPrompt = "你是中文短视频标题策划。请输出 JSON 数组，每个元素包含 title 和可选 hotScore。"
        let userPrompt = "请围绕以下主题生成 \(settings.count) 条中文商品短视频标题，并尽量给出 0-100 的爆款分 hotScore：\n\(settings.prompt)\n只输出 JSON。"

        let requestBody = ChatCompletionRequest(
            model: settings.model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt),
            ],
            temperature: 0.8
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw TitleGenerationError.invalidResponse
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content else {
            throw TitleGenerationError.invalidResponse
        }
        return parsePayload(content)
    }

    private static func parsePayload(_ content: String) -> [(String, Int?)] {
        if let data = content.data(using: .utf8),
           let payload = try? JSONDecoder().decode([TitlePayload].self, from: data) {
            return payload.map { ($0.title, $0.hotScore) }
        }

        return content
            .split(whereSeparator: \.isNewline)
            .map { normalizeTitle(String($0)) }
            .filter { !$0.isEmpty }
            .map { ($0, nil) }
    }
}

private struct TitlePayload: Codable {
    var title: String
    var hotScore: Int?
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
