import AppKit
import Foundation

enum UpdateServiceError: LocalizedError {
    case missingRepository
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingRepository:
            return "请先填写 GitHub 仓库 owner 和 repo"
        case .invalidResponse:
            return "更新接口返回格式无效"
        }
    }
}

enum UpdateService {
    static func checkForLatestRelease(settings: UpdateSettings) async throws -> ReleaseInfo {
        let owner = settings.repoOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = settings.repoName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repo.isEmpty else {
            throw UpdateServiceError.missingRepository
        }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw UpdateServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw UpdateServiceError.invalidResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let pageURL = URL(string: release.htmlURL) else {
            throw UpdateServiceError.invalidResponse
        }
        let downloadURL = release.assets.first.flatMap { URL(string: $0.browserDownloadURL) }
        return ReleaseInfo(version: release.tagName, pageURL: pageURL, downloadURL: downloadURL)
    }

    static func openRelease(_ release: ReleaseInfo) {
        NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
    }
}

private struct GitHubRelease: Codable {
    struct Asset: Codable {
        var browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case browserDownloadURL = "browser_download_url"
        }
    }

    var tagName: String
    var htmlURL: String
    var assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}
