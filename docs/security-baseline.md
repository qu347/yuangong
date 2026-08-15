# 安全基线

## 密钥与配置

- `.env`、私钥、证书、keystore、`key.properties` 与生产域名不得提交。
- `.env.example` 只包含明确的开发值；生产环境缺少关键变量时必须拒绝启动。
- Android 本阶段不配置 Release 签名，Windows 不创建正式签名安装包。

## 认证与授权

- 本阶段不实现登录与 Token 流程。
- 未来所有授权以 Django 后端判断为准，客户端隐藏按钮不构成权限控制。
- 登录标识、AD/LDAP 与角色模型在 `OPEN_DECISIONS.md` 确认前不得固化。

## 数据与日志

- 不在日志中输出密码、Token、身份证、工资、完整响应或数据库连接信息。
- 测试只使用虚构数据。
- 错误响应只返回稳定错误码与用户安全消息，不返回堆栈。

## 网络

- Staging 与 Production 只允许 HTTPS。
- Android cleartext HTTP 只由 `android/app/src/debug` 下的 manifest 与 Network Security Configuration 开启；Release 主清单不得引用该配置或全局允许明文流量。
- Debug HTTP 只用于访问本地开发 API，不得传输登录凭据、Token 或敏感员工数据。
- `0.0.0.0:8000` 只用于可信开发局域网；应配置 Windows 防火墙并避免公共网络暴露。
- CORS 使用显式来源列表，不允许通配所有来源。

## 依赖与变更

- 依赖升级必须检查发布说明、安全公告与平台最低版本。
- 数据库修改必须有迁移，API 修改必须有测试与文档。
- CI 不使用生产密钥，不上传 APK 或安装包到外部服务。
