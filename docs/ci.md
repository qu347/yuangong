# 持续集成与本地质量门禁

## GitHub Actions

`.github/workflows/ci.yml` 在推送到 `main`、面向 `main` 的 Pull Request 以及手动触发时运行。工作流只有 `contents: read` 权限，并按工作流与分支/PR 设置并发取消。

六个 job 的职责如下：

| job | 验证内容 |
| --- | --- |
| `backend-sqlite` | Ruff、Django check、迁移漂移、SQLite 全量 pytest、严格 OpenAPI 零警告 |
| `backend-postgresql` | PostgreSQL 17、Redis 8 PING、迁移与 PostgreSQL 全量 pytest |
| `flutter-quality` | Dart 格式、Flutter analyze、Flutter 全量测试 |
| `android-build` | JDK 21 下构建 Android Debug APK，并输出本次构建 SHA-256 |
| `windows-build` | 构建 Windows Debug EXE，并输出本次构建 SHA-256 |
| `repository-safety` | Compose 配置和禁止提交文件、私钥头、构建产物扫描 |

第三方 Action 必须使用完整 commit SHA 固定版本；更新 SHA 时同步更新 ADR-0005 和 CI 契约测试。Pull Request 不上传 APK、EXE 或其他构建产物，日志中的哈希只用于证明该次构建实际产生了文件。

## 本地全量门禁

先启动并等待开发服务健康：

```powershell
docker compose -f .\deploy\docker-compose.dev.yml up -d --build
```

再运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1
```

脚本使用仓库虚拟环境、当前 Flutter SDK、既有 Compose 服务和临时 PostgreSQL 测试数据库。它不删除或重建开发数据库/数据卷；PostgreSQL 测试用 one-off 容器在完成后自动回收，只读挂载 `.github`、`scripts` 和 `deploy` 以执行仓库契约测试。

单独运行仓库安全扫描：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\repository-safety.ps1
```

## 本地与远端状态的表述

本地命令通过只能表述为“本地验证通过”。只有 GitHub Actions 页面显示成功，才可表述为“远端 CI 通过”。若本机没有 `actionlint`，报告必须记录 `NOT RUN`，不得临时全局安装或把 YAML 解析测试冒充为 actionlint。
