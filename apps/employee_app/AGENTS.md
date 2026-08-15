# Flutter 工作规则

- 使用 feature-first 结构：Presentation -> Riverpod Provider/Controller -> Repository -> Dio/Platform Service。
- 只使用 Riverpod 作为状态管理，go_router 作为路由，Dio 作为 HTTP 客户端。
- Widget 不直接调用网络或 Secure Storage；用户可见错误必须为简体中文。
- API 地址只来自 `AppConfig` 与 Dart define JSON，不在页面硬编码。
- 响应式断点为 900：桌面 NavigationRail，移动端 NavigationBar。
- 修改客户端后必须运行 format、analyze、test，并验证 Android 与 Windows；无法运行时明确标记 `NOT RUN`。
- 不创建 iOS、Web、macOS 或 Linux 文件，不配置 Android Release 签名。
- 日志不得包含 Token、密码、完整响应或敏感员工数据。
