# ADR-0008：产品能力完善与企业使用体验增强

- 状态：Accepted
- 日期：2026-08-20
- 适用阶段：第五阶段产品能力完善

## 背景

阶段四已经完成账号安全、审计治理、生产配置合同和内部试用构建验证。现有客户端登录后仍进入员工列表，Dashboard 只是连通性占位页；部门只提供扁平目录；Employee 只包含基础目录字段；系统没有统一搜索、HR 聚合统计或用户通知。本阶段在不引入新基础设施、不扩展考勤/审批/薪资等业务的前提下，把这些能力补齐为企业内部正式试用所需的工作台体验。

## 决策

### Dashboard 与统计

在既有 `common` 模块新增 `GET /api/v1/dashboard/summary/` 和 `GET /api/v1/statistics/hr/`。两者只执行数据库聚合，不逐行查询。Dashboard 对所有已认证角色开放基础目录计数；只有具备 `audit.view_auditevent` 的 HR/system 管理员获得最近操作。HR 统计只允许 HR/system 管理员访问，返回部门人数、岗位数量、入职趋势，以及仅在档案存在数据时返回的性别和年龄分布。所有响应排除工资、身份证、家庭住址、健康信息和其他敏感字段。

### 组织树

在 `organizations` 新增 `GET /api/v1/departments/tree/`。服务一次读取部门并用聚合注解获得员工人数，然后在内存中按 `sort_order, code` 组装树；不递归访问 ORM。模型与树服务共同拒绝循环，最大深度为 12。超过限制返回稳定的安全校验错误，不产生部分树。

### 员工档案边界

Employee 增加可选的 `avatar_url`、`gender`、`birthday`、`office_location`、`manager` 和 `description`。头像只保存 HTTPS URL，本阶段不实现上传。`manager` 是可空自关联，使用 `SET_NULL`，禁止本人及循环汇报关系。生日和性别只用于授权 HR 统计；普通员工可以读取目录安全字段，但不提供批量生日或年龄搜索。禁止加入身份证、银行卡、工资、家庭住址和健康信息。

### 全局搜索

在 `common` 新增 `GET /api/v1/search/`，支持员工、部门、岗位三类结果，参数为 `q`、`page`、`page_size`，默认 20、最大 50。查询只使用 Django ORM 参数绑定和既有可见目录，按固定类型顺序与稳定字段排序后分页。空查询返回 400，不接受客户端 SQL、排序字段或任意模型名。员工结果只包含 UUID、姓名/工号和组织摘要。

### 通知中心

在 `accounts` 新增 `Notification`，字段为 UUID、user、title、content、read、created_at。API 仅允许当前用户列出自己的通知和通过 `PATCH /api/v1/notifications/{id}/read/` 标记已读；不存在跨用户读取、创建、删除、实时推送、WebSocket 或消息队列。列表响应包含 `unread_count` 和受限分页结果。

### 权限与数据范围

继续使用 Django Group/model permissions，不建立第二套权限。Dashboard、组织树、全局搜索、个人通知使用 `IsAuthenticated` 和对象所有权；HR 统计使用现有 `employees.view_employee` 加管理角色判断；员工档案写入继续由 `employees.change_employee` 控制。Flutter capability 只控制入口显示，不构成授权边界。

### 性能目标

提供幂等的虚构性能数据命令，按固定前缀补齐 100 部门、500 岗位和 10,000 员工，不删除或修改现有业务数据。员工搜索目标小于 500ms、分页小于 300ms、Dashboard 小于 500ms。Employee 的姓名、邮箱、状态/部门和组织外键使用明确索引；列表/detail 使用 `select_related`，树使用单次聚合查询。测量结果记录数据库、数据量、热身方式与机器环境，未达到目标不得描述为通过。

### Flutter 体验

登录后进入 `/dashboard`。继续复用唯一 Riverpod、go_router、Dio 与安全存储链路；新增 feature-first 的 Dashboard、全局搜索、组织树和通知 repository/controller/page。Windows 在侧栏和顶部提供入口并使用网格卡片，Android 使用滚动卡片、搜索按钮和折叠树。新增页面必须具有 loading、empty、error、retry、success 状态；写操作禁用重复提交。

第五阶段增量补全继续复用 `GET /api/v1/statistics/hr/`，在 Flutter 新增仅 HR/system capability 可进入的 `/statistics` 页面。图表使用 Material 卡片、`LinearProgressIndicator` 和比例布局表达部门人数、岗位总量、入职趋势、性别与年龄分布，不增加第三方图表依赖。客户端入口仍只用于体验控制，后端 `CanViewHrStatistics` 保持最终授权。

组织树节点通过 Riverpod family provider 调用既有员工分页接口，并固定传入所选部门 UUID；成员弹层覆盖 loading、empty、error/retry、success，只展示目录安全字段。该交互不修改部门或员工权限模型。

员工详情在 `avatar_url` 为非空 HTTPS 地址时使用网络图片；空地址、非 HTTPS 地址或图片加载失败均降级为姓名首字头像，且不记录 URL、响应或图片错误内容。全局搜索保持现有 ORM/API，只在员工安全摘要中补充工作邮箱，并在客户端以员工、部门、岗位固定顺序分组展示。

### 测试策略

后端先写失败 pytest，覆盖权限、聚合正确性、空数据、树深度/循环/N+1、档案兼容与经理校验、搜索分页/过滤、通知所有权和查询数量。Flutter 先写失败的 repository/controller/widget 测试，覆盖解析、加载、空、错误、重试和跳转。完成前运行 SQLite、PostgreSQL、OpenAPI 严格验证、Flutter format/analyze/test、Windows/Android 构建和适用的真实设备/模拟器验收。

## 结果与限制

- 系统获得企业工作台、目录树、增强档案、统一搜索、HR 统计和轻量通知。
- 本阶段不部署公网、不接入外部身份源、不实现实时通知或完整 HR 业务。
- 性别、生日和头像 URL 均为可选字段；历史数据无需回填。
- 正式品牌、签名、SMTP、分发和敏感字段合规范围继续由 `OPEN_DECISIONS.md` 管理。
