# 第六阶段文件中心验收报告

- 日期：2026-08-21
- 分支：`feature/file-center-and-employee-attachments`
- 状态：`PASSED WITH WARNINGS`
- 提交：未创建

## 验收范围

本轮验证 ADR-0009 的 employees app 归属、专用本地 `FileSystemStorage`、固定类型与内容签名、10 MiB 上限、软删除、对象权限、审计、服务端生成路径、SQLite/PostgreSQL/OpenAPI、10,000 员工性能隔离、Flutter 以及 Windows/Android Debug 构建。最终修复重验额外覆盖读取 model permission、21 条以上分页、类型正确下载 fallback、400 存储冲突映射、Android writing teardown 和 production root `0700`。

## 后端与数据库

所有计数和耗时均为本轮新鲜运行：

| 检查 | 结果 | 墙钟耗时 |
| --- | --- | ---: |
| Ruff format | 150 files already formatted，exit 0 | 与 Ruff/check/Django/migration 合并 3.239 s |
| Ruff check | All checks passed，exit 0 | 同上 |
| Django check | 0 issues，exit 0 | 同上 |
| Migration drift | `No changes detected`，exit 0 | 同上 |
| SQLite pytest | 276 passed，1 skipped | pytest 16.75 s |
| PostgreSQL/Redis pytest | 273 passed，4 skipped | pytest 22.26 s |
| PostgreSQL 并发删除定点复跑 | 1 passed，25 deselected，未跳过 | pytest 3.03 s |
| Strict OpenAPI | `--validate --fail-on-warn` exit 0，0 warnings | 3.20 s |

SQLite 唯一 skip 是明确的 PostgreSQL row-lock concurrency contract。PostgreSQL 的 4 个 skip 均是 Linux 容器内要求 Windows PowerShell 的既有 release-contract 用例；`test_concurrent_attachment_delete_has_one_success_and_one_hidden_not_found` 在 PostgreSQL 全量结果中实际执行，并定点复跑通过，验证两个并发请求只产生一个 204、一个隐藏 404 和一条删除审计。附件权限/API/security/production-focused 结果为 74 passed、1 同样的 PostgreSQL-only skip。

首次宿主 SQLite 运行因当前沙箱身份无权读取宿主用户默认 pytest 临时目录而产生 39 个 setup errors；将临时目录切换到可写、仓库外位置后全量通过。一次仓库内临时目录试跑又被审计归档的“输出必须位于仓库外”安全合同正确拒绝；未改测试或放宽安全检查。

## 存储与性能

- production 镜像重新构建 exit 0，构建步骤确认 `install -d -m 0700 -o app -g app`。
- 一次性全新 named volume copy-up 探针得到 `COPY_UP_OWNER=10001:10001`、`COPY_UP_MODE=700`、`COPY_UP_WRITE=ok`、exit 0；探针卷随后删除，数据库卷未删除。
- 当前运行 API 的 bind mount 已确认指向本工作区，无需重建 API 容器。
- bind mount 不执行镜像目录 copy-up，运营方必须预先保证映射后的宿主目录由 UID/GID `10001` 可读写。
- 附件分页列表对 1 条与 20 条上传者已加载记录均为 3 次查询，证明没有 uploaded_by N+1。
- 附件区域按单员工独立加载，不加入员工目录 queryset，因此 10,000 员工查询不会预取附件。

10,000 员工 SQLite 性能合同定点复跑：100 部门、500 岗位、10,000 员工，3 次迭代；搜索 7.628 ms（目标 <500 ms）、分页 6.205 ms（目标 <300 ms）、Dashboard 3.25 ms（目标 <500 ms）。该测试与附件恒定查询测试共 `2 passed in 2.09s`。

## Flutter 与双平台

| 检查 | 结果 | 墙钟耗时 |
| --- | --- | ---: |
| Dart format | 138 files，0 changed | 1.140 s |
| Flutter analyze | No issues found | analyzer 4.2 s |
| Flutter test | 179 passed | 25.217 s |
| Kotlin lifecycle contract | `AttachmentWriteLifecycleContract: PASS` | dependency-free JVM contract |
| Windows Debug build | `employee_app.exe` 构建成功 | Flutter 48.6 s |
| Android Debug APK build | `app-debug.apk` 构建成功，且 assemble 内 contract PASS | Flutter 73.4 s |

Flutter analyze 通过仓库脚本创建并校验临时 ASCII junction，规避中文路径下的 Flutter 3.47 LSP Content-Length 问题。Windows 构建只在当前进程设置 `TrackFileAccess=false`；Android 构建恢复现有用户级 Gradle/Pub cache 设置，没有写入仓库配置。

Android 附件保存使用应用自有 `ACTION_CREATE_DOCUMENT` + `ContentResolver`，实际字节写入在单线程 `ExecutorService` 执行，不接收或返回 raw filesystem path。engine teardown 对 writing 阶段使用 orderly shutdown，不中断已接受写入、不在 teardown 后回调；写入失败对本次 URI best-effort delete。无新依赖 Kotlin contract 用阻塞 fake writer 验证成功写不被中断、失败清理和回调抑制，并已绑定 Debug assemble。由于没有受控 Android 设备和慢速 document provider，真实慢 provider instrumentation 仍为 `NOT RUN`；现有 Dart 平台单测、Kotlin contract、Flutter 全量测试和 Android Debug 构建均已执行。

Android 构建输出一条已有工具链兼容提示：当前 SDK 处理器理解 XML 到版本 3，但遇到版本 4；构建仍 exit 0。应在独立工具链维护任务中对齐 Android Studio 与 command-line tools，不在本阶段升级依赖。

## 最终门禁与仓库安全

文档更新后的最终 `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1` 完整执行并以 exit 0 结束。门禁内证据为：Dart 138 files/0 changed、Flutter analyze 无问题（3.7 s）、Flutter 179 passed、Ruff 150 files formatted/check 通过、Django 0 issues、迁移 `No changes detected`、阶段四合同 35 passed、SQLite 276 passed/1 PostgreSQL 专用 skip（27.69 s）、严格 OpenAPI 0 warnings、两份 Compose config、Redis `PONG`、PostgreSQL 273 passed/4 Windows 专用 skip（34.83 s）、Release script contracts 与 Repository safety baseline 通过。

最终 gate 后的 `git diff --check` 为 exit 0，仅输出既有 LF→CRLF 工作区提示；独立 `scripts/repository-safety.ps1` 为 exit 0，并输出 `Repository safety baseline passed.`。构建产物和工具缓存仍由 `.gitignore` 排除；任务未创建 commit。

## 关注项

- 本地文件存储仍需要运营方制定数据库/附件一致性备份恢复、容量告警、法定保留期和物理清理审批。
- 未实现病毒扫描、对象存储、外链、在线预览、文件版本、自动物理清理或自助恢复。
- Android 真实慢 document provider instrumentation 未运行；原因和已完成替代验证见上文。
