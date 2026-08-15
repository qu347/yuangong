# AGENTS.md

## 仓库结构

- `apps/employee_app/`：Flutter Android/Windows 客户端。
- `backend/`：Django 模块化单体。
- `config/`：Flutter 环境 JSON。
- `deploy/`：Docker Compose 与镜像。
- `docs/`：架构、API、安全、ADR 和计划。
- `scripts/`：PowerShell 开发入口。

## 修改前必读

先读 `README.md`、`docs/architecture.md`、`docs/development.md`、`docs/security-baseline.md` 和适用子目录的 `AGENTS.md`。复杂任务先更新 `docs/plans/`。架构变化新增或更新 ADR；API 变化同步更新测试、OpenAPI 与 `docs/api-conventions.md`。

## 常用命令

```powershell
.\scripts\bootstrap.ps1
.\scripts\check.ps1
.\scripts\run-backend.ps1
.\scripts\run-flutter-windows.ps1
.\scripts\run-flutter-android.ps1
```

## 工程约束

- 当前只支持 Windows 与 Android，不创建 iOS、Web、macOS、Linux。
- Flutter 只用 Riverpod、go_router、Dio；Widget 不直接访问网络或 Secure Storage。
- Django View 保持精简，数据库变化必须有迁移，API 变化必须有测试。
- 不提前实现登录、CRUD、考勤、审批、权限等完整业务。

## 安全与完成定义

- 不提交 `.env`、Token、证书、签名、生产密钥或真实员工数据。
- 不记录密码、Token 或敏感个人信息。
- 格式化、静态检查、测试和适用平台构建全部通过，或明确记录 `NOT RUN` 与原因。
- 不跳过失败测试，不把未运行命令描述为成功，不自动创建 commit。
