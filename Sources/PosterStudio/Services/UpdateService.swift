import AppKit
import Foundation

enum UpdateServiceError: LocalizedError {
    case missingRepository
    case httpError(Int, String)
    case decodingFailed(String)
    case missingInstallAsset
    case unsupportedInstallationTarget
    case downloadFailed
    case unpackFailed
    case installFailed
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRepository:
            return "请先填写 GitHub 仓库 owner 和 repo"
        case .httpError(let status, let detail):
            return "GitHub API 返回 HTTP \(status)：\(detail)"
        case .decodingFailed(let detail):
            return "解析 GitHub Release 失败：\(detail)"
        case .missingInstallAsset:
            return "最新 Release 没有可安装的 .zip 资产"
        case .unsupportedInstallationTarget:
            return "当前只支持从已安装的 .app 包内执行更新"
        case .downloadFailed:
            return "下载更新包失败"
        case .unpackFailed:
            return "解压更新包失败"
        case .installFailed:
            return "启动安装流程失败"
        case .processFailed(let message):
            return message
        }
    }
}

enum UpdateService {
    /// Cached ETag and response data to avoid hitting GitHub API rate limits.
    /// Conditional requests returning 304 do not count against the limit.
    nonisolated(unsafe) private static var cachedETag: String?
    nonisolated(unsafe) private static var cachedResponseData: Data?
    nonisolated(unsafe) private static var lastCheckTime: Date?
    private static let minimumCheckInterval: TimeInterval = 300 // 5 minutes

    static func currentVersionDisplay(bundle: Bundle = .main) -> String {
        normalizedVersion(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? normalizedVersion(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "开发版"
    }

    static func installedVersion(bundle: Bundle = .main) -> String {
        normalizedVersion(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? normalizedVersion(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "0.0.0"
    }

    static func checkForLatestRelease(settings: UpdateSettings) async throws -> ReleaseInfo {
        try await checkForLatestRelease(settings: settings, currentVersion: nil).latestRelease
    }

    static func checkForLatestRelease(settings: UpdateSettings, currentVersion: String? = nil) async throws -> UpdateCheckResult {
        let owner = settings.trimmedOwner
        let repo = settings.trimmedRepoName
        guard settings.hasRepository else {
            throw UpdateServiceError.missingRepository
        }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw UpdateServiceError.httpError(0, "无法构建 API URL")
        }

        // Cooldown: if checked recently and we have cached data, use it
        if let lastCheck = lastCheckTime, let cached = cachedResponseData,
           Date().timeIntervalSince(lastCheck) < minimumCheckInterval {
            let release = try decodeRelease(from: cached)
            return try buildResult(from: release, currentVersion: currentVersion)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PosterStudio/\(installedVersion())", forHTTPHeaderField: "User-Agent")
        // Send cached ETag for conditional request (304 doesn't count against rate limit)
        if let etag = cachedETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateServiceError.httpError(0, "无法获取 HTTP 响应")
        }

        lastCheckTime = Date()

        // 304 Not Modified — use cached data
        if httpResponse.statusCode == 304, let cached = cachedResponseData {
            let release = try decodeRelease(from: cached)
            return try buildResult(from: release, currentVersion: currentVersion)
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let detail: String
            if httpResponse.statusCode == 404 {
                detail = "仓库 \(owner)/\(repo) 不存在或没有 Release"
            } else if httpResponse.statusCode == 403 {
                detail = "API 速率限制，请稍后再试"
            } else {
                detail = body.prefix(200).description
            }
            throw UpdateServiceError.httpError(httpResponse.statusCode, detail)
        }

        // Cache the ETag and response data for future conditional requests
        if let etag = httpResponse.value(forHTTPHeaderField: "Etag") {
            cachedETag = etag
            cachedResponseData = data
        }

        let release = try decodeRelease(from: data)
        return try buildResult(from: release, currentVersion: currentVersion)
    }

    private static func decodeRelease(from data: Data) throws -> GitHubRelease {
        do {
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateServiceError.decodingFailed(error.localizedDescription)
        }
    }

    private static func buildResult(from release: GitHubRelease, currentVersion: String?) throws -> UpdateCheckResult {
        guard let pageURL = URL(string: release.htmlURL) else {
            throw UpdateServiceError.decodingFailed("html_url 无效")
        }

        let asset = installAsset(from: release.assets)
        let downloadURL = asset.flatMap { URL(string: $0.browserDownloadURL) }

        let latestRelease = ReleaseInfo(
            version: normalizedVersion(release.tagName) ?? release.tagName,
            tagName: release.tagName,
            pageURL: pageURL,
            downloadURL: downloadURL,
            assetName: asset?.name,
            publishedAt: release.publishedAt.flatMap(parsePublishedDate)
        )

        let installed = normalizedVersion(currentVersion) ?? installedVersion()
        return UpdateCheckResult(
            latestRelease: latestRelease,
            isUpdateAvailable: canInstall(release: latestRelease, currentVersion: installed)
        )
    }

    static func canInstall(release: ReleaseInfo, currentVersion: String) -> Bool {
        guard release.downloadURL != nil else { return false }
        guard let normalizedLatest = normalizedVersion(release.version) else { return false }
        guard let normalizedCurrent = normalizedVersion(currentVersion) else { return true }
        return normalizedLatest.compare(normalizedCurrent, options: [.numeric, .caseInsensitive]) == .orderedDescending
    }

    @discardableResult
    static func installRelease(_ release: ReleaseInfo) async throws -> URL {
        guard let targetAppURL = installedBundleURL() else {
            throw UpdateServiceError.unsupportedInstallationTarget
        }

        let preparedUpdate = try await prepareUpdate(release: release, targetAppURL: targetAppURL)

        do {
            try launchInstaller(preparedUpdate)
        } catch {
            throw UpdateServiceError.installFailed
        }

        // launchInstaller already triggers terminate — no duplicate call needed.
        return targetAppURL
    }

    static func openReleasePage(settings: UpdateSettings) {
        guard let url = settings.releasesPageURL else { return }
        openURL(url)
    }

    static func openReleasePage(_ release: ReleaseInfo) {
        openURL(release.pageURL)
    }

    static func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func installUpdate(_ release: ReleaseInfo) async throws {
        _ = try await installRelease(release)
    }

    private static func prepareUpdate(release: ReleaseInfo, targetAppURL: URL) async throws -> PreparedUpdate {
        guard let downloadURL = release.downloadURL else {
            throw UpdateServiceError.missingInstallAsset
        }

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let stagingRoot = fileManager.temporaryDirectory
                .appendingPathComponent("PosterStudioUpdate-\(UUID().uuidString)", isDirectory: true)
            let archiveName = release.assetName ?? "PosterStudio-update.zip"
            let archiveURL = stagingRoot.appendingPathComponent(archiveName)
            let unpackedDirectoryURL = stagingRoot.appendingPathComponent("unpacked", isDirectory: true)
            let installerScriptURL = stagingRoot.appendingPathComponent("install_update.sh")

            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(at: unpackedDirectoryURL, withIntermediateDirectories: true, attributes: nil)

            let (temporaryArchiveURL, response) = try await URLSession.shared.download(from: downloadURL)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                throw UpdateServiceError.downloadFailed
            }

            try fileManager.moveItem(at: temporaryArchiveURL, to: archiveURL)
            try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, unpackedDirectoryURL.path])

            guard let stagedAppURL = locateAppBundle(in: unpackedDirectoryURL) else {
                throw UpdateServiceError.unpackFailed
            }

            try installerScript().write(to: installerScriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installerScriptURL.path)

            return PreparedUpdate(
                targetAppURL: targetAppURL,
                stagedAppURL: stagedAppURL,
                stagingRootURL: stagingRoot,
                installerScriptURL: installerScriptURL
            )
        }.value
    }

    private static func launchInstaller(_ preparedUpdate: PreparedUpdate) throws {
        let process = Process()
        process.standardOutput = nil
        process.standardError = nil

        let arguments = [
            preparedUpdate.installerScriptURL.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            preparedUpdate.targetAppURL.path,
            preparedUpdate.stagedAppURL.path,
            preparedUpdate.stagingRootURL.path,
        ]

        if requiresAdministratorPrivileges(for: preparedUpdate.targetAppURL) {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            let shellCommand = (["/bin/zsh"] + arguments).map(shellQuote).joined(separator: " ")
            let appleScript = "do shell script \(appleScriptLiteral(shellCommand)) with administrator privileges"
            process.arguments = ["-e", appleScript]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = arguments
        }

        try process.run()

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private static func installedBundleURL(bundle: Bundle = .main) -> URL? {
        let bundleURL = bundle.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension == "app", FileManager.default.fileExists(atPath: bundleURL.path) else {
            return nil
        }
        return bundleURL
    }

    private static func installAsset(from assets: [GitHubRelease.Asset]) -> GitHubRelease.Asset? {
        let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "PosterStudio"
        return assets.first(where: { $0.name.hasSuffix(".zip") && $0.name.localizedCaseInsensitiveContains(appName) })
            ?? assets.first(where: { $0.name.hasSuffix(".zip") })
    }

    private static func parsePublishedDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func normalizedVersion(_ version: String?) -> String? {
        guard let version else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalizedVersion(lhs) ?? lhs
        let right = normalizedVersion(rhs) ?? rhs
        return left.compare(right, options: .numeric)
    }

    private static func locateAppBundle(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "app" {
            return fileURL
        }

        return nil
    }

    private static func runProcess(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "未知进程错误"
            throw UpdateServiceError.processFailed(message)
        }
    }

    private static func requiresAdministratorPrivileges(for targetAppURL: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: targetAppURL.path) {
            return !fileManager.isWritableFile(atPath: targetAppURL.path)
        }
        return !fileManager.isWritableFile(atPath: targetAppURL.deletingLastPathComponent().path)
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func installerScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        TARGET_PID="$1"
        TARGET_APP="$2"
        STAGED_APP="$3"
        STAGING_ROOT="$4"
        BACKUP_APP="${TARGET_APP}.previous"

        for _ in {1..120}; do
          if ! kill -0 "$TARGET_PID" 2>/dev/null; then
            break
          fi
          sleep 1
        done

        rm -rf "$BACKUP_APP"
        if [[ -d "$TARGET_APP" ]]; then
          mv "$TARGET_APP" "$BACKUP_APP"
        fi

        if ! /usr/bin/ditto "$STAGED_APP" "$TARGET_APP"; then
          rm -rf "$TARGET_APP"
          if [[ -d "$BACKUP_APP" ]]; then
            mv "$BACKUP_APP" "$TARGET_APP"
          fi
          exit 1
        fi

        /usr/bin/xattr -cr "$TARGET_APP" >/dev/null 2>&1 || true
        rm -rf "$BACKUP_APP"
        /usr/bin/open "$TARGET_APP"
        rm -rf "$STAGING_ROOT"
        """
    }
}

private struct PreparedUpdate {
    var targetAppURL: URL
    var stagedAppURL: URL
    var stagingRootURL: URL
    var installerScriptURL: URL
}

private struct GitHubRelease: Codable {
    struct Asset: Codable {
        var name: String
        var browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    var tagName: String
    var htmlURL: String
    var assets: [Asset]
    var publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
        case publishedAt = "published_at"
    }
}
