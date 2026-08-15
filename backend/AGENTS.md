# Django 工作规则

- 保持 Django 模块化单体，业务 app 统一放在 `modules/`。
- View 只处理 HTTP 边界；复杂业务应放在清晰、可测试的服务或模型边界中。
- 数据库模型修改必须包含迁移；自定义用户模型保持 `accounts.User`。
- API 修改必须包含 pytest 测试，并同步 OpenAPI 与 `docs/api-conventions.md`。
- 所有权限最终由后端控制，客户端状态不能作为授权依据。
- 不在日志、异常响应或测试数据中记录敏感个人信息、密码、Token 或数据库凭据。
- 使用 Ruff，不叠加 Black、isort 或 Flake8。
- 完成前运行 Ruff format/check、Django check 与 pytest；不得跳过失败测试。
