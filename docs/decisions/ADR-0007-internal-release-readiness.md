# ADR-0007：生产安全合同、内部试用构建与仓库治理

- 状态：Accepted
- 日期：2026-08-19
- 适用阶段：第四阶段内部试用交付准备

## 背景

第三阶段已具备本地双平台构建、Docker 开发环境和六 job CI，但生产 settings、密钥解耦、签名合同、发布 manifest、生产容器示例和仓库治理仍不完整。正式公司身份、域名、证书、SMTP、分发渠道和审计法定期限均未提供，不能被猜测。

## 生产密钥与配置

生产必须显式提供 Django secret、独立 JWT signing key、PostgreSQL、Redis、HTTPS API URL、通用 SMTP、账号一次性 Token keyring、审计归档 keyring 和仓库外归档目录。`DEBUG=False`；拒绝 SQLite、LocMem、Mailpit、HTTP API、通配 ALLOWED_HOSTS/CORS、TLS+SSL 同开、`.invalid` 发件人和不安全默认值。

SimpleJWT `SIGNING_KEY` 使用 `JWT_SIGNING_KEY`。实际轮换会使全部旧 JWT 失效，运维必须在维护窗口撤销 AccountSession 并要求重新登录；第四阶段只实现配置和检查合同，不对生产执行轮换。

邀请码/重置码采用带 key ID 的格式 `<kid>.<random>`。新行保存 `token_key_id` 和 active key 摘要；验证从 raw token 解析 kid 后精确选择一把 key，不遍历 keyring。旧行 `token_key_id=NULL` 使用短期 legacy Django secret 路径；已使用/撤销状态仍先行拒绝。迁移不重算现有 digest。`account_token_key_report` 只输出 key ID/有效数量/legacy 数量/最晚过期时间。

## 生产邮件

development 只用 Mailpit，tests 只用 locmem，production 只实现供应商无关 SMTP 合同。没有真实 SMTP 凭据、测试收件人和发送授权时，staging probe 为 NOT RUN，不能用 Mailpit 冒充。

## 发布身份门

严格身份检查拒绝 `com.yourcompany.*`、占位 Windows company/publisher、HTTP API、无效 SemVer/build number、缺失支持邮箱。用户未提供正式值前不修改 applicationId、namespace、Windows publisher 或品牌。

允许显式 `-ValidationOnly -AllowDevelopmentPlaceholders` 做构建路径验证；此模式仍要求 HTTPS validation API 配置，所有目录、ZIP、APK 和 manifest 必须含 `NON-DISTRIBUTABLE`，且不得上传、tag 或创建 Release。

## Android 签名合同

Release Gradle 配置只从 `ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` 读取，缺少任一项立即失败，绝不回退 Debug keystore。正式 keystore 不入库。

ValidationOnly 可在系统临时目录使用 `keytool` 生成一次性 keystore，只验证 Release signing path；脚本不打印密码，构建后删除 keystore。APK 必须验证签名、证书摘要、applicationId、versionName/versionCode、SHA-256，并在 `employee_api36` 安装运行；仍因占位身份标记 NON-DISTRIBUTABLE。

## Windows 构建合同

构建标准 Flutter Windows Release 目录并压缩 ZIP；记录 SHA-256、版本、完整 Git SHA、UTC 时间和签名状态。只有提供 `WINDOWS_SIGNING_CERT_PFX`、密码和 timestamp URL 时才允许调用签名；本阶段没有真实证书，状态为 `UNSIGNED / NON-DISTRIBUTABLE`。不自行选择 MSIX/MSI/Inno Setup/NSIS。

## 生产容器合同

新增生产 Dockerfile/Compose example：Gunicorn、非 root、无 Mailpit、PostgreSQL/Redis 不公开宿主端口、healthcheck/restart、显式 secrets 环境合同，不自动执行 destructive migrate。它只证明本地 production-like smoke，不代表生产部署。

## GitHub 与供应链治理

仓库当前 public、main 未保护、无 ruleset，仅一名直接协作者。secret scanning 与 push protection 已启用，Dependabot security updates 关闭，CodeQL 尚无分析，Actions 允许所有 actions 且未要求 SHA pinning。

仓库增加 SECURITY、Dependabot（pip/pub/github-actions）、强化 PR 模板、治理文档、手动 release-readiness workflow 和 Python CodeQL workflow。CodeQL 只扫描官方支持的 Python，不声称支持 Dart；依据：<https://docs.github.com/en/code-security/concepts/code-scanning/codeql/codeql-code-scanning>。

不创建 CODEOWNERS：无法确认第二名协作者。也不应用 visibility、ruleset、branch protection、Secrets、Environments 或 Actions 权限变更。建议方案必须先解决第二审查者/唯一管理员锁定风险，再经用户单独授权执行。

## 版本与产物

继续使用 `0.1.0+1`，不自动创建 `v1.0.0`、tag 或 GitHub Release。manifest schema version 1 不含密钥、密码、本机用户名、环境转储或私有路径。

## 结果与限制

- 代码库可验证生产配置和内部试用构建路径，但不具备正式身份/证书/SMTP/分发授权。
- 所有 ValidationOnly 产物不可分发。
- 仓库公开风险和 main 未保护仍是明确外部治理项。
