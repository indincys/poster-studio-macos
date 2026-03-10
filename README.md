# PosterStudio MVP

这版已经按你最新的四张表结构重做：

- `视频库`
- `标签库`
- `标题库`
- `任务单`

同时提供两套能力：

- Python 脚本：快速生成 Excel、跑样本、验证逻辑
- SwiftUI macOS App：把标题生成、任务单生成、更新检查封装进一个 Apple Silicon 工具

## 当前文件

- [字段模型](/Users/indincys/Documents/code/poster/scripts/schema.py)
- [样本库初始化脚本](/Users/indincys/Documents/code/poster/scripts/bootstrap_sample_data.py)
- [标题库生成脚本](/Users/indincys/Documents/code/poster/scripts/generate_title_library.py)
- [任务单生成脚本](/Users/indincys/Documents/code/poster/scripts/generate_daily_tasks.py)
- [任务生成配置](/Users/indincys/Documents/code/poster/config/task_generation_options.json)
- [Swift Package](/Users/indincys/Documents/code/poster/Package.swift)
- [SwiftUI 应用入口](/Users/indincys/Documents/code/poster/Sources/PosterStudio/PosterStudioApp.swift)
- [App 状态管理](/Users/indincys/Documents/code/poster/Sources/PosterStudio/AppState.swift)
- [标题生成服务](/Users/indincys/Documents/code/poster/Sources/PosterStudio/Services/TitleGenerationService.swift)
- [任务生成服务](/Users/indincys/Documents/code/poster/Sources/PosterStudio/Services/TaskGenerationService.swift)
- [Excel 读写服务](/Users/indincys/Documents/code/poster/Sources/PosterStudio/Services/XlsxService.swift)
- [GitHub 更新服务](/Users/indincys/Documents/code/poster/Sources/PosterStudio/Services/UpdateService.swift)
- [主界面](/Users/indincys/Documents/code/poster/Sources/PosterStudio/Views/ContentView.swift)
- [打包脚本](/Users/indincys/Documents/code/poster/scripts/package_app.sh)
- [GitHub Release 工作流](/Users/indincys/Documents/code/poster/.github/workflows/release.yml)

## 四张表

### 1. 视频库

文件：`data/video_library.xlsx`  
工作表：`视频库`

表头：

- `视频文件名`
- `视频路径`
- `封面路径`
- `SKU编码`
- `SKU款式`
- `使用状态`
- `发布日期`
- `发布时间`
- `小黄车标题`
- `看后搜小蓝词（抖音）`
- `位置信息（视频号）`
- `热门款`

### 2. 标签库

文件：`data/tag_library.xlsx`  
工作表：`标签库`

表头：

- `SKU编码`
- `SKU款式名`
- `标签1`
- `标签2`
- `标签3`
- `标签4`
- `标签5`

### 3. 标题库

文件：`data/title_library.xlsx`  
工作表：`标题库`

表头：

- `标题`
- `使用状态`
- `使用次数`
- `爆款分`
- `短标题（视频号）`

短标题规则已经落进脚本和 App：

- 基于 `标题` 自动生成
- 目标长度 6-16 字
- 不保留不支持的特殊符号
- 只允许书名号、引号、冒号、加号、问号、百分号、摄氏度
- 逗号转空格

### 4. 任务单

文件：`output/tasks_YYYY-MM-DD.xlsx`  
工作表：`任务单`

表头：

- `任务ID`
- `任务日期`
- `定时发布时间`
- `发布平台`
- `账号名称`
- `SKU款式名`
- `SKU编码`
- `商品名称`
- `视频文件名`
- `视频路径`
- `封面路径`
- `标题`
- `标签1`
- `标签2`
- `标签3`
- `标签4`
- `标签5`
- `标记原创`
- `小黄车标题（抖音）`
- `位置信息`
- `任务状态`

## Python 使用方式

初始化样本视频库和标签库：

```bash
python3 scripts/bootstrap_sample_data.py
```

生成标题库：

```bash
python3 scripts/generate_title_library.py \
  --prompt "保温杯 蒸汽眼罩 小风扇 短视频带货标题" \
  --count 12
```

如果要接兼容 OpenAI 的接口：

```bash
python3 scripts/generate_title_library.py \
  --prompt "保温杯短视频转化标题" \
  --count 20 \
  --api-key "YOUR_KEY" \
  --base-url "https://your-base-url/v1" \
  --model "your-model"
```

生成任务单：

```bash
python3 scripts/generate_daily_tasks.py
```

任务单生成逻辑由 [config/task_generation_options.json](/Users/indincys/Documents/code/poster/config/task_generation_options.json) 控制：

- 任务日期
- 视频库热门款/普通款筛选
- 标题库高爆款分/普通标题筛选
- 爆款分阈值
- 平台计划
- 是否回写视频状态和标题使用次数

## 任务单逻辑

当前逻辑已经重构为：

1. 从 `视频库` 读取数据
2. 按 `任务日期 + 使用状态 + 热门款筛选` 过滤视频
3. 从 `标题库` 按 `使用状态 + 爆款分策略` 挑标题
4. 优先选择 `使用次数` 更少、`爆款分` 更高的标题
5. 从 `标签库` 按 `SKU编码` 匹配 `标签1-标签5`
6. 按平台计划展开 `任务单`
7. 回写：
   - 视频 `使用状态 -> 已生成任务`
   - 标题 `使用次数 + 1`

## macOS App

应用名：`PosterStudio`

功能：

- `数据源` 页签：导入/导出视频库、标签库、标题库、任务单
- `标题生成` 页签：Prompt、API Key、Base URL、模型名、模型提供方设置
- `任务单生成` 页签：业务流程可视化、热门款/普通款筛选、爆款标题/普通标题筛选、平台计划
- `更新` 页签：GitHub 仓库设置、检查最新 Release、下载并安装更新

编译：

```bash
swift build
```

运行：

```bash
swift run PosterStudio
```

## 打包与发布

本地打包：

```bash
swift build -c release
./scripts/package_app.sh 0.1.0
```

会生成：

- `dist/PosterStudio.app`
- `dist/PosterStudio-arm64-0.1.0.zip`

GitHub Release：

- 推送 `v*` tag 后，工作流 [release.yml](/Users/indincys/Documents/code/poster/.github/workflows/release.yml) 会自动构建并上传 zip 到 Release
- App 内部通过 GitHub Releases API 检查最新版本，直接下载 `.zip` 并自动替换安装

## 说明

- 这版 App 只支持 Apple Silicon，编译目标是 `arm64`
- 目前仓库和发布链路已经准备好，但还没有替你创建远端 GitHub 仓库，也没有替你实际 push release
- 如果你下一步要我继续，我可以直接做这三件事：
  1. 把 App 再补一轮界面细节和导入校验
  2. 初始化 git 并整理首次提交
  3. 接你指定的 GitHub 仓库名，完成远端创建、push、tag 和首个 release
