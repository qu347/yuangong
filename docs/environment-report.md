# Windows 开发缓存与 SDK 迁移报告

缓存迁移检查日期：2026-08-15

员工项目复验日期：2026-08-17
工作区：`D:\员工管理`
隐私：不记录用户名、计算机名、代理值、密码、Token、局域网详情或真实员工数据。所有命令结果仅使用 `PASSED`、`FAILED`、`NOT RUN`。

## 1. 迁移前磁盘空间

| 检查 | 状态 | 结果 |
| --- | --- | --- |
| C 盘可用空间 | PASSED | 约 21.59 GiB |
| D 盘可用空间 | PASSED | 约 150.00 GiB |
| 旧 Gradle 用户目录 | PASSED | 47,050 个文件，6,387,078,868 字节 |
| 旧 Android SDK | PASSED | 70,494 个文件，13,077,848,209 字节 |
| 旧 Pub Cache | PASSED | 19,281 个文件，478,886,895 字节 |
| Docker Local 数据 | PASSED | 28 个文件，1,746,205,977 字节；两个 VHDX 位于 C 盘 |

迁移前 `GRADLE_USER_HOME`、`PUB_CACHE` 未设置，`ANDROID_HOME` 与用户 PATH 中三个 Android 工具项指向 C 盘旧 SDK。机器级 PATH 未修改。

## 2. 迁移后磁盘空间

| 盘符 | 状态 | 最终已用 | 最终可用 |
| --- | --- | ---: | ---: |
| C | PASSED | 约 210.31 GiB | 约 41.82 GiB |
| D | PASSED | 约 518.82 GiB | 约 181.18 GiB |

D 盘在执行期间还发生了与本任务无关的主机存储变化，因此只把 C 盘的直接删除计量作为精确释放值，不把 D 盘前后差额全部归因于本次迁移。

## 3. 实际释放空间

| 检查 | 状态 | 结果 |
| --- | --- | --- |
| 三个旧目录备份删除前 | PASSED | C 盘可用 24,734,253,056 字节 |
| 三个旧目录备份删除后 | PASSED | C 盘可用 44,994,928,640 字节 |
| 精确直接释放 | PASSED | 20,260,675,584 字节，即 18.87 GiB |
| 迁移前后 C 盘净变化 | PASSED | 约增加 20.23 GiB；包含 Docker VHDX 迁移和少量运行时波动 |

## 4. Gradle 迁移结果

- 状态：PASSED
- 目标：`D:\DevCaches\Gradle`。
- 完整复制后初始审计为 0 个失败、0 个不匹配；旧目录隔离前再次以“只合并较新文件、不删除目标新增缓存”的方式审计，待复制文件为 0。
- 用户 `GRADLE_USER_HOME=D:\DevCaches\Gradle`；全新 `powershell.exe -NoProfile` 中值一致。
- 二次 clean 构建后的 Gradle daemon 使用 `D:\DevCaches\Gradle`，`UsesOldCGradle=False`，Java 为 `D:\andriod\jbr\bin\java.exe`。
- 旧 `C:\Users\quwenxin\.gradle` 先改名为 `C:\Users\quwenxin\.gradle.backup-20260815-154915481`，复验通过后已删除。
- 原配置备份创建路径：`C:\Users\quwenxin\.gradle\gradle.properties.backup-20260815-143648039`；迁移后保留路径：`D:\DevCaches\Gradle\gradle.properties.backup-20260815-143648039`。
- 保留备份 SHA-256：`838C8486F690AF31A5DEEF3C3C19ED343EE206BF3EAADDC7941D6AABB9816561`。
- 构建未使用临时 `GRADLE_USER_HOME`、隔离目录、`--offline`、人工 Maven 缓存或临时代理变量。

## 5. 被禁用的代理键名称，隐藏值

- 状态：PASSED
- `systemProp.http.proxyHost`
- `systemProp.http.proxyPassword`
- `systemProp.http.proxyPort`
- `systemProp.https.proxyHost`
- `systemProp.https.proxyPassword`
- `systemProp.https.proxyPort`

六个键的活动数量均为 0；代理值和凭据未输出、未记录。其他 Gradle 配置、系统代理、浏览器代理和公司网络配置均未修改。

## 6. Android SDK 迁移结果

- 状态：PASSED
- 目标：`D:\Android\Sdk`；旧 `C:\Users\quwenxin\AppData\Local\Android\Sdk` 已在双轮验证后删除。
- `flutter config android-sdk`、`ANDROID_HOME`、临时项目 `android/local.properties` 均指向 `D:\Android\Sdk`；`ANDROID_SDK_ROOT` 保持不存在。
- `where adb`、`where emulator`、`where sdkmanager` 全部解析到 D 盘。
- `flutter doctor -v`：Android SDK 36.0.0、Build-Tools 36.0.0、Emulator 35.4.9、JBR 21.0.5、许可证全部接受，No issues found。
- `sdkmanager --list`：API 36、Build-Tools 36.0.0、CMake 4.1.2、NDK 28.2/29.0 与 API 36 Google APIs x86_64 镜像均存在。
- AVD 保持 `D:\Android\avd`；Flutter JDK 保持 `D:\andriod\jbr`；API 34/35/36、NDK 28/29 和 CMake 未删除。
- Android Studio 于 15:39 的启动日志确认读取 `D:\Android\Sdk`。SDK Manager 界面可视确认因无关旧项目弹出代理认证框而标记 `NOT RUN`；未输入凭据、未修改代理，也未修改该旧项目。

## 7. Pub Cache 迁移结果

- 状态：PASSED
- 目标：`D:\DevCaches\Pub\Cache`；用户 `PUB_CACHE` 与全新 PowerShell 均指向该路径。
- `dart pub global list`：PASSED；当前无全局包。
- clean 后 `flutter pub get`：PASSED；`.dart_tool/package_config.json` 包含 D 盘 Pub Cache，旧 C 盘 Pub Cache 引用为 0。
- 二次构建期间 D 盘 Pub Cache 有真实写入；旧 `C:\Users\quwenxin\AppData\Local\Pub\Cache` 已在复验通过后删除。
- 用户 PATH 原本没有旧 Pub Cache `bin`，因此没有添加重复项。

## 8. Docker 数据迁移结果

- 状态：PASSED
- 严格通过 Docker Desktop 官方 UI 执行 `Settings → Resources → Advanced → Disk image location`；选择 `D:\DockerData` 后，Docker Desktop 4.86.0 的有效目录为 `D:\DockerData\DockerDesktopWSL`。
- 最终 VHDX：`disk\docker_data.vhdx` 1,645,215,744 字节，`main\ext4.vhdx` 100,663,296 字节；C 盘 Docker WSL 目录 VHDX 数量为 0，D 盘为 2。
- 未手工移动 WSL 数据，未执行 `wsl --unregister`、`docker system prune`、恢复出厂设置，也未删除镜像、容器或卷。
- Docker 4.86.0 曾被 Windows AF_UNIX 残留端点阻断。只隔离两个各含 0 字节瞬态 socket 的父目录后恢复 Engine，再通过 UI 迁移；VHDX 始终未被手工改动。
- 迁移前后对象指纹一致：容器 0、镜像 1、卷 0；镜像 ID 集合 SHA-256 均为 `AD8E856C63C3CB62A0E6857EF4D8D45285425BBD278D582DE217F4E0759E8AE6`。
- Docker 官方说明确认 WSL 2 数据位置应从 Resources/Advanced 修改：[Docker Desktop settings](https://docs.docker.com/desktop/settings-and-maintenance/settings/)；逐字一致的 AF_UNIX 现象见 [docker/desktop-feedback #460](https://github.com/docker/desktop-feedback/issues/460)。

## 9. 用户环境变量最终状态

| 变量 | 状态 | 最终值 |
| --- | --- | --- |
| `GRADLE_USER_HOME` | PASSED | `D:\DevCaches\Gradle` |
| `ANDROID_HOME` | PASSED | `D:\Android\Sdk` |
| `ANDROID_SDK_ROOT` | PASSED | `UNSET`，保持不存在 |
| `ANDROID_AVD_HOME` | PASSED | `D:\Android\avd` |
| `PUB_CACHE` | PASSED | `D:\DevCaches\Pub\Cache` |
| `GRADLE_OPTS` | PASSED | `UNSET` |
| `JAVA_TOOL_OPTIONS` | PASSED | `UNSET` |
| `HTTP_PROXY` / `HTTPS_PROXY` | PASSED | `UNSET` |
| `FLUTTER_STORAGE_BASE_URL` | PASSED | `UNSET` |

由于 Codex 宿主进程不会自动刷新登录环境，全新无 Profile 子进程由 HKCU 持久用户环境构造；没有使用不同于持久配置的临时缓存覆盖。

## 10. PATH 最终状态

- 状态：PASSED
- `%ANDROID_HOME%\platform-tools`：1 项。
- `%ANDROID_HOME%\emulator`：1 项。
- `%ANDROID_HOME%\cmdline-tools\latest\bin`：1 项。
- 指向 C 盘旧 SDK 的用户 PATH 项：0。
- 指向 C 盘旧 Pub Cache 的用户 PATH 项：0。
- 机器 PATH 哈希在迁移过程中保持不变；未覆盖整个用户 PATH。

## 11. flutter doctor 结果

- 状态：PASSED
- Flutter 3.47.0 stable / Dart 3.13.0，路径 `D:\DevTools\flutter`。
- Android toolchain、Windows 11、Visual Studio Professional 2022 17.14、连接设备和网络资源全部通过。
- 精确结论：`No issues found!`

## 12. Android Debug 构建结果

| 步骤 | 状态 | 结果 |
| --- | --- | --- |
| 首轮 `flutter build apk --debug` | PASSED | 136.6 秒 |
| 旧目录隔离后的 clean / pub get / format / analyze / test | PASSED | format 0 变更、analyze 无问题、1/1 测试通过 |
| 二轮 `flutter build apk --debug` | PASSED | 65.3 秒 |
| APK | PASSED | 150,491,324 字节；SHA-256 `9F61465BE7E54827BA1C20662398EF26101A18F77B6DD1705D9C75BBC6D960DD` |

历史产物路径为 `D:\DevTools\smoke\cache_migration_smoke_20260815_144500\build\app\outputs\flutter-apk\app-debug.apk`；按清理要求，验证完成后临时项目已删除。

## 13. Windows Debug 构建结果

- 状态：PASSED
- 首轮真实命令 `flutter build windows --debug` 在仅设置进程级 `TrackFileAccess=false` 后于 36.4 秒完成；该设置只绕过本机 MSBuild FileTracker 挂起，不改变 Gradle、Pub、Android SDK、代理或网络配置。
- EXE 为 1,029,632 字节；SHA-256 `18AF21B869D51512DB28B0DFB9A08E21BE57249398A5A48060688DA93A300501`。
- 历史产物路径为 `D:\DevTools\smoke\cache_migration_smoke_20260815_144500\build\windows\x64\runner\Debug\cache_migration_smoke.exe`；临时项目已删除。

## 14. 模拟器运行结果

| 检查 | 状态 | 结果 |
| --- | --- | --- |
| 启动源 | PASSED | `D:\Android\Sdk\emulator\emulator.exe` 与 D 盘 QEMU |
| AVD | PASSED | `employee_api36`，`emulator-5554`，Android 16 / API 36 |
| `sys.boot_completed` | PASSED | `1` |
| `flutter devices` | PASSED | 识别 Android 模拟器与 Windows desktop |
| `flutter run --debug --no-resident` | PASSED | 32.8 秒，安装并启动完成 |
| 应用进程 | PASSED | `com.example.cache_migration_smoke`，PID 3461 |
| 前台 Activity | PASSED | `topResumedActivity` 与 `ResumedActivity` 均为测试应用 `MainActivity` |

AVD 未删除，最终仍为 ADB `device` 状态。

## 15. Docker 验证结果

| 命令 | 状态 | 结果 |
| --- | --- | --- |
| `docker version` | PASSED | Client/Server 29.7.2 |
| `docker compose version` | PASSED | 5.3.1 |
| `docker info` | PASSED | Linux Engine / Docker Desktop |
| `docker context show` | PASSED | `desktop-linux` |
| `docker run --rm hello-world` | PASSED | 输出 `Hello from Docker!`，临时容器自动删除 |
| 对象指纹复核 | PASSED | 容器、镜像、卷数量和哈希与迁移前一致 |

## 16. 删除的旧目录

仅在两轮 Android 验收和 Docker 验收全部通过后执行：

| 目录 | 状态 | 结果 |
| --- | --- | --- |
| `C:\Users\quwenxin\.gradle.backup-20260815-154915481` | PASSED | 已永久删除 |
| `C:\Users\quwenxin\AppData\Local\Android\Sdk.backup-20260815-154915481` | PASSED | 已永久删除 |
| `C:\Users\quwenxin\AppData\Local\Pub\Cache.backup-20260815-154915481` | PASSED | 已永久删除 |
| `D:\DevTools\smoke\cache_migration_smoke_20260815_144500` | PASSED | 本轮临时项目已永久删除 |

员工管理项目、Android AVD、API、NDK、CMake、Docker 镜像/容器/卷均未删除。

## 17. 保留的备份

| 项目 | 状态 | 路径/说明 |
| --- | --- | --- |
| Gradle 原配置备份 | PASSED | `D:\DevCaches\Gradle\gradle.properties.backup-20260815-143648039`；SHA-256 已验证 |
| Docker run 恢复目录 | PASSED | `C:\Users\quwenxin\AppData\Local\Docker\run.stale-20260815-153016954`；7 个 0 字节端点 |
| Docker secrets 恢复目录 | PASSED | `C:\Users\quwenxin\AppData\Local\docker-secrets-engine.stale-20260815-153016954`；3 个 0 字节端点 |

两个 Docker 恢复目录不含 VHDX、镜像或用户数据，占用 0 字节；为避免再次触发 Windows AF_UNIX 内核端点问题，本轮不删除。

## 18. 失败或未执行项目

| 项目 | 状态 | 原因 |
| --- | --- | --- |
| Android Studio SDK Manager 界面可视确认 | NOT RUN | 自动重开无关旧项目并弹出代理认证；按安全约束未操作认证框。启动日志与实际工具链已证明默认 SDK 为 D 盘 |
| `scripts/check.ps1` | NOT RUN | 会在当前无锁文件的员工 Flutter 项目中触发依赖解析，可能生成被明确禁止的项目 `pubspec.lock` |
| 员工项目 `flutter create`、项目 Compose、迁移、业务构建 | NOT RUN | 本轮明确禁止修改业务工程 |
| Release 签名/构建 | NOT RUN | 不属于本轮缓存与 Debug 冒烟范围 |
| Git commit | NOT RUN | 用户明确禁止 |

已恢复的脚本问题不计为环境失败：一次 `sdkmanager` 警告被 PowerShell 5.1 误判为异常，保留原生退出码后为 0；一次 ADB 脚本误用只读 `$PID` 变量，改名后验证通过。

## 19. 是否满足默认开发环境完成条件

- 状态：PASSED WITH WARNINGS
- 结论：**持久用户配置满足默认开发条件；当前员工项目的 Pub 生成元数据仍需在正确继承用户变量的终端中刷新。**

Flutter、Gradle、Android SDK、AVD、Windows 构建、Docker Engine/Compose 与真实 Android 安装运行均通过。2026-08-17 发现 Codex 宿主进程未继承持久 `PUB_CACHE`，项目 `.dart_tool/package_config.json` 的 97 个 Pub 包仍引用 C 盘并重新创建了该缓存；该生成目录不提交 Git。本轮按用户要求没有重复 `flutter pub get`，因此不再维持“C 盘 Pub Cache 原路径未重建”的旧结论。

## 20. 员工项目完整复验（2026-08-17）

| 检查 | 状态 | 结果 |
| --- | --- | --- |
| 持久 D 盘变量 | PASSED | `GRADLE_USER_HOME`、`PUB_CACHE`、`ANDROID_HOME`、`ANDROID_AVD_HOME` 仍分别指向已记录的 D 盘目录 |
| 临时代理/离线构建 | PASSED | 用户级与验收进程的代理相关变量为 `UNSET`；Android 构建未使用离线参数、隔离 Gradle 或人工 Maven 缓存 |
| Windows 项目构建与运行 | PASSED WITH WARNINGS | EXE 983,040 字节；进程和窗口通过；构建使用进程级 `TrackFileAccess=false` 绕过本机 FileTracker 挂起 |
| Android 项目构建与运行 | PASSED WITH WARNINGS | APK 165,290,276 字节；`employee_api36` 上 PID 与 resumed Activity 通过；首次 `am start -W` 等待超时但应用保持正常 |
| Docker Compose | PASSED | PostgreSQL、Redis healthy，Django API running；未删除卷 |
| PostgreSQL / Redis | PASSED | SQL 返回 `1`；CLI 与 Django Redis 探针均为 `PONG`；Django vendor 为 `postgresql` |
| Django | PASSED | 无迁移差异、migrate 幂等、SQLite 与 PostgreSQL 模式 pytest 都为 9/9，三个 HTTP 端点均为 200 |
| `scripts/check.ps1` | PASSED | 提交前复验为 2026-08-17 10:52:44 至 10:53:08，24.2 秒，退出码 0；Compose 配置静默校验 |
| Pub 项目元数据 | PASSED WITH WARNINGS | 持久用户变量正确，但项目 97 个生成引用仍指向 C 盘；C 盘缓存为 9,877 个文件、154,872,143 字节 |

完整项目级命令、产物哈希、进程、协议和 Git 结果见 `docs/project-bootstrap-validation-report.md`。

## 21. HR 目录管理第二阶段复验（2026-08-17）

| 检查 | 状态 | 结果 |
| --- | --- | --- |
| 持久 Gradle/Pub | PASSED WITH NOTE | 真实用户 PowerShell 读取 `D:\DevCaches\Gradle` / `D:\DevCaches\Pub\Cache`；Codex 精简继承环境不自动注入，正式 Android 构建从用户配置加载 |
| Docker Compose | PASSED | Engine 29.7.2；api running；PostgreSQL/Redis healthy；Redis PONG；未删除 volume |
| 迁移 | PASSED | audit 0001、organizations 0002、token_blacklist 官方迁移全部应用；无迁移差异 |
| SQLite/PostgreSQL | PASSED | 两种后端均 75/75；PostgreSQL 专属行锁问题已修复 |
| OpenAPI | PASSED | `--validate --fail-on-warn` 退出码 0，0 warning/error |
| `scripts/check.ps1` | PASSED | Dart 74/0 变更、analyze 0 issue、Flutter 66/66、Ruff/Django/SQLite/Compose 全通过 |
| Windows Debug | PASSED WITH WARNING | 41.6 秒；EXE 983,040 字节；SHA-256 `769AFE9978660356D85C9AF1CB8623926002CAA6C92D35BBA770B50C13A41601`；进程响应正常；仅进程级 TrackFileAccess=false |
| Android Debug | PASSED WITH WARNING | 29.8 秒；APK 232,355,573 字节；SHA-256 `1F13DCF28053ABDC40C633A722B728EE32E7A7CE34592740A48C9314FB3563FE`；install Success；PID 6778；前台 Activity 通过；FATAL=0 |
| 真实 UI/API | PASSED | Windows 与 employee_api36 均完成 HR 登录、管理表单、审计、目录详情、部门与 logout |

完整功能、安全、数据清理和 Git 结果见 `docs/hr-directory-management-validation-report.md`。
