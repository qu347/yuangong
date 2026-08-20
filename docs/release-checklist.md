# 内部试用发布检查清单

## 发布身份决策门

- [ ] 正式产品全称与简称已由公司确认。
- [ ] 公司法定名称、反向域名、Android `applicationId`/`namespace` 已确认。
- [ ] Windows ProductName、InternalName、Publisher Display Name、Publisher CN 与版权文本已确认。
- [ ] 支持邮箱与正式 HTTPS API URL 已确认。
- [ ] `scripts/validate-release-identity.ps1` 在严格模式退出 0。

未满足以上条件时只能生成 `NON-DISTRIBUTABLE` ValidationOnly 产物。

## 安全配置

- [ ] production `check --deploy` 通过，且 Django、JWT、账号 Token、审计归档使用不同密钥。
- [ ] PostgreSQL、Redis、HTTPS、CORS/Host 和 SMTP 配置经过目标环境验证。
- [ ] Mailpit、LocMem、SQLite、HTTP API 和通配 Host/CORS 未进入 production。
- [ ] SMTP staging 探针由授权人员确认，日志不含邮件正文、邀请码或重置码。

## 数据与审计

- [ ] 迁移前后 User、Employee、AuditEvent 和账号安全表计数已记录。
- [ ] 审计 CSV 权限、上限、公式注入防护与导出自身审计已验证。
- [ ] 归档 manifest、SHA-256、HMAC、篡改检测与不删除 AuditEvent 已验证。
- [ ] 公司法定保留期限和未来清理审批流程已明确；当前不自动删除。

## Android

- [ ] 正式 keystore 由授权保管方提供，未进入 Git。
- [ ] Release APK 签名、证书 SHA-256、版本、包名、文件 SHA-256 已验证。
- [ ] 在目标设备安装并确认 PID、前台 MainActivity 与 FATAL=0。
- [ ] 一次性验证证书构建明确标记 `NON-DISTRIBUTABLE`，不上传或分发。

## Windows

- [ ] 安装包格式已由公司决定；本阶段不自行选择 MSIX/MSI/NSIS/Inno Setup。
- [ ] 正式 PFX、时间戳服务和 Publisher 已授权，证书未进入 Git。
- [ ] Release ZIP、EXE 进程、窗口响应、正常退出与 SHA-256 已验证。
- [ ] 无正式签名时明确标记 `UNSIGNED / NON-DISTRIBUTABLE`。

## 自动化与交付

- [ ] `scripts/check.ps1` 退出 0，SQLite/PostgreSQL/Redis/OpenAPI/Flutter/Compose 均有真实结果。
- [ ] `scripts/verify-release-artifacts.ps1` 对最终 manifest 退出 0。
- [ ] Git 工作树干净，安全扫描无禁止文件或私钥头。
- [ ] GitHub required checks、审批者、visibility 与分发渠道已获得外部授权。
- [ ] 未创建未授权的 tag、GitHub Release、商店上传或 MDM 分发。
