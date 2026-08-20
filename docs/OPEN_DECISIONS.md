# 未决事项

以下事项均为“发布前必须确认”，当前默认值只用于可逆的本地开发。

| 事项 | 当前处理 | 发布前要求 |
| --- | --- | --- |
| 公司正式应用名称 | 界面暂用“企业员工管理系统” | 确认品牌、简称与版权信息 |
| Android 正式 applicationId | `com.yourcompany.employee_app` | 必须替换 applicationId、namespace 与相关应用标识 |
| 正式 API 域名 | 未配置 | 确认 HTTPS 域名、证书与网络边界 |
| 生产身份源 | 当前稳定 username + 账号邮箱登录；不使用工号别名 | 决定是否继续本地账号或接入 AD/LDAP/SSO；迁移不得破坏现有稳定 username |
| 生产邮件供应商 | 本地仅使用 Mailpit | 选择受控 SMTP/API 供应商、域名、退信与密钥轮换方案 |
| 审计保留与导出 | system_admin 可受控导出；可生成 SHA/HMAC 归档；默认无限期且不删除 | 明确法定保留期限、正式归档介质、访问审批和未来双人清理流程 |
| 是否支持公司外网访问 | 未决定 | 完成风险评估、访问控制与审计设计 |
| Android 内部分发方式 | 未决定 | 确认 MDM、企业分发或受控下载渠道 |
| Windows 安装包格式 | 未决定 | 确认 MSIX、MSI 或其他企业软件分发格式 |
| Android 正式签名 | 当前仅一次性 ValidationOnly 证书 | 由授权保管方提供正式 keystore、别名和轮换/吊销方案 |
| Windows 正式签名 | 当前 ZIP 未签名且不可分发 | 提供正式 PFX、Publisher CN 与时间戳服务 |
| GitHub 仓库可见性 | 当前为 public，尚未授权调整 | 明确源码是否允许公开并评估既有 fork/历史风险 |
| main 保护与审批者 | 当前无保护且只有一名直接协作者 | 至少确认第二名审查者，再授权 ruleset/branch protection |
| 是否接入 AD/LDAP | 未决定 | 盘点现有目录服务与账号生命周期 |
| 考勤打卡方式 | 未决定 | 确认办公网、设备、二维码或其他合规方式 |
| 敏感员工字段范围 | 未决定 | 由法务、安全与人事共同确认最小必要范围 |

这些决定未完成前，不得把 ValidationOnly 构建、production 示例或本地 smoke 描述为正式生产发布。
