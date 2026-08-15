# 下一步建议

1. 提供 Flutter stable，在本机记录准确版本并生成真实 `pubspec.lock`，运行 format/analyze/test 与双平台 Debug build。
2. 安装 Docker Desktop，验证 Compose、PostgreSQL healthcheck、Redis healthcheck 与三条 API。
3. 由产品、人事、安全共同关闭 `OPEN_DECISIONS.md` 中与认证和敏感数据相关的事项。
4. 设计最小认证切片，只实现登录、注销和后端权限拒绝测试，不同时开展员工 CRUD。
5. 认证稳定后，先交付组织架构只读查询，再设计员工档案字段与权限边界。
6. 为 Android 真机与 Windows 桌面建立可重复的手工验收清单。
