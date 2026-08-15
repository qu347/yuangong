# 企业员工管理系统基础框架设计

日期：2026-08-14
状态：已批准（以用户提供的工程任务说明及“读取并执行”指令为批准依据）

## 目标与边界

在空工作区中建立一个面向 Windows 与 Android 的企业员工管理系统基础工程。工程需要可读、可测试、可协作，并通过唯一的真实联通能力——Django Health API 与 Flutter 健康状态卡——证明前后端边界有效。本阶段不实现登录、员工 CRUD、考勤、审批、权限等完整业务。

## 已比较的实施方式

1. **完全依赖本机生成器**：使用 `flutter create`、Django 命令和包管理器生成全部文件。优点是模板与 SDK 完全一致；缺点是当前 Flutter、Dart、Docker 和系统 Python 不在 PATH，无法完成。
2. **完全手写所有生成产物**：不依赖工具写出全部源代码、平台 runner 与锁文件。优点是立即得到完整目录；缺点是伪造 `pubspec.lock` 或声称构建成功会降低可信度。
3. **混合脚手架（采用）**：使用项目可访问的 Python 3.12 完成后端创建、依赖安装和测试；Flutter 写入业务源码、测试、Android/Windows runner 骨架及依赖清单，但只有实际运行 Flutter 工具后才生成 `pubspec.lock` 并确认构建。所有不可执行项标记为 `NOT RUN`。

## 架构

- Flutter 采用 feature-first 组织，数据流为 `Presentation -> Riverpod Controller -> Repository -> Dio API Client / Platform Service`。
- `go_router` 统一六个一级入口；宽度小于 900 使用 `NavigationBar`，否则使用 `NavigationRail`。
- Django 采用模块化单体，业务模块位于 `backend/modules/`，配置分为 base、development、test、production。
- PostgreSQL 是持久化数据库；Redis 仅作为预留基础设施，不成为业务启动依赖。
- API 统一使用 `/api/v1/`；健康检查只返回服务状态、版本和数据库状态，不泄露连接信息。

## 关键组件与数据流

1. `AppConfig` 从 `String.fromEnvironment` 读取环境与 API 地址。
2. `ApiClient` 持有 Dio；`HealthRepository` 请求 `/health/` 并将网络/协议错误转换为统一 Failure。
3. Riverpod `HealthController` 管理加载、成功和失败状态；Dashboard 仅观察状态并渲染。
4. Django health view 使用数据库游标执行轻量查询，正常返回 200，数据库异常返回 503。
5. drf-spectacular 提供 schema；开发环境开放 Swagger，生产环境由显式环境变量决定。

## 错误与安全

- Flutter 不向用户展示堆栈、数据库信息或敏感请求内容，网络失败显示中文消息并允许重试。
- Django 生产设置要求显式密钥、主机、CORS 和数据库变量；健康接口吞掉数据库异常细节。
- `.env`、密钥、签名文件、虚拟环境和构建产物均被忽略。
- 测试只使用虚构数据，不引入真实员工信息。

## 测试策略

- 后端：用户模型、健康接口成功/失败、OpenAPI schema、CORS 配置与 system check。
- Flutter：AppConfig、HealthRepository、Dashboard、响应式导航和启动 smoke test；全部使用替身，不访问公网或真实后端。
- 工程：Ruff、Dart format、Flutter analyze/test、Windows/Android debug build、Docker Compose config。
- 当前缺少 Flutter 与 Docker，因此对应命令必须保留为 `NOT RUN`，不得伪报成功。

## 范围自审

- 未引入微服务、Celery、Channels、云服务、JWT、文件上传或完整业务模型。
- Android applicationId、正式域名、登录标识等未确认事项统一进入 `docs/OPEN_DECISIONS.md`。
- 设计与用户指定的目录、平台和技术栈一致，没有额外平台目录。

## 提交说明

用户明确要求本任务不自动创建 Git commit，因此设计文档只写入工作区，不提交。
