# Windows 开发环境配置状态

更新时间：2026-08-15
用途：记录可重复执行的环境配置阶段；不包含代理值、凭据、真实员工数据或无关个人文件内容。

## 状态说明

- `PASSED`：真实命令已执行且满足默认使用条件。
- `FAILED`：命令已执行但未达到验收条件。
- `NOT RUN`：为遵守安全或仓库约束而未执行。

## 阶段状态

| 阶段 | 状态 | 当前结论 | 继续入口 |
| --- | --- | --- | --- |
| 系统预检 | PASSED | Windows 11 Pro x64；Hypervisor/WHPX 可用；最终 C 盘约 41.82 GiB、D 盘约 181.18 GiB 可用 | 无 |
| Flutter SDK | PASSED | Flutter 3.47.0 / Dart 3.13.0，位于 `D:\DevTools\flutter` | 无 |
| Gradle 用户目录 | PASSED | `GRADLE_USER_HOME=D:\DevCaches\Gradle`；二次 clean 构建与 daemon 路径均为 D 盘 | 无 |
| Gradle 代理 | PASSED | 只禁用 6 个已识别 HTTP/HTTPS 键，活动键为 0；配置备份在 D 盘保留 | 无 |
| Android SDK | PASSED | `ANDROID_HOME=D:\Android\Sdk`，`ANDROID_SDK_ROOT` 不存在；API 36、Build-Tools、NDK、CMake、模拟器工具均从 D 盘通过 | 无 |
| Android Studio/JBR | PASSED | Android Studio 2024.3 位于 `D:\andriod`；本次启动日志读取 D 盘 SDK；Flutter 使用 JBR 21.0.5 | 无 |
| Android Studio SDK Manager UI | NOT RUN | 无关旧项目弹出代理认证框；未输入凭据或修改代理。默认 SDK 已由日志、Flutter、SDK Manager CLI 与实构建证明 | 如需人工复核，在关闭旧项目后打开 SDK Manager |
| Android AVD | PASSED | `employee_api36` 保持在 `D:\Android\avd`；ADB `device`，`sys.boot_completed=1` | 无 |
| Pub Cache | PASSED | `PUB_CACHE=D:\DevCaches\Pub\Cache`；pub get、package_config 与真实写入均验证为 D 盘 | 无 |
| Visual Studio / Windows | PASSED | Visual Studio Professional 2022 17.14；Windows Debug 实编译通过 | 无 |
| Docker Desktop | PASSED | WSL 2 数据通过官方 UI 迁移到 `D:\DockerData\DockerDesktopWSL`；Engine 29.7.2、Compose 5.3.1、hello-world 通过 | 无 |
| Python | PASSED | 仓库 venv Python 3.12.13、Django 5.2.17、pytest 9.1.1 保持可用 | 无 |
| 独立 Flutter 冒烟 | PASSED | Android/Windows 临时项目完成 clean、pub get、format、analyze、test、双平台构建、安装与前台 Activity 验证；临时项目已删除 | 无 |
| 旧目录清理 | PASSED | 旧 Gradle、Android SDK、Pub Cache 先改名隔离，二次验收后永久删除；精确释放 18.87 GiB | 无 |
| 项目仓库保护 | PASSED | 未修改业务代码，未运行项目 `flutter create`，未生成项目 `pubspec.lock`，未创建 commit | 无 |
| `scripts/check.ps1` | NOT RUN | 可能在无锁文件的员工 Flutter 项目中生成被本轮禁止的 `pubspec.lock` | 下一轮工程补全时运行 |

## 最终持久路径

| 项目 | 状态 | 路径 |
| --- | --- | --- |
| Flutter | PASSED | `D:\DevTools\flutter` |
| Gradle | PASSED | `D:\DevCaches\Gradle` |
| Android SDK | PASSED | `D:\Android\Sdk` |
| Android AVD | PASSED | `D:\Android\avd` |
| Pub Cache | PASSED | `D:\DevCaches\Pub\Cache` |
| Docker WSL 数据 | PASSED | `D:\DockerData\DockerDesktopWSL` |
| Flutter JDK | PASSED | `D:\andriod\jbr` |

## Gradle 配置备份

- 状态：PASSED
- 创建时原路径：`C:\Users\quwenxin\.gradle\gradle.properties.backup-20260815-143648039`。
- 最终保留路径：`D:\DevCaches\Gradle\gradle.properties.backup-20260815-143648039`。
- SHA-256：`838C8486F690AF31A5DEEF3C3C19ED343EE206BF3EAADDC7941D6AABB9816561`。
- 禁用键：`systemProp.http.proxyHost`、`systemProp.http.proxyPassword`、`systemProp.http.proxyPort`、`systemProp.https.proxyHost`、`systemProp.https.proxyPassword`、`systemProp.https.proxyPort`；值与凭据不记录。

## 验收产物记录

- 状态：PASSED
- Android Debug APK：150,491,324 字节；SHA-256 `9F61465BE7E54827BA1C20662398EF26101A18F77B6DD1705D9C75BBC6D960DD`。
- Windows Debug EXE：1,029,632 字节；SHA-256 `18AF21B869D51512DB28B0DFB9A08E21BE57249398A5A48060688DA93A300501`。
- Android 包：`com.example.cache_migration_smoke`；ADB 确认 PID 3461，`MainActivity` 为 resumed Activity。
- 产物来自任务临时目录；按清理要求，该目录已删除。

## 幂等、安全与清理记录

- 用户 PATH 中三个 `%ANDROID_HOME%` 工具项各 1 个，旧 SDK/Pub Cache 项为 0；机器 PATH 未修改。
- `GRADLE_OPTS`、`JAVA_TOOL_OPTIONS`、`HTTP_PROXY`、`HTTPS_PROXY`、`FLUTTER_STORAGE_BASE_URL` 均为 `UNSET`。
- 未使用离线参数、隔离 Gradle、人工 Maven 缓存或临时代理。
- 未执行 Docker reset、prune 或 WSL unregister；迁移前后镜像、容器、卷对象指纹一致。
- C 盘三个旧缓存/SDK 原路径和时间戳备份均已删除；D 盘目标保持可用。
- 为修复 Docker 4.86.0 AF_UNIX 启动循环，保留两个共 10 个、总计 0 字节的运行时恢复目录；不含 VHDX 或用户数据。
- 默认开发环境配置完成：**PASSED**。

## 等待用户操作

无。
