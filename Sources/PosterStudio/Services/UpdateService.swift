import AppKit
import Foundation

enum UpdateServiceError: LocalizedError {
    case missingRepository
    case invalidResponse
    case missingDownloadAsset
    case invalidDownloadURL
    case archiveExtractionFailed
    case appBundleNotFound
    case installerPreparationFailed
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRepository:
            return "请先填写 GitHub 仓库 owner 和 repo"
        case .invalidResponse:
            return "更新接口返回格式无效"
        case .missingDownloadAsset:
            return "最新 Release 没有可安装的 .zip 包"
        case .invalidDownloadURL:
            return "更新下载地址无效"
        case .archiveExtractionFailed:
            return "更新包解压失败"
        case .appBundleNotFound:
            return "更新包里没有找到 .app 安装包"
        case .installerPreparationFailed:
            return "无法准备更新安装器"
        case .processFailed(let message):
            return message
        }
    }
}

enum UpdateService {
    static func checkForLatestRelease(settings: UpdateSettings) async throws -> ReleaseInfo {
        guard settings.hasRepository else {
            throw UpdateServiceError.missingRepository
        }

        guard let url = URL(string: "https://api.github.com/repos/\(settings.trimmedOwner)/\(settings.trimmedRepoName)/releases/latest") else {
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
        let asset = preferredAsset(in: release.assets)
        let downloadURL = asset.flatMap { URL(string: $0.browserDownloadURL) }
        return ReleaseInfo(version: release.tagName, pageURL: pageURL, downloadURL: downloadURL, assetName: asset?.name)
    }

    static func currentVersionDisplay() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return normalizedVersion(shortVersion) ?? normalizedVersion(buildVersion) ?? "开发版"
    }

    static func canInstall(release: ReleaseInfo, currentVersion: String) -> Bool {
        guard release.downloadURL != nil else { return false }
        guard let normalizedLatest = normalizedVersion(release.version) else { return false }
        guard let normalizedCurrent = normalizedVersion(currentVersion) else { return true }
        return normalizedLatest.compare(normalizedCurrent, options: [.numeric, .caseInsensitive]) == .orderedDescending
    }

    @discardableResult
    static func installRelease(_ release: ReleaseInfo) async throws -> URL {
        guard let downloadURL = release.downloadURL else {
            throw UpdateServiceError.missingDownloadAsset
        }

        let fileManager = FileManager.default
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("PosterStudioUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let archiveURL = workingDirectory.appendingPathComponent(release.assetName ?? "PosterStudio-update.zip")
        let extractedDirectory = workingDirectory.appendingPathComponent("expanded", isDirectory: true)
        try fileManager.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)

        let temporaryDownloadURL = try await downloadArchive(from: downloadURL)
        try fileManager.moveItem(at: temporaryDownloadURL, to: archiveURL)

        do {
            try runProcess(
                executable: "/usr/bin/ditto",
                arguments: ["-x", "-k", archiveURL.path, extractedDirectory.path]
            )
        } catch {
            throw UpdateServiceError.archiveExtractionFailed
        }

        let appBundleURL = try findAppBundle(in: extractedDirectory)
        let targetURL = try installationTargetURL(fallbackAppName: appBundleURL.lastPathComponent)
        let installerScriptURL = try writeInstallerScript(into: workingDirectory)

        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/bin/zsh")
        installer.arguments = [
            installerScriptURL.path,
            appBundleURL.path,
            targetURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            workingDirectory.path,
        ]

        do {
            try installer.run()
        } catch {
            throw UpdateServiceError.installerPreparationFailed
        }

        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }

        return targetURL
    }

    static func openReleasePage(_ release: ReleaseInfo) {
        openURL(release.pageURL)
    }

    static func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static func preferredAsset(in assets: [GitHubRelease.Asset]) -> GitHubRelease.Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }

    private static func normalizedVersion(_ version: String?) -> String? {
        guard let version else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        return trimmed.replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
    }

    private static func downloadArchive(from url: URL) async throws -> URL {
        guard url.scheme?.hasPrefix("http") == true else {
            throw UpdateServiceError.invalidDownloadURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw UpdateServiceError.invalidResponse
        }

        return temporaryURL
    }

    private static func findAppBundle(in root: URL) throws -> URL {
        let fileManager = FileManager.default
        if root.pathExtension == "app" {
            return root
        }

        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw UpdateServiceError.appBundleNotFound
        }

        for case let url as URL in enumerator where url.pathExtension == "app" {
            return url
        }

        throw UpdateServiceError.appBundleNotFound
    }

    private static func installationTargetURL(fallbackAppName: String) throws -> URL {
        let fileManager = FileManager.default
        let runningBundleURL = Bundle.main.bundleURL.standardizedFileURL

        if runningBundleURL.pathExtension == "app" {
            let parentDirectory = runningBundleURL.deletingLastPathComponent()
            if fileManager.isWritableFile(atPath: parentDirectory.path) {
                return runningBundleURL
            }
        }

        let userApplicationsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        try fileManager.createDirectory(at: userApplicationsDirectory, withIntermediateDirectories: true)

        let appName = runningBundleURL.pathExtension == "app" ? runningBundleURL.lastPathComponent : fallbackAppName
        return userApplicationsDirectory.appendingPathComponent(appName, isDirectory: true)
    }

    private static func writeInstallerScript(into directory: URL) throws -> URL {
        let script = """
        #!/bin/zsh
        set -euo pipefail

        SOURCE_APP="$1"
        TARGET_APP="$2"
        APP_PID="$3"
        TEMP_ROOT="$4"

        while kill -0 "$APP_PID" 2>/dev/null; do
          sleep 0.5
        done

        sleep 1
        mkdir -p "${TARGET_APP:h}"
        rm -rf "$TARGET_APP"
        ditto "$SOURCE_APP" "$TARGET_APP"
        xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
        open "$TARGET_APP"
        rm -rf "$TEMP_ROOT"
        """

        let scriptURL = directory.appendingPathComponent("install_update.sh")
        guard let data = script.data(using: .utf8) else {
            throw UpdateServiceError.installerPreparationFailed
        }
        try data.write(to: scriptURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    private static func runProcess(executable: String, arguments: [String]) throws {
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

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}
