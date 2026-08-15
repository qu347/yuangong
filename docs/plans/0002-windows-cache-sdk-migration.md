# Windows 开发缓存与 SDK 迁移 Implementation Plan

> **执行方式：** 按“盘点 → 复制 → 切换 → 双轮验证 → 清理”推进；任何验证失败都保留源目录并记录回退状态。

**Goal:** 在不修改员工管理业务代码的前提下，把用户级 Gradle、Android SDK、Pub Cache 与 Docker Desktop 磁盘映像迁移到 D 盘，并用全新默认 PowerShell 环境完成 Android、Windows、模拟器和 Docker 的真实验收。

**Targets:**

- Gradle：`D:\DevCaches\Gradle`
- Android SDK：`D:\Android\Sdk`
- Pub Cache：`D:\DevCaches\Pub\Cache`
- Docker Desktop 磁盘映像：`D:\DockerData`（仅通过 Docker Desktop 官方设置迁移）

**Constraints:**

- 不移动整个用户目录或 `AppData`，不修改机器 PATH、系统代理、浏览器代理、公司网络配置或安全设置。
- 不删除 Android API、NDK、CMake、AVD、Docker 镜像、容器或卷。
- 每项迁移都先完整复制并校验，再切换用户环境；旧目录仅在两轮默认环境验收通过后清理。
- Gradle 只保持已识别的 6 个 HTTP/HTTPS 代理键为禁用状态，报告不记录任何代理值或凭据。
- 不运行仓库内 `flutter create`，不生成仓库 `pubspec.lock`，不修改业务代码，不创建 Git commit。

## Phase 1：只读盘点与基线

- [x] 记录 C/D 可用空间，源目录大小、文件数和目标目录状态。
- [x] 记录用户环境变量、用户/机器 PATH、Flutter 配置、doctor/devices 与 Android 工具解析路径。
- [x] 记录 Docker Desktop 磁盘映像位置、Engine/Compose/context，以及现有容器、镜像和卷计数。
- [x] 记录仓库状态与禁止变更基线。

## Phase 2：Gradle 迁移

- [x] 停止 Gradle 构建与 daemon；创建不覆盖的 `gradle.properties` 时间戳备份。
- [x] 完整复制默认用户 Gradle 目录至 `D:\DevCaches\Gradle`，校验文件数、字节数和关键配置。
- [x] 在 D 盘目标中只保持 6 个已识别代理键禁用，设置用户 `GRADLE_USER_HOME`。
- [x] 在全新无 Profile PowerShell 中证明默认 Gradle 目录为 D 盘，且没有临时代理、隔离目录、本地 Maven 或离线参数。

## Phase 3：Android SDK 与 Pub Cache 迁移

- [x] 关闭 Android Studio与模拟器，完整复制 SDK 至 `D:\Android\Sdk` 并校验组件、文件数和字节数。
- [x] 设置用户 `ANDROID_HOME`，保持 `ANDROID_SDK_ROOT` 缺失，精确替换用户 PATH 中旧 SDK 项，并更新 Flutter Android SDK 配置。
- [x] 完整复制 Pub Cache 至 `D:\DevCaches\Pub\Cache`，设置用户 `PUB_CACHE`，精确处理用户 PATH 中 Pub bin 项。
- [x] 在全新无 Profile PowerShell 中验证 `adb`、`emulator`、`sdkmanager`、Flutter 和 Pub 均解析到 D 盘。

## Phase 4：Docker Desktop 官方迁移

- [x] 在 Docker Desktop 中读取当前 Disk image location。
- [x] 使用 Settings → Resources → Advanced → Disk image location 切换到 `D:\DockerData` 并等待 Engine 恢复。
- [x] 验证 Engine、Compose、context、`hello-world`，并比较容器、镜像和卷清单，禁止手工移动 WSL 数据。

## Phase 5：首次完整验收

- [x] 启动 `employee_api36`，确认启动完成且 Flutter/ADB 可识别。
- [x] 在任务专用临时目录创建仅 Android/Windows 的全新 Flutter 工程。
- [x] 依次执行 pub get、format、analyze、test、Android Debug、Windows Debug、模拟器运行与 ADB 前台验证。
- [x] 证明实际 Gradle、SDK、Pub Cache 路径均为 D 盘，且 Docker 验收通过。

## Phase 6：旧目录隔离、复验与清理

- [x] 仅在首次完整验收通过后，把旧 Gradle、SDK、Pub Cache 目录精确改名为时间戳备份。
- [x] 在全新无 Profile PowerShell 中重复 doctor/devices、Android 构建、安装和前台验证。
- [x] 仅在第二轮全部通过后删除旧备份；若失败则保留两份并回退或报告。
- [x] 删除本任务创建的临时冒烟工程，记录实际释放的 C 盘空间。

## Phase 7：报告与收尾

- [x] 更新 `docs/environment-setup-state.md` 与 `docs/environment-report.md`，按 19 节要求记录 PASSED/FAILED/NOT RUN。
- [x] 确认没有项目 `pubspec.lock`、额外平台、业务代码或 Git commit 变更。
- [x] 输出最终 `git status --short`。
