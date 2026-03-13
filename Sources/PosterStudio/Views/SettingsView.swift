import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("GitHub 发布与更新") {
                Text("应用默认指向官方 GitHub Releases，可直接检查最新版本并下载安装。")
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("GitHub Owner", text: $appState.updateSettings.repoOwner)
                    TextField("Repo Name", text: $appState.updateSettings.repoName)
                }

                SecureField("GitHub Token（可选，避免速率限制）", text: $appState.updateSettings.githubToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(appState.isCheckingUpdate ? "检查中..." : "检查更新") {
                        Task { await appState.checkForUpdate() }
                    }
                    .disabled(appState.isCheckingUpdate || appState.isInstallingUpdate || !appState.updateSettings.hasRepository)

                    Button("恢复官方仓库") {
                        appState.restoreOfficialUpdateRepository()
                    }
                    .disabled(appState.isCheckingUpdate || appState.isInstallingUpdate)

                    if let url = appState.updateSettings.releasesPageURL {
                        Link("打开 Releases 页面", destination: url)
                    }
                }

                LabeledContent("当前版本") { Text(appState.currentVersion) }
                Text(appState.updateStatusMessage)
                    .foregroundStyle(.secondary)
            }

            if let release = appState.latestRelease {
                Section("最新发布") {
                    LabeledContent("版本") { Text(release.version) }

                    if let assetName = release.assetName {
                        LabeledContent("安装包") {
                            Text(assetName).foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button(appState.isInstallingUpdate ? "安装中..." : "下载并安装") {
                            Task { await appState.installLatestRelease() }
                        }
                        .disabled(
                            appState.isCheckingUpdate ||
                            appState.isInstallingUpdate ||
                            !UpdateService.canInstall(release: release, currentVersion: appState.currentVersion)
                        )

                        Button("打开 Release 页面") {
                            UpdateService.openReleasePage(release)
                        }
                    }

                    if !UpdateService.canInstall(release: release, currentVersion: appState.currentVersion) {
                        Text(release.downloadURL == nil ? "缺少可安装的 .zip 资产" : "当前已是最新版本")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 400)
    }
}
